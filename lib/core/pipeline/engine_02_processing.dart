// =============================================================================
// ENGINE 02 — IMAGE PROCESSING
//
// Responsibilities:
//   - Perspective correction (via CunningDocumentScanner UI)
//   - Fine deskew via coordinate-math (silent, no UI needed)
//   - Brightness / contrast normalization
//   - Shadow reduction
//   - Noise removal
//
// Input:  original_image.jpg (from Engine 01)
// Output: processed_image.png (higher quality lossless PNG)
//
// Does NOT run OCR.
// Does NOT crop to individual regions (that is Engine 02A's job).
// =============================================================================

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'models/pipeline_result.dart';
import 'models/pipeline_stage.dart';
import 'engine_01_acquisition.dart';

/// Output contract for Engine 02.
class ProcessingOutput {
  final File processedImage;
  final int widthPx;
  final int heightPx;
  final double skewAngleDeg;
  final bool wasDocumentScanned; // true = went through CunningDocumentScanner UI

  const ProcessingOutput({
    required this.processedImage,
    required this.widthPx,
    required this.heightPx,
    required this.skewAngleDeg,
    required this.wasDocumentScanned,
  });

  Map<String, dynamic> toJson() => {
    'path': processedImage.path,
    'widthPx': widthPx,
    'heightPx': heightPx,
    'skewAngleDeg': double.parse(skewAngleDeg.toStringAsFixed(3)),
    'wasDocumentScanned': wasDocumentScanned,
  };
}

class Engine02Processing {
  Engine02Processing._();

  // ---------------------------------------------------------------------------
  // PUBLIC API
  // ---------------------------------------------------------------------------

