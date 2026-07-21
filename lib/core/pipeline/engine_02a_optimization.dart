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

  // ─── STEP 4: CLAHE TILE HISTOGRAM EQUALISATION ──────────────────────────
  // Using 2x2 tiles for speed. 4x4 tiles add detail but are 4x slower.
  out = _tileHistogramEqualise(out, tiles: 2);

  // ─── STEP 5: FAST ADAPTIVE THRESHOLD (Integral Image / O(n·m)) ──────────
  // Replaces the broken O(n·m·w²) per-pixel loop with an integral image
  // that answers "sum over any rectangular region" in O(1).
  out = _adaptiveThresholdIntegral(out, windowSize: 31, k: 0.15);

  // ─── STEP 6: TEXT SHARPENING ─────────────────────────────────────────────
  out = img.convolution(out, filter: [
     0, -1,  0,
    -1,  5, -1,
     0, -1,  0,
  ], div: 1.0);

  return out;
}

// =============================================================================
// FAST ADAPTIVE THRESHOLD — INTEGRAL IMAGE APPROACH
//
// Classic Sauvola threshold is O(n·m·w²). This version is O(n·m) by
// pre-computing a 2D prefix-sum (integral image) that answers
// "sum of luminance values in any rectangle" in exactly 4 array lookups.
//
// For a 1500×2000 image with windowSize=31:
//   Old approach:  1500×2000×31² = ~2.9 billion ops  (HANGS)
//   New approach:  1500×2000×1   = ~3 million ops     (< 1 second)
// =============================================================================
img.Image _adaptiveThresholdIntegral(img.Image src,
    {int windowSize = 31, double k = 0.15}) {
  final w = src.width;
  final h = src.height;
  final half = windowSize ~/ 2;
  final out = src.clone();

  // Build integral images (1-indexed: row 0 and col 0 are always 0)
  // Using flat arrays for memory efficiency.
  final W1 = w + 1;
  final H1 = h + 1;
  final integral = List<double>.filled(H1 * W1, 0.0);
  final integralSq = List<double>.filled(H1 * W1, 0.0);

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final lum = img.getLuminance(src.getPixel(x, y)).toDouble();
      final idx = (y + 1) * W1 + (x + 1);
      integral[idx] = lum
          + integral[y * W1 + (x + 1)]
          + integral[(y + 1) * W1 + x]
          - integral[y * W1 + x];
      integralSq[idx] = lum * lum
          + integralSq[y * W1 + (x + 1)]
          + integralSq[(y + 1) * W1 + x]
          - integralSq[y * W1 + x];
    }
  }

  // Threshold each pixel using the integral image for O(1) window sums
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final x0 = (x - half).clamp(0, w - 1);
      final y0 = (y - half).clamp(0, h - 1);
      final x1 = (x + half).clamp(0, w - 1);
      final y1 = (y + half).clamp(0, h - 1);

      // O(1) sum via integral image
      final count = ((x1 - x0 + 1) * (y1 - y0 + 1)).toDouble();
      final sum = integral[(y1 + 1) * W1 + (x1 + 1)]
                - integral[y0 * W1 + (x1 + 1)]
                - integral[(y1 + 1) * W1 + x0]
                + integral[y0 * W1 + x0];
      final sumSq = integralSq[(y1 + 1) * W1 + (x1 + 1)]
                  - integralSq[y0 * W1 + (x1 + 1)]
                  - integralSq[(y1 + 1) * W1 + x0]
                  + integralSq[y0 * W1 + x0];

      final mean = sum / count;
      final variance = (sumSq / count) - (mean * mean);

      // Fast integer sqrt approximation (Newton-Raphson, 5 iterations)
      double std = 0.0;
      if (variance > 0.01) {
        double r = variance;
        r = (r + variance / r) / 2;
        r = (r + variance / r) / 2;
        r = (r + variance / r) / 2;
        r = (r + variance / r) / 2;
        r = (r + variance / r) / 2;
        std = r;
      }

      // Sauvola formula: T = mean × (1 - k × (1 - std/R))  where R=128
      final threshold = mean * (1.0 - k * (1.0 - std / 128.0));
      final lum = img.getLuminance(src.getPixel(x, y)).toDouble();
      final val = lum < threshold ? 0 : 255;
      out.setPixelRgb(x, y, val, val, val);
    }
  }

  return out;
}

// =============================================================================
// AUTOCROP — trim uniform light borders from all 4 sides
// =============================================================================
img.Image _autocrop(img.Image src) {
  const threshold = 240.0;
  final w = src.width;
  final h = src.height;

  int top = 0, bottom = h - 1, left = 0, right = w - 1;

  outer1:
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (img.getLuminance(src.getPixel(x, y)) < threshold) { top = y; break outer1; }
    }
  }
  outer2:
  for (int y = h - 1; y >= 0; y--) {
    for (int x = 0; x < w; x++) {
      if (img.getLuminance(src.getPixel(x, y)) < threshold) { bottom = y; break outer2; }
    }
  }
  outer3:
  for (int x = 0; x < w; x++) {
    for (int y = 0; y < h; y++) {
      if (img.getLuminance(src.getPixel(x, y)) < threshold) { left = x; break outer3; }
    }
  }
  outer4:
  for (int x = w - 1; x >= 0; x--) {
    for (int y = 0; y < h; y++) {
      if (img.getLuminance(src.getPixel(x, y)) < threshold) { right = x; break outer4; }
    }
  }

  top    = (top    - 10).clamp(0, h - 1);
  bottom = (bottom + 10).clamp(0, h - 1);
  left   = (left   - 10).clamp(0, w - 1);
  right  = (right  + 10).clamp(0, w - 1);

  if (right <= left || bottom <= top) return src;
  return img.copyCrop(src, x: left, y: top, width: right - left, height: bottom - top);
}

// =============================================================================
// CLAHE-APPROXIMATION — per-tile histogram equalisation
// =============================================================================
img.Image _tileHistogramEqualise(img.Image src, {int tiles = 2}) {
  final w = src.width;
  final h = src.height;
  final tileW = (w / tiles).ceil();
  final tileH = (h / tiles).ceil();
  final out = src.clone();

  for (int ty = 0; ty < tiles; ty++) {
    for (int tx = 0; tx < tiles; tx++) {
      final x0 = tx * tileW;
      final y0 = ty * tileH;
      final x1 = (x0 + tileW).clamp(0, w);
      final y1 = (y0 + tileH).clamp(0, h);

      final hist = List<int>.filled(256, 0);
      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          hist[img.getLuminance(src.getPixel(x, y)).toInt().clamp(0, 255)]++;
        }
      }

      final cdf = List<int>.filled(256, 0);
      cdf[0] = hist[0];
      for (int i = 1; i < 256; i++) cdf[i] = cdf[i - 1] + hist[i];

      final cdfMin = cdf.firstWhere((v) => v > 0, orElse: () => 1);
      final total = (x1 - x0) * (y1 - y0);
      if (total == 0) continue;

      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          final lum = img.getLuminance(src.getPixel(x, y)).toInt().clamp(0, 255);
          final newVal = (((cdf[lum] - cdfMin) / (total - cdfMin)) * 255)
              .clamp(0, 255)
              .toInt();
          out.setPixelRgb(x, y, newVal, newVal, newVal);
        }
      }
    }
  }

  return out;
}
