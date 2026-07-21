import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:math' as math;

import 'models/pipeline_result.dart';
import 'models/pipeline_stage.dart';
import 'engine_02a_optimization.dart';
import '../services/memo_ocr_engine.dart' show OcrWord;

/// Result of the Header Engine
class HeaderOutput {
  final File croppedHeaderImage;
  final Map<String, dynamic> headerData;
  final List<OcrWord> rawWords;

  const HeaderOutput({
    required this.croppedHeaderImage,
    required this.headerData,
    required this.rawWords,
  });
}

class Engine03Header {
  Engine03Header._();

  static final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  static Future<PipelineResult<HeaderOutput>> extract(OptimizationOutput input) async {
    final stopwatch = Stopwatch()..start();
    try {
      // 1. Load image and crop top 35%
      final bytes = await input.optimizedImage.readAsBytes();
      final image = await compute(_decodeBytes, bytes);
      if (image == null) throw Exception('Could not decode optimized image');

      final cropHeight = (image.height * 0.35).toInt();
      final cropped = img.copyCrop(image, x: 0, y: 0, width: image.width, height: cropHeight);

      // Save crop to temp file for ML Kit
      final tempDir = await getTemporaryDirectory();
      final cropPath = '${tempDir.path}/header_crop_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final cropFile = File(cropPath)..writeAsBytesSync(img.encodeJpg(cropped, quality: 90));

      // 2. Run ML Kit Text Recognition
      final inputImage = InputImage.fromFile(cropFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      // 3. Convert to OcrWord list
      final allWords = <OcrWord>[];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            allWords.add(OcrWord(
              text: element.text,
              left: element.boundingBox.left.toInt(),
              top: element.boundingBox.top.toInt(),
              right: element.boundingBox.right.toInt(),
              bottom: element.boundingBox.bottom.toInt(),
            ));
          }
        }
      }

      // 4. Spatial Extraction
      final headerData = _extractSpatial(allWords);

      stopwatch.stop();

      return PipelineResult(
        data: HeaderOutput(
          croppedHeaderImage: cropFile,
          headerData: headerData,
          rawWords: allWords,
        ),
        timingMs: stopwatch.elapsedMilliseconds,
        confidence: 0.85,
        stage: PipelineStage.header,
      );
    } catch (e) {
      stopwatch.stop();
      return PipelineResult.failure(
        stage: PipelineStage.header,
        reason: 'Header extraction failed: $e',
        timingMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  static img.Image? _decodeBytes(List<int> bytes) {
    return img.decodeImage(Uint8List.fromList(bytes));
  }

  /// Extracts header fields using spatial proximity instead of strict regex strings
  static Map<String, dynamic> _extractSpatial(List<OcrWord> words) {
    // Spatial search helpers
    OcrWord? findWordRegex(String pattern) {
      final reg = RegExp(pattern, caseSensitive: false);
      for (final w in words) {
        if (reg.hasMatch(w.text)) return w;
      }
      return null;
    }

    String grabWordsRightOf(OcrWord anchor, {int maxDistanceX = 600, int maxDistanceY = 20}) {
      final candidates = words.where((w) {
        if (w.left <= anchor.right) return false;
        if (w.left - anchor.right > maxDistanceX) return false;
        final yDiff = (w.top - anchor.top).abs();
        return yDiff <= maxDistanceY;
      }).toList();

      candidates.sort((a, b) => a.left.compareTo(b.left));
      
      // Stop collecting if there's a huge gap (next column) or another known label
      final result = <String>[];
      int lastRight = anchor.right;
      for (final w in candidates) {
        if (w.left - lastRight > 150) break; // gap too big
        if (w.text == ':' || w.text == '-') {
           lastRight = w.right;
           continue; // skip separators
        }
        // Stop if we hit another label
        if (RegExp(r'^(MEMO|DATE|AREA|M/S|PHONE|No)$', caseSensitive: false).hasMatch(w.text)) break;
        
        result.add(w.text);
        lastRight = w.right;
      }
      return result.join(' ');
    }

    // 1. Memo Number
    String memoNo = '';
    final memoLabel = findWordRegex(r'^MEMO');
    if (memoLabel != null) {
      // Sometimes "MEMO No. : 12345". Find the number to the right.
      memoNo = grabWordsRightOf(memoLabel, maxDistanceX: 400).replaceAll(RegExp(r'[^\d]'), '');
    }

    // 2. Date
    String memoDate = '';
    final dateLabel = findWordRegex(r'^DATE');
    if (dateLabel != null) {
      memoDate = grabWordsRightOf(dateLabel, maxDistanceX: 300).replaceAll(RegExp(r'[^\d/]'), '');
    }

    // 3. Area
    String area = '';
    final areaLabel = findWordRegex(r'^AREA');
    if (areaLabel != null) {
      area = grabWordsRightOf(areaLabel);
    }

    // 4. Phone
    String phone = '';
    final phoneLabel = findWordRegex(r'^(PHONE|PH|MOB)');
    if (phoneLabel != null) {
      phone = grabWordsRightOf(phoneLabel).replaceAll(RegExp(r'[^\d]'), '');
    } else {
      // Fallback: look for any 10-digit sequence anywhere in the header
      for (final w in words) {
        final clean = w.text.replaceAll(RegExp(r'\D'), '');
        if (clean.length >= 10 && clean.startsWith(RegExp(r'[6-9]'))) {
          phone = clean.substring(0, 10);
          break;
        }
      }
    }

    // 5. Customer Name (typically right after M/S., M/S, etc.)
    String customerName = '';
    final msLabel = findWordRegex(r'^M/S');
    if (msLabel != null) {
      customerName = grabWordsRightOf(msLabel, maxDistanceX: 800);
      // Clean up common artifacts
      customerName = customerName.replaceAll(RegExp(r'^[.,\s]+'), '');
    } else {
      // Fallback: It's often the largest text line near the top. We'll capture everything before "SHOP" or "NEAR".
      // Since this is hard without context, we will leave it empty for Gemini to fix if spatial fails.
    }

    return {
      'customerName': customerName,
      'memoNo': memoNo,
      'memoDate': memoDate,
      'area': area,
      'phone': phone,
    };
  }
}
