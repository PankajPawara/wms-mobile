import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'engine_02a_optimization.dart';
import 'models/pipeline_result.dart';
import 'models/pipeline_stage.dart';
import '../services/memo_ocr_engine.dart' show OcrWord;

class TableGeometryOutput {
  final int topY;
  final int bottomY;
  final int leftX;
  final int rightX;
  final int imageWidth;
  final int imageHeight;
  final List<OcrWord> allWords; // Passed down to prevent re-running OCR

  TableGeometryOutput({
    required this.topY,
    required this.bottomY,
    required this.leftX,
    required this.rightX,
    required this.imageWidth,
    required this.imageHeight,
    required this.allWords,
  });

  Map<String, dynamic> toJson() {
    return {
      'topY': topY,
      'bottomY': bottomY,
      'leftX': leftX,
      'rightX': rightX,
      'imageWidth': imageWidth,
      'imageHeight': imageHeight,
      'wordCount': allWords.length,
    };
  }
}

class Engine04TableDetection {
  static final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  static Future<PipelineResult<TableGeometryOutput>> detect(OptimizationOutput input) async {
    final stopwatch = Stopwatch()..start();
    final errors = <String>[];

    try {
      // 1. Get image dimensions
      final bytes = await input.optimizedImage.readAsBytes();
      final image = await compute(_decodeBytes, bytes);
      if (image == null) throw Exception('Could not decode optimized image');
      final imageWidth = image.width;
      final imageHeight = image.height;

      // 2. Run OCR on the full optimized image
      final inputImage = InputImage.fromFile(input.optimizedImage);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      final words = <OcrWord>[];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            words.add(OcrWord(
              text: element.text,
              left: element.boundingBox.left.toInt(),
              top: element.boundingBox.top.toInt(),
              right: element.boundingBox.right.toInt(),
              bottom: element.boundingBox.bottom.toInt(),
            ));
          }
        }
      }

      if (words.isEmpty) {
        throw Exception("No OCR words found in optimized input.");
      }

      // 3. Find the header row by looking for key headers (SR, PART, DESCRIPTION)
      int headerBottomY = 0;
      bool headerFound = false;

      final sortedByY = List<OcrWord>.from(words)..sort((a, b) => a.top.compareTo(b.top));
      
      for (final w in sortedByY) {
        final text = w.text.toUpperCase();
        if (text.contains('DESCRIPTION') || text.contains('PART') || text.contains('QTY') || text.contains('M.R.P')) {
          int cy = (w.top + w.bottom) ~/ 2;
          
          final bandWords = words.where((bw) {
            int bcy = (bw.top + bw.bottom) ~/ 2;
            return (bcy - cy).abs() <= 60; 
          }).toList();
          
          int headerMatches = 0;
          for (final bw in bandWords) {
            final t = bw.text.toUpperCase();
            if (t.contains('SR') || t.contains('S.R') || t.contains('PART') || 
                t.contains('DESC') || t.contains('QTY') || t.contains('LOC') || 
                t.contains('PACK') || t.contains('STOCK') || t.contains('MRP') || 
                t.contains('M.R.P')) {
              headerMatches++;
            }
          }

          if (headerMatches >= 3) {
            headerFound = true;
            int maxBottom = 0;
            for (final bw in bandWords) {
              if (bw.bottom > maxBottom) maxBottom = bw.bottom;
            }
            // Strict rule: table starts immediately after the lowest pixel of this header row.
            headerBottomY = maxBottom;
            break;
          }
        }
      }

      if (!headerFound) {
        errors.add("Warning: Could not confidently identify table header. Falling back.");
        headerBottomY = (imageHeight * 0.35).toInt(); 
      }

      int tableTopY = headerBottomY + 5;
      int tableBottomY = imageHeight; 
      
      for (final w in sortedByY.reversed) {
        final text = w.text.toUpperCase();
        if (text.contains('NET') || text.contains('AMOUNT') || text.contains('TOTAL')) {
          if (w.top > tableTopY) {
            tableBottomY = w.top - 10;
            break;
          }
        }
      }

      int minLeft = 999999;
      int maxRight = 0;
      for (final w in words) {
        if (w.top > tableTopY && w.bottom < tableBottomY) {
          if (w.left < minLeft) minLeft = w.left;
          if (w.right > maxRight) maxRight = w.right;
        }
      }
      
      if (minLeft == 999999) minLeft = 0;
      if (maxRight == 0) maxRight = imageWidth;

      final result = TableGeometryOutput(
        topY: tableTopY,
        bottomY: tableBottomY,
        leftX: minLeft,
        rightX: maxRight,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        allWords: words,
      );

      stopwatch.stop();
      return PipelineResult(
        data: result,
        timingMs: stopwatch.elapsedMilliseconds,
        confidence: 1.0,
        stage: PipelineStage.tableDetection,
        errors: errors,
      );
    } catch (e) {
      stopwatch.stop();
      errors.add(e.toString());
      return PipelineResult.failure(
        stage: PipelineStage.tableDetection,
        reason: e.toString(),
        timingMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  static img.Image? _decodeBytes(List<int> bytes) {
    return img.decodeImage(Uint8List.fromList(bytes));
  }
}