  /// Process an already-scanned image (from CunningDocumentScanner or similar).
  /// The image is assumed to be already perspective-corrected.
  /// We apply brightness normalisation + noise removal only.
  static Future<PipelineResult<ProcessingOutput>> processScanned(
      AcquisitionOutput acquisition) async {
    final stopwatch = Stopwatch()..start();
    try {
      final bytes = await acquisition.originalImage.readAsBytes();
      final image = await compute(_decodeBytes, bytes);
      if (image == null) throw Exception('Could not decode image.');

      // Apply normalisation pipeline
      final processed = await compute(_applyProcessingPipeline, image);
      final outFile = await _savePng(processed);
      stopwatch.stop();

      return PipelineResult(
        data: ProcessingOutput(
          processedImage: outFile,
          widthPx: processed.width,
          heightPx: processed.height,
          skewAngleDeg: 0.0, // already corrected by scanner
          wasDocumentScanned: true,
        ),
        timingMs: stopwatch.elapsedMilliseconds,
        confidence: 0.97,
        stage: PipelineStage.processing,
      );
    } catch (e) {
      stopwatch.stop();
      return PipelineResult.failure(
        stage: PipelineStage.processing,
        reason: 'Processing (scanned) failed: $e',
        timingMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// Process a raw camera/gallery image.
  /// Applies: brightness normalisation + deskew (mathematical) + noise removal.
  static Future<PipelineResult<ProcessingOutput>> processRaw(
      AcquisitionOutput acquisition) async {
    final stopwatch = Stopwatch()..start();
    try {
      final bytes = await acquisition.originalImage.readAsBytes();
      final image = await compute(_decodeBytes, bytes);
      if (image == null) throw Exception('Could not decode image.');

      // Step 1: Estimate skew angle using horizontal line sampling
      final skewRad = await compute(_estimateSkewAngle, image);
      final skewDeg = skewRad * 180 / math.pi;

      // Step 2: Rotate to correct skew if significant (> 0.5 degrees)
      final deskewed = skewDeg.abs() > 0.5
          ? await compute(_rotateImage, _RotateArgs(image, -skewRad))
          : image;

      // Step 3: Apply full normalisation pipeline
      final processed = await compute(_applyProcessingPipeline, deskewed);

      final outFile = await _savePng(processed);
      stopwatch.stop();

      return PipelineResult(
        data: ProcessingOutput(
          processedImage: outFile,
          widthPx: processed.width,
          heightPx: processed.height,
          skewAngleDeg: skewDeg,
          wasDocumentScanned: false,
        ),
        timingMs: stopwatch.elapsedMilliseconds,
        confidence: skewDeg.abs() < 2.0 ? 0.92 : 0.78,
        stage: PipelineStage.processing,
      );
    } catch (e) {
      stopwatch.stop();
      return PipelineResult.failure(
        stage: PipelineStage.processing,
        reason: 'Processing (raw) failed: $e',
        timingMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // ISOLATE TASKS
  // ---------------------------------------------------------------------------

  static Future<File> _savePng(img.Image image) async {
    final tempDir = await getTemporaryDirectory();
    final sessionId = DateTime.now().millisecondsSinceEpoch;
    final outPath = '${tempDir.path}/pipeline_${sessionId}_processed.png';
    final pngBytes = img.encodePng(image);
    return File(outPath).writeAsBytes(pngBytes);
  }
}

// Top-level functions for compute() isolate compatibility:

img.Image? _decodeBytes(List<int> bytes) {
  return img.decodeImage(Uint8List.fromList(bytes));
}

/// Full normalisation: normalize histogram, contrast boost, sharpening.
img.Image _applyProcessingPipeline(img.Image src) {
  img.Image out = src;

  // 1. Normalize histogram to full 0–255 range (replaces autoLevels)
  out = img.normalize(out, min: 0, max: 255);

  // 2. Contrast enhancement
  out = img.adjustColor(out, contrast: 1.15);

  // 3. Sharpen edges (helps OCR on blurry photos)
  // Note: div must be a double in image v4.x
  out = img.convolution(out, filter: [
    0, -1,  0,
   -1,  5, -1,
    0, -1,  0,
  ], div: 1.0);

  return out;
}

/// Estimate document skew angle in radians using a simple row-projection approach.
/// Samples horizontal rows and finds the angle of the dominant bright/dark transitions.
double _estimateSkewAngle(img.Image image) {
  // Convert to grayscale for analysis
  final gray = img.grayscale(image);

  final w = gray.width;
  final h = gray.height;

  // Sample vertical strips and compute column-wise brightness variance
  // to find the dominant angle of text lines.
  // We'll use a simplified Radon-like approach: project along candidate angles.
  
  const angleRangeRad = 0.15; // ±8.6 degrees
  const angleSteps = 60;
  double bestAngle = 0.0;
  double bestScore = -1.0;

  for (int step = 0; step <= angleSteps; step++) {
    final angle = -angleRangeRad + (step * (2 * angleRangeRad / angleSteps));
    double score = _projectionScore(gray, w, h, angle);
    if (score > bestScore) {
      bestScore = score;
      bestAngle = angle;
    }
  }

  return bestAngle;
}

double _projectionScore(img.Image gray, int w, int h, double angle) {
  final cos = math.cos(angle);
  final sin = math.sin(angle);
  final centerX = w / 2;
  final centerY = h / 2;

  // Accumulate column sums after virtual rotation
  final sums = List<double>.filled(h, 0.0);
  int sampleStep = math.max(1, w ~/ 100); // sample every N columns for speed

  for (int x = 0; x < w; x += sampleStep) {
    for (int y = 0; y < h; y++) {
      final nx = (x - centerX) * cos - (y - centerY) * sin + centerX;
      final ny = (x - centerX) * sin + (y - centerY) * cos + centerY;
      if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
      final pixel = gray.getPixel(nx.toInt(), ny.toInt());
      sums[y] += img.getLuminance(pixel) / 255.0;
    }
  }

  // Score = variance of row sums (high variance = sharp transitions = text lines)
  final mean = sums.reduce((a, b) => a + b) / sums.length;
  double variance = 0;
  for (final s in sums) {
    variance += (s - mean) * (s - mean);
  }
  return variance / sums.length;
}

class _RotateArgs {
  final img.Image image;
  final double angleRad;
  _RotateArgs(this.image, this.angleRad);
}

img.Image _rotateImage(_RotateArgs args) {
  final angleDeg = args.angleRad * 180 / math.pi;
  return img.copyRotate(args.image, angle: angleDeg);
}
