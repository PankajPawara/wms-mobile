import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:wms_mobile/core/utils/local_ocr_parser.dart';
import 'package:wms_mobile/core/services/gemini_fallback_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Batch OCR and Gemini Fallback Test', (WidgetTester tester) async {
    // 1. Initialize environment
    await dotenv.load(fileName: ".env");

    // 2. Locate images from AssetManifest
    final extDir = await getExternalStorageDirectory();
    print('APP EXTERNAL DIR: ${extDir?.path}');
    
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final imagePaths = manifest.listAssets()
        .where((path) => path.startsWith('test_assets/rawfiles/') && 
                        (path.toLowerCase().endsWith('.jpg') || path.toLowerCase().endsWith('.jpeg')))
        .toList();
    
    print('Found ${imagePaths.length} image files in assets.');

    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final allResults = <String, dynamic>{};
    
    for (var i = 0; i < imagePaths.length; i++) {
      final assetPath = imagePaths[i];
      final fileName = assetPath.split('/').last;
      print('Processing [${i + 1}/${imagePaths.length}]: $fileName');

      try {
        final byteData = await rootBundle.load(assetPath);
        final file = File('${extDir?.path}/$fileName');
        await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));

        final inputImage = InputImage.fromFile(file);
        final recognizedText = await textRecognizer.processImage(inputImage);
        
        final rawDebugBuffer = StringBuffer();
        List<dynamic> allExtractedItems = [];
        Map<String, String> extractedHeader = {};

        for (int b = 0; b < recognizedText.blocks.length; b++) {
          final block = recognizedText.blocks[b];
          rawDebugBuffer.writeln('  [BLOCK $b] y=${block.boundingBox.top.toInt()}—${block.boundingBox.bottom.toInt()}');
          for (int l = 0; l < block.lines.length; l++) {
            final line = block.lines[l];
            rawDebugBuffer.writeln('    [LINE $l] y=${line.boundingBox.top.toInt()}  "${line.text}"');
          }
        }
        rawDebugBuffer.writeln();

        final result = LocalOcrParser.parseTable(recognizedText);
        allExtractedItems.addAll(result['items'] as List<dynamic>);
        if (result['header'] != null) {
          final header = result['header'] as Map<String, String>;
          if (header['customer']?.isNotEmpty ?? false) extractedHeader['customer'] = header['customer']!;
          if (header['area']?.isNotEmpty ?? false) extractedHeader['area'] = header['area']!;
          if (header['memo_no']?.isNotEmpty ?? false) extractedHeader['memo_no'] = header['memo_no']!;
        }

        bool needsFallback = false;
        if (extractedHeader['customer'] == null || extractedHeader['customer']!.isEmpty ||
            extractedHeader['area'] == null || extractedHeader['area']!.isEmpty ||
            extractedHeader['memo_no'] == null || extractedHeader['memo_no']!.isEmpty) {
          needsFallback = true;
        }
        for (final item in allExtractedItems) {
          if ((item['part_no'] == null || item['part_no']!.toString().isEmpty) ||
              (item['qty'] == null || item['qty'] == 0)) {
            needsFallback = true;
            break;
          }
        }

        Map<String, dynamic> finalData = {
          'header': extractedHeader,
          'items': allExtractedItems,
          'needs_fallback': needsFallback,
        };
        allResults[fileName] = finalData;

        if (needsFallback) {
          print('  Triggering Gemini Fallback for $fileName...');
          try {
            final geminiData = await GeminiFallbackService.correctOcrData(
              rawDebugBuffer.toString(),
              extractedHeader,
              allExtractedItems,
              imageFile: file,
            );
            
            finalData['gemini_header'] = geminiData['header'];
            finalData['gemini_items'] = geminiData['items'];
            allResults[fileName] = finalData;
          } catch (e) {
            print('  Gemini failed: $e');
            finalData['gemini_error'] = e.toString();
          }
          // Strict rate limit prevention: 5 seconds
          await Future.delayed(const Duration(seconds: 5));
        }

        // Incremental save
        final outFile = File('${extDir?.path}/rawfiles_results.json');
        await outFile.writeAsString(const JsonEncoder.withIndent('  ').convert(allResults));

      } catch (e, st) {
        print('  Error processing $fileName: $e');
        allResults[fileName] = {'error': e.toString(), 'stack': st.toString()};
      }
    }

    await textRecognizer.close();
    print('✅ Finished processing all images!');
    print('=== RESULT JSON BEGIN ===');
    print(const JsonEncoder.withIndent('  ').convert(allResults));
    print('=== RESULT JSON END ===');
  }, timeout: const Timeout(Duration(minutes: 60)));
}
