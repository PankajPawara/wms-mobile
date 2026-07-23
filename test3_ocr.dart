import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

void main() async {
  final file = File('assets/test_images/test3.jpg');
  final inputImage = InputImage.fromFile(file);
  final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  
  final recognizedText = await textRecognizer.processImage(inputImage);
  
  for (final block in recognizedText.blocks) {
    for (final line in block.lines) {
      print('LINE: ${line.text} (Top: ${line.boundingBox.top}, Bottom: ${line.boundingBox.bottom})');
      for (final element in line.elements) {
        print('  WORD: ${element.text} (Top: ${element.boundingBox.top}, Bottom: ${element.boundingBox.bottom}, Left: ${element.boundingBox.left})');
      }
    }
  }
}
