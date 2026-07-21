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

  final W1 = w + 1;
  final H1 = h + 1;
  final integral = List<double>.filled(H1 * W1, 0.0);
  final integralSq = List<double>.filled(H1 * W1, 0.0);

  // Build integral image in one fast pass
  for (final p in src) {
    final x = p.x;
    final y = p.y;
    final lum = p.luminance.toDouble();
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

  // Threshold in one fast pass
  for (final p in out) {
    final x = p.x;
    final y = p.y;
    
    final x0 = (x - half).clamp(0, w - 1);
    final y0 = (y - half).clamp(0, h - 1);
    final x1 = (x + half).clamp(0, w - 1);
    final y1 = (y + half).clamp(0, h - 1);

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

    double std = 0.0;
    if (variance > 0.01) {
      double r = variance;
      for (int i = 0; i < 5; i++) {
        r = (r + variance / r) / 2;
      }
      std = r;
    }

    final threshold = mean * (1.0 - k * (1.0 - std / 128.0));
    final val = p.luminance < threshold ? 0 : 255;
    p.setRgb(val, val, val);
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
// =============================================================================
img.Image _tileHistogramEqualise(img.Image src, {int tiles = 2}) {
  final w = src.width;
  final h = src.height;
  final tileW = (w / tiles).ceil();
  final tileH = (h / tiles).ceil();
  final out = src.clone();

  final hists = List.generate(tiles * tiles, (_) => List<int>.filled(256, 0));
  final cdfs = List.generate(tiles * tiles, (_) => List<int>.filled(256, 0));
  final cdfMins = List<int>.filled(tiles * tiles, 1);
  final totals = List<int>.filled(tiles * tiles, 0);

  // 1. Build histograms in one fast pass
  for (final p in src) {
    final tx = (p.x ~/ tileW).clamp(0, tiles - 1);
    final ty = (p.y ~/ tileH).clamp(0, tiles - 1);
    hists[ty * tiles + tx][p.luminance.toInt().clamp(0, 255)]++;
    totals[ty * tiles + tx]++;
  }

  // 2. Compute CDFs
  for (int i = 0; i < tiles * tiles; i++) {
    cdfs[i][0] = hists[i][0];
    for (int j = 1; j < 256; j++) {
      cdfs[i][j] = cdfs[i][j - 1] + hists[i][j];
    }
    cdfMins[i] = cdfs[i].firstWhere((v) => v > 0, orElse: () => 1);
  }

  // 3. Apply equalization in one fast pass
  for (final p in out) {
    final tx = (p.x ~/ tileW).clamp(0, tiles - 1);
    final ty = (p.y ~/ tileH).clamp(0, tiles - 1);
    final tileIdx = ty * tiles + tx;
    
    final total = totals[tileIdx];
    if (total == 0) continue;

    final lum = p.luminance.toInt().clamp(0, 255);
    final cdfMin = cdfMins[tileIdx];
    
    final newVal = (((cdfs[tileIdx][lum] - cdfMin) / (total - cdfMin)) * 255)
        .clamp(0, 255)
        .toInt();
    
    p.setRgb(newVal, newVal, newVal);
  }

  return out;
}
