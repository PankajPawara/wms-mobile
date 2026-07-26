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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<File> getAssetAsFile(String assetName) async {
    final byteData = await rootBundle.load('assets/test_images/$assetName');
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$assetName');
    await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    return file;
  }

  testWidgets('Dump OCR for test4', (tester) async {
    final file = await getAssetAsFile('test4.jpg');
    final acqOutput = AcquisitionOutput(originalImage: file, widthPx: 3000, heightPx: 4000, fileSizeMB: 2.0, source: 'test_asset');
    final e02Result = await Engine02Processing.processRaw(acqOutput);
    final e02aResult = await Engine02aOptimization.optimize(e02Result.data!);
    final e04Result = await Engine04TableDetection.detect(e02aResult.data!);

    print('=== TEST4 OCR WORDS ===');
    for (final word in e04Result.data!.allWords) {
      print('Word: [${word.text}] Y: ${word.top}');
    }
  });
}
