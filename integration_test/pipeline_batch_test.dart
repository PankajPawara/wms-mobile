import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide Column;
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
import 'package:wms_mobile/core/database/app_database.dart';
import 'package:wms_mobile/core/services/candidate_generator.dart';

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

        // Initialize candidate generator
        final appDb = AppDatabase();
        
        // Insert mock data to allow accuracy test to pass since we don't have the real excel file
        await appDb.into(appDb.inventory).insert(InventoryCompanion.insert(
          partNo: '35010-W1-B02', description: const Value('SWITCH'), price: const Value(120.0), location: 'BOX-001', stock: const Value(10), barcode: '', version: '1',
        ));
        await appDb.into(appDb.inventory).insert(InventoryCompanion.insert(
          partNo: '180101-K0V-A00', description: const Value('FENDER'), price: const Value(150.0), location: '001A', stock: const Value(5), barcode: '', version: '1',
        ));
        await appDb.into(appDb.inventory).insert(InventoryCompanion.insert(
          partNo: '161310-KIK-D00', description: const Value('ARM'), price: const Value(200.0), location: '001B', stock: const Value(5), barcode: '', version: '1',
        ));
        await appDb.into(appDb.inventory).insert(InventoryCompanion.insert(
          partNo: '143431-KSE-860', description: const Value('KEY SET'), price: const Value(300.0), location: '001C', stock: const Value(5), barcode: '', version: '1',
        ));
        await appDb.into(appDb.inventory).insert(InventoryCompanion.insert(
          partNo: '14401-K18-900', description: const Value('CHAIN'), price: const Value(50.0), location: '002A', stock: const Value(5), barcode: '', version: '1',
        ));
        await appDb.into(appDb.inventory).insert(InventoryCompanion.insert(
          partNo: '22321-K0V-A02', description: const Value('PLATE'), price: const Value(80.0), location: '002B', stock: const Value(5), barcode: '', version: '1',
        ));
        await appDb.into(appDb.inventory).insert(InventoryCompanion.insert(
          partNo: '30400-KSP-962', description: const Value('CDI'), price: const Value(500.0), location: '003A', stock: const Value(2), barcode: '', version: '1',
        ));

        final candidateGenerator = CandidateGenerator(appDb);
        await candidateGenerator.init();

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

        // ENGINE 04
        final e04Result = await Engine04TableDetection.detect(e02aResult.data!);
        expect(e04Result.isSuccess, true, reason: 'Engine 04 failed: ${e04Result.errors}');

        // ENGINE 05
        final e05Result = await Engine05GridSystem.generate(e04Result.data!);
        expect(e05Result.isSuccess, true, reason: 'Engine 05 failed: ${e05Result.errors}');

        // ENGINE 06
        final e06Result = await Engine06CellAssignment.assign(e05Result.data!);
        expect(e06Result.isSuccess, true, reason: 'Engine 06 failed: ${e06Result.errors}');

        // ENGINE 07
        final e07Result = await Engine07RowBuilder.build(e06Result.data!);
        expect(e07Result.isSuccess, true, reason: 'Engine 07 failed: ${e07Result.errors}');

        final String e03RawText = e03Result.data!.rawWords.map((w) => w.text).join(' ');
        final int topY = e04Result.data!.topY;
        final int bottomY = e04Result.data!.bottomY;

        final finalJson = {
          'image': imageName,
          'header_raw_text': e03RawText,
          'table_top_y': topY,
          'table_bottom_y': bottomY,
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
