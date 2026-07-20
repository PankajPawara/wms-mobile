import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:wms_mobile/core/services/sandbox_ocr_engine.dart';
import 'package:wms_mobile/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Test OCR Engine on images 1 to 5', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle();

    final tempDir = await getTemporaryDirectory();

    for (int i = 1; i <= 5; i++) {
      final assetName = 'test$i.jpg';
      try {
        print('--- Testing $assetName ---');
        final byteData = await rootBundle.load('assets/test_images/$assetName');
        final file = File('${tempDir.path}/$assetName');
        await file.writeAsBytes(byteData.buffer.asUint8List());

        final result = await SandboxOcrEngine.processImage(file);
        
        if (result.geometry != null) {
          print('Geometry detected:');
          print(jsonEncode(result.geometry!.toJson()));
        } else {
          print('No Geometry Detected!');
        }

        if (result.pickupJson != null) {
          print('Pickup JSON:');
          print(jsonEncode(result.pickupJson));
        } else {
          print('No Pickup JSON Generated!');
        }
        
      } catch (e) {
        print('Error processing $assetName: $e');
      }
    }
  });
}
