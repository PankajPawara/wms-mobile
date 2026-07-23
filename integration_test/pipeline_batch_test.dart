import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:wms_mobile/core/pipeline/engine_01_acquisition.dart';
import 'package:wms_mobile/core/pipeline/engine_02_processing.dart';
import 'package:wms_mobile/core/pipeline/engine_02a_optimization.dart';
import 'package:wms_mobile/core/pipeline/engine_03_header.dart';
import 'package:wms_mobile/core/pipeline/engine_04_table_detection.dart';
import 'package:wms_mobile/core/pipeline/engine_05_grid.dart';
import 'package:wms_mobile/core/pipeline/engine_06_cell.dart';
import 'package:wms_mobile/core/pipeline/engine_07_row.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<File> getAssetAsFile(String assetName) async {
    final byteData = await rootBundle.load('assets/test_images/$assetName');
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$assetName');
    await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    return file;
  }

  group('Pipeline Batch Test', () {
    testWidgets('Iterate over 5 test images and extract table JSON', (WidgetTester tester) async {
      final testImages = ['test1.jpg', 'test2.jpg', 'test3.jpg', 'test4.jpg', 'test5.jpg'];
      final allResults = [];

      for (String imageName in testImages) {
        print('========================================================================');
        print('PROCESSING $imageName');
        print('========================================================================');

        final file = await getAssetAsFile(imageName);

        // Mock Acquisition Output
        final acqOutput = AcquisitionOutput(
          originalImage: file,
          widthPx: 3000,
          heightPx: 4000,
          fileSizeMB: 2.0,
          source: 'test_asset',
        );

        // Engine 02
        final e02Result = await Engine02Processing.processRaw(acqOutput);
        if (!e02Result.isSuccess) {
          print('FAILED AT ENGINE 02: ${e02Result.errors}');
          continue;
        }

        // Engine 02A
        final e02aResult = await Engine02aOptimization.optimize(e02Result.data!);
        if (!e02aResult.isSuccess) {
          print('FAILED AT ENGINE 02A: ${e02aResult.errors}');
          continue;
        }

        // Engine 03
        final e03Result = await Engine03Header.extract(e02aResult.data!);
        if (!e03Result.isSuccess) {
          print('FAILED AT ENGINE 03: ${e03Result.errors}');
          continue;
        }

        // Engine 04
        final e04Result = await Engine04TableDetection.detect(e02aResult.data!);
        if (!e04Result.isSuccess) {
          print('FAILED AT ENGINE 04: ${e04Result.errors}');
          continue;
        }

        // Engine 05
        final e05Result = await Engine05GridSystem.generate(e04Result.data!);
        if (!e05Result.isSuccess) {
          print('FAILED AT ENGINE 05: ${e05Result.errors}');
          continue;
        }

        // Engine 06
        final e06Result = await Engine06CellAssignment.assign(e05Result.data!);
        if (!e06Result.isSuccess) {
          print('FAILED AT ENGINE 06: ${e06Result.errors}');
          continue;
        }

        // Engine 07
        final e07Result = await Engine07RowBuilder.build(e06Result.data!);
        if (!e07Result.isSuccess) {
          print('FAILED AT ENGINE 07: ${e07Result.errors}');
          continue;
        }

        final String e03RawText = e03Result.data!.rawWords.map((w) => w.text).join(' ');
        final int topY = e04Result.data!.topY;
        final int bottomY = e04Result.data!.bottomY;
        
        List<int?> getColBounds(String key) {
          try {
            final col = e05Result.data!.columns.firstWhere((c) => c.key == key);
            return [col.leftX, col.rightX];
          } catch (e) {
            return [null, null];
          }
        }

        final finalJson = {
          'image': imageName,
          'header_raw_text': e03RawText,
          'table_top_y': topY,
          'table_bottom_y': bottomY,
          'grid_cols': {
            'SR': getColBounds('SR'),
            'PART': getColBounds('PART'),
            'DESC': getColBounds('DESC'),
          },
          'header': e03Result.data!.headerData,
          'rows': e07Result.data!.rows.map((r) => r.toJson()).toList(),
        };

        allResults.add(finalJson);
        print(const JsonEncoder.withIndent('  ').convert(finalJson));
      }

      print('========================================================================');
      print('BATCH TEST COMPLETE');
      print('========================================================================');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
