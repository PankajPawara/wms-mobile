// =============================================================================
// ENGINE 02A — IMAGE OPTIMIZATION (v2 — Fast Integral Image)
//
// Responsibilities:
//   - STEP 1: Resize first (max 1500px) BEFORE any expensive algorithms
//   - STEP 2: Autocrop white margins
//   - STEP 3: Convert to Grayscale
//   - STEP 4: CLAHE tile histogram equalisation
//   - STEP 5: Fast Adaptive Threshold using Integral Images (O(n·m) not O(n·m·w²))
//   - STEP 6: Text sharpening
//   - STEP 7: JPEG compression + report
//
// THE ROOT CAUSE OF THE HANG:
//   The previous version ran a 51×51 window loop for EVERY pixel.
//   For a 2868px-wide image that is ~21 BILLION operations.
//   The Integral Image approach reduces this to O(1) per pixel lookup.
//
// Input:  processed_image.png (from Engine 02)
// Output: optimized_upload.jpg + OptimizationReport
//
// Performance target: < 3 seconds on a mid-range Android device.
// =============================================================================

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'models/pipeline_result.dart';
import 'models/pipeline_stage.dart';
import 'models/optimization_report.dart';
import 'engine_02_processing.dart';

/// The paired outputs of Engine 02A.
class OptimizationOutput {
  final File optimizedImage;
  final OptimizationReport report;

  const OptimizationOutput({
    required this.optimizedImage,
    required this.report,
  });

  Map<String, dynamic> toJson() => {
    'optimizedImagePath': optimizedImage.path,
    'report': report.toJson(),
  };
}

class Engine02aOptimization {
  Engine02aOptimization._();

  /// Max width BEFORE running any expensive per-pixel algorithms.
  /// Resizing first is the single biggest performance win.
  static const int _maxProcessingWidthPx = 1500;

  /// JPEG quality for the final compressed output.
  static const int _jpegQuality = 85;

  static Future<PipelineResult<OptimizationOutput>> optimize(
      ProcessingOutput processing) async {
    final stopwatch = Stopwatch()..start();
    try {
      final originalSizeBytes = processing.processedImage.lengthSync();
      final bytes = await processing.processedImage.readAsBytes();

      final image = await compute(_decodeBytes, bytes);
      if (image == null) throw Exception('Could not decode processed image.');

      final originalW = image.width;
      final originalH = image.height;

      // Run optimization pipeline in isolate (CPU-intensive)
      final optimized = await compute(
        _runOptimizationPipeline,
        _OptimizationArgs(image, _maxProcessingWidthPx),
      );

      // Save as JPEG
      final outFile = await _saveJpeg(optimized);
      final optimizedSizeBytes = outFile.lengthSync();

      stopwatch.stop();

      final ratio = originalSizeBytes > 0
          ? originalSizeBytes / optimizedSizeBytes
          : 1.0;
      final report = OptimizationReport(
        originalSizeMB: originalSizeBytes / (1024 * 1024),
        optimizedSizeMB: optimizedSizeBytes / (1024 * 1024),
        compressionRatio: '${ratio.toStringAsFixed(1)}x',
        processingTimeMs: stopwatch.elapsedMilliseconds,
        uploadReady: (optimizedSizeBytes / (1024 * 1024)) < 1.5,
        originalWidth: originalW,
        originalHeight: originalH,
        optimizedWidth: optimized.width,
        optimizedHeight: optimized.height,
      );

      return PipelineResult(
        data: OptimizationOutput(optimizedImage: outFile, report: report),
        timingMs: stopwatch.elapsedMilliseconds,
        confidence: 0.95,
        stage: PipelineStage.optimization,
      );
    } catch (e) {
      stopwatch.stop();
      return PipelineResult.failure(
        stage: PipelineStage.optimization,
        reason: 'Optimization failed: $e',
        timingMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  static Future<File> _saveJpeg(img.Image image) async {
    final tempDir = await getTemporaryDirectory();
    final sessionId = DateTime.now().millisecondsSinceEpoch;
    final outPath = '${tempDir.path}/pipeline_${sessionId}_optimized.jpg';
    final jpegBytes = img.encodeJpg(image, quality: _jpegQuality);
    return File(outPath).writeAsBytes(jpegBytes);
  }
}

// =============================================================================
// ISOLATE TASKS — all top-level for compute() compatibility
// =============================================================================

img.Image? _decodeBytes(List<int> bytes) {
  return img.decodeImage(Uint8List.fromList(bytes));
}

class _OptimizationArgs {
  final img.Image image;
  final int maxWidth;
  _OptimizationArgs(this.image, this.maxWidth);
}

img.Image _runOptimizationPipeline(_OptimizationArgs args) {
  img.Image out = args.image;

  // ─── STEP 1: RESIZE FIRST ────────────────────────────────────────────────
  // This is the most important step. All subsequent operations run on a
  // smaller image, making them dramatically faster.
  if (out.width > args.maxWidth) {
    final scale = args.maxWidth / out.width;
    out = img.copyResize(
      out,
      width: args.maxWidth,
      height: (out.height * scale).toInt(),
      interpolation: img.Interpolation.linear,
    );
  }

  // ─── STEP 2: AUTOCROP WHITE MARGINS ─────────────────────────────────────
  out = _autocrop(out);

  // ─── STEP 3: CONVERT TO GRAYSCALE ───────────────────────────────────────
  out = img.grayscale(out);

  // Note: We deliberately SKIP Histogram Equalization, Adaptive Thresholding,
  // and Convolution Sharpening. Google ML Kit uses Deep Learning models that 
  // rely on sub-pixel anti-aliasing and natural lighting to read text accurately. 
  // Forcing the image to strict black & white destroys this subtle information 
  // and causes the text recognizer to fail or hallucinate.

  return out;
}



// =============================================================================
// AUTOCROP — trim uniform light borders from all 4 sides
// =============================================================================
img.Image _autocrop(img.Image src) {
  const threshold = 240.0;
  final w = src.width;
  final h = src.height;

  int minX = w, minY = h, maxX = 0, maxY = 0;
  bool found = false;

  for (final p in src) {
    if (p.luminance < threshold) {
      found = true;
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
  }

  if (!found) return src; // Blank image

  int top = (minY - 10).clamp(0, h - 1);
  int bottom = (maxY + 10).clamp(0, h - 1);
  int left = (minX - 10).clamp(0, w - 1);
  int right = (maxX + 10).clamp(0, w - 1);

  if (bottom - top <= 10 || right - left <= 10) return src;

  return img.copyCrop(
    src,
    x: left,
    y: top,
    width: right - left + 1,
    height: bottom - top + 1,
  );
}

// =============================================================================
// CLAHE-APPROXIMATION — per-tile histogram equalisation

