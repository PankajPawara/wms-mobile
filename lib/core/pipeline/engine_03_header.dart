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

      // 4. Simple Line-Based Extraction
      final headerData = _extractSimple(recognizedText.text);

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

  /// Extracts header fields using simple regex and line parsing since the structure is fixed.
  static Map<String, dynamic> _extractSimple(String text) {
    String customerName = '';
    String memoNo = '';
    String memoDate = '';
    String area = '';
    String phone = '';

    final lines = text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    for (final line in lines) {
      final upper = line.toUpperCase();

      // M/S., SHREE NAVSHAKTI AUTO PARTS PANDESARA
      if (upper.startsWith('M/S') && customerName.isEmpty) {
        // Find where the name actually starts
        final prefixMatch = RegExp(r'M/S\.?,?\s*').firstMatch(upper);
        if (prefixMatch != null) {
          customerName = line.substring(prefixMatch.end).trim();
        }
      }

      // MEMO No. : 11264       IB05A
      if (upper.contains('MEMO NO')) {
        final parts = line.split(':');
        if (parts.length > 1) {
          // ' 11264       IB05A' -> split by space and take first
          final valParts = parts[1].trim().split(RegExp(r'\s+'));
          if (valParts.isNotEmpty) {
            memoNo = valParts.first.replaceAll(RegExp(r'[^\d]'), '');
          }
        }
      }

      // MEMO DATE : 21/07/2026
      if (upper.contains('MEMO DATE') || upper.contains('DATE')) {
        final parts = line.split(':');
        if (parts.length > 1) {
          memoDate = parts[1].trim().split(RegExp(r'\s+')).first;
          memoDate = memoDate.replaceAll(RegExp(r'[^\d/]'), '');
        }
      }

      // AREA       : UDHNA
      if (upper.contains('AREA')) {
        final parts = line.split(':');
        if (parts.length > 1) {
          area = parts[1].trim();
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

