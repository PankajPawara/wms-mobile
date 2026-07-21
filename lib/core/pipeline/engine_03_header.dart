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

      // 4. Group words into horizontal lines to defeat ML Kit column separation
      final physicalLines = _reconstructPhysicalLines(allWords);

      // 5. Simple Line-Based Extraction
      final headerData = _extractSimple(physicalLines);

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

  /// Groups words into physical horizontal lines based on Y-coordinates
  static List<String> _reconstructPhysicalLines(List<OcrWord> words) {
    if (words.isEmpty) return [];
    
    // Sort words top-to-bottom
    final sorted = List<OcrWord>.from(words)..sort((a, b) => a.top.compareTo(b.top));
    
    final lines = <List<OcrWord>>[];
    List<OcrWord> currentLine = [sorted.first];
    lines.add(currentLine);

    for (int i = 1; i < sorted.length; i++) {
      final word = sorted[i];
      final currentLineCenter = (currentLine.first.top + currentLine.first.bottom) / 2;
      final wordCenter = (word.top + word.bottom) / 2;
      
      // If the vertical center is within 25 pixels, consider it the same line
      if ((wordCenter - currentLineCenter).abs() < 25) {
        currentLine.add(word);
      } else {
        currentLine = [word];
        lines.add(currentLine);
      }
    }

    // Sort each line left-to-right and join with a space
    return lines.map((line) {
      line.sort((a, b) => a.left.compareTo(b.left));
      return line.map((w) => w.text).join(' ');
    }).toList();
  }

  /// Extracts header fields using simple regex and line parsing since the structure is fixed.
  static Map<String, dynamic> _extractSimple(List<String> lines) {
    String customerName = '';
    String memoNo = '';
    String memoDate = '';
    String area = '';
    String phone = '';

    for (final line in lines) {
      final upper = line.toUpperCase();

      // M/S., SHREE NAVSHAKTI AUTO PARTS PANDESARA   MEMO No. : 11264
      if (upper.startsWith('M/S') && customerName.isEmpty) {
        // Find where the name actually starts
        final prefixMatch = RegExp(r'M/S\.?,?\s*').firstMatch(upper);
        if (prefixMatch != null) {
          String rawName = line.substring(prefixMatch.end).trim();
          
          // Since we reconstructed physical lines, "MEMO No." might be on the same line!
          // We must chop off the name if it hits another known label.
          final stopMatch = RegExp(r'\b(MEMO|DATE|AREA|PHONE|PH|MOB)\b', caseSensitive: false).firstMatch(rawName);
          if (stopMatch != null) {
            rawName = rawName.substring(0, stopMatch.start).trim();
          }
          
          customerName = rawName;
        }
      }

      // MEMO No. : 11264       IB05A
      if (upper.contains('MEMO NO')) {
        // extract the first sequence of digits that appears after "MEMO NO"
        final match = RegExp(r'MEMO\s*NO[^\d]*(\d+)', caseSensitive: false).firstMatch(line);
        if (match != null) {
          memoNo = match.group(1)!;
        }
      }

      // MEMO DATE : 21/07/2026
      if (upper.contains('MEMO DATE') || upper.contains('DATE')) {
        final match = RegExp(r'DATE[^\d]*([\d/]+)', caseSensitive: false).firstMatch(line);
        if (match != null) {
          memoDate = match.group(1)!.replaceAll(RegExp(r'[^\d/]'), '');
        }
      }

      // AREA       : UDHNA
      if (upper.contains('AREA')) {
        final match = RegExp(r'AREA[^A-Za-z]*([A-Za-z]+)', caseSensitive: false).firstMatch(line);
        if (match != null) {
          area = match.group(1)!.trim();
        }
      }

      // Find 10 digit phone anywhere
      if (phone.isEmpty) {
        final clean = line.replaceAll(RegExp(r'\D'), '');
        if (clean.length >= 10 && clean.startsWith(RegExp(r'[6-9]'))) {
          phone = clean.substring(0, 10);
        }
      }
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

