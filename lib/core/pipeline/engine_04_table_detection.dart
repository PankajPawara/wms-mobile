import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'engine_02a_optimization.dart';
import 'models/pipeline_result.dart';
import 'models/pipeline_stage.dart';
import 'models/ocr_word.dart';

class TableGeometryOutput {
  final int topY;
  final int bottomY;
  final int leftX;
  final int rightX;
  final int imageWidth;
  final int imageHeight;
  final bool hasHeader;
  final List<OcrWord> allWords; // Passed down to prevent re-running OCR

  TableGeometryOutput({
    required this.topY,
    required this.bottomY,
    required this.leftX,
    required this.rightX,
    required this.imageWidth,
    required this.imageHeight,
    required this.hasHeader,
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
        // Trigger if we find anything resembling a column header
        if (text.contains('DES') || text.contains('PART') || text.contains('PARI') || text.contains('QTY') || text.contains('M.R.P') || text == 'SR' || text == 'S.R') {
          int cy = (w.top + w.bottom) ~/ 2;
          
          final bandWords = words.where((bw) {
            int bcy = (bw.top + bw.bottom) ~/ 2;
            return (bcy - cy).abs() <= 100; // Expanded band to account for tilt
          }).toList();
          
          bool hasSr = false;
          bool hasPart = false;
          bool hasDesc = false;
          bool hasQty = false;
          bool hasMrp = false;
          bool hasOther = false;

          for (final bw in bandWords) {
            final t = bw.text.toUpperCase();
            if (t == 'SR' || t == 'S.R' || t == 'SR.') hasSr = true;
            else if (t.contains('PART') || t.contains('PARI') || t.contains('PRT') || t.contains('1ART')) hasPart = true;
            else if (t.contains('DESC') || t == 'DES' || t.contains('DSCR')) hasDesc = true;
            else if (t.contains('QTY') || t.contains('QTV')) hasQty = true;
            else if (t.contains('MRP') || t.contains('M.R.P')) hasMrp = true;
            else if (t.contains('LOC') || t.contains('PACK') || t.contains('STOCK') || t.contains('STK')) hasOther = true;
          }

          int headerScore = 0;
          if (hasSr) headerScore++;
          if (hasPart) headerScore++;
          if (hasDesc) headerScore++;
          if (hasQty) headerScore++;
          if (hasMrp) headerScore++;
          if (hasOther) headerScore++;

          // If we have at least 3 matches, and it includes PART or DESC, AND includes QTY or MRP, it's very likely the header
          // Alternatively, if it has 4 matches, it's definitely the header.
          if (headerScore >= 4 || (headerScore >= 3 && (hasPart || hasDesc) && (hasQty || hasMrp))) {
            headerFound = true;
            int maxBottom = 0;
            for (final bw in bandWords) {
              if (bw.bottom > maxBottom) maxBottom = bw.bottom;
            }
            headerBottomY = maxBottom;
            break;
          }
        }
      }

      if (!headerFound) {
        errors.add("Notice: No clear table header found. Setting table start to top of image.");
        headerBottomY = -5; // tableTopY will be 0
      }

      int tableTopY = headerBottomY + 5;
      int tableBottomY = imageHeight;  
      
      final bottomSearchLimit = imageHeight * 0.70; // Only look in the bottom 30% for footer

      for (final w in sortedByY.reversed) {
        if (w.top < bottomSearchLimit) {
          // If we've searched all the way up to 70% of the image and found no footer, stop searching.
          break;
        }

        final text = w.text.toUpperCase();
        // Check for exact phrases or safe words to avoid 'RR NET 5G' breaking the table
        if (text.contains('NET AMOUNT') || 
            text.contains('TOTAL') || 
            text == 'NET' || 
            text.contains('DISCOUNT') ||
            text == 'AMOUNT') {
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
        leftX: minLeft == 999999 ? 0 : minLeft,
        rightX: maxRight == 0 ? imageWidth : maxRight,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        hasHeader: headerFound,
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
