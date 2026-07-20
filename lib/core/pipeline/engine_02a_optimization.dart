// =============================================================================
// ENGINE 02A — IMAGE OPTIMIZATION
//
// Responsibilities:
//   - Crop unused white margins
//   - Convert to Grayscale (reduces file size + helps OCR)
//   - Apply CLAHE-style adaptive contrast (histogram equalisation per tile)
//   - Apply Adaptive Threshold (Sauvola-inspired) for binarization
//   - Morphological cleanup (dilation/erosion to connect broken characters)
//   - Text sharpening
//   - Resize intelligently (max 2000px wide for OCR — beyond that is wasteful)
//   - Compress to JPEG (optimized_upload.jpg)
//   - Output optimization_report.json metrics
//
// Input:  processed_image.png (from Engine 02)
// Output: optimized_upload.jpg  (small, OCR-ready)
//         OptimizationReport (metrics)
//
// Does NOT run OCR.
// The objective is OCR readability, not visual quality.
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

  static const int _maxOcrWidthPx = 2000; // beyond this, OCR gains nothing
  static const int _jpegQuality = 85;     // good quality vs. size tradeoff

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
        _OptimizationArgs(image, _maxOcrWidthPx),
      );

      // Save as JPEG
      final outFile = await _saveJpeg(optimized);
      final optimizedSizeBytes = outFile.lengthSync();

      stopwatch.stop();

      final ratio = originalSizeBytes / optimizedSizeBytes;
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
// ISOLATE TASKS
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

  // Step 1: Trim white margins (autocrop)
  out = _autocrop(out);

  // Step 2: Convert to grayscale
  out = img.grayscale(out);

  // Step 3: Adaptive histogram equalisation (CLAHE approximation)
  // We do a simple per-tile histogram equalisation (4x4 tiles)
  out = _tileHistogramEqualise(out, tiles: 4);

  // Step 4: Sauvola-inspired adaptive threshold binarization
  // This converts the image to clean black text on white background
  out = _adaptiveThreshold(out, windowSize: 51, k: 0.2);

  // Step 5: Morphological cleanup — small blur to smooth broken character edges
  out = img.gaussianBlur(out, radius: 1);

  // Step 6: Sharpen text edges (div must be a double in image v4.x)
  out = img.convolution(out, filter: [
     0, -1,  0,
    -1,  5, -1,
     0, -1,  0,
  ], div: 1.0);

  // Step 7: Resize to max OCR width if too large
  if (out.width > args.maxWidth) {
    final scale = args.maxWidth / out.width;
    out = img.copyResize(
      out,
      width: args.maxWidth,
      height: (out.height * scale).toInt(),
      interpolation: img.Interpolation.linear,
    );
  }

  return out;
}

/// Trim uniform white/light borders from all 4 sides.
img.Image _autocrop(img.Image src) {
  const threshold = 240; // pixels brighter than this are considered background
  final w = src.width;
  final h = src.height;

  int top = 0, bottom = h - 1, left = 0, right = w - 1;

  // Find top boundary
  outer:
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final lum = img.getLuminance(src.getPixel(x, y));
      if (lum < threshold) { top = y; break outer; }
    }
  }
  // Find bottom boundary
  outer:
  for (int y = h - 1; y >= 0; y--) {
    for (int x = 0; x < w; x++) {
      final lum = img.getLuminance(src.getPixel(x, y));
      if (lum < threshold) { bottom = y; break outer; }
    }
  }
  // Find left boundary
  outer:
  for (int x = 0; x < w; x++) {
    for (int y = 0; y < h; y++) {
      final lum = img.getLuminance(src.getPixel(x, y));
      if (lum < threshold) { left = x; break outer; }
    }
  }
  // Find right boundary
  outer:
  for (int x = w - 1; x >= 0; x--) {
    for (int y = 0; y < h; y++) {
      final lum = img.getLuminance(src.getPixel(x, y));
      if (lum < threshold) { right = x; break outer; }
    }
  }

  // Add 10px padding
  top    = (top    - 10).clamp(0, h - 1);
  bottom = (bottom + 10).clamp(0, h - 1);
  left   = (left   - 10).clamp(0, w - 1);
  right  = (right  + 10).clamp(0, w - 1);

  if (right <= left || bottom <= top) return src; // safety guard

  return img.copyCrop(src,
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  );
}

/// Simplified per-tile histogram equalisation (CLAHE approximation).
img.Image _tileHistogramEqualise(img.Image src, {int tiles = 4}) {
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

      // Build histogram for this tile
      final hist = List<int>.filled(256, 0);
      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          final lum = img.getLuminance(src.getPixel(x, y)).toInt().clamp(0, 255);
          hist[lum]++;
        }
      }

      // Build CDF
      final cdf = List<int>.filled(256, 0);
      cdf[0] = hist[0];
      for (int i = 1; i < 256; i++) cdf[i] = cdf[i - 1] + hist[i];

      final cdfMin = cdf.firstWhere((v) => v > 0, orElse: () => 1);
      final totalPixels = (x1 - x0) * (y1 - y0);
      if (totalPixels == 0) continue;

      // Equalise tile pixels
      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          final lum = img.getLuminance(src.getPixel(x, y)).toInt().clamp(0, 255);
          final newVal = (((cdf[lum] - cdfMin) / (totalPixels - cdfMin)) * 255)
              .clamp(0, 255)
              .toInt();
          out.setPixelRgb(x, y, newVal, newVal, newVal);
        }
      }
    }
  }

  return out;
}

/// Sauvola-inspired adaptive threshold.
/// Each pixel is compared to the local mean in a windowSize×windowSize window.
/// Pixels below (mean * (1 - k * (1 - std/128))) become black (0), else white (255).
img.Image _adaptiveThreshold(img.Image src, {int windowSize = 51, double k = 0.2}) {
  final w = src.width;
  final h = src.height;
  final out = src.clone();
  final half = windowSize ~/ 2;

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final x0 = (x - half).clamp(0, w - 1);
      final y0 = (y - half).clamp(0, h - 1);
      final x1 = (x + half).clamp(0, w - 1);
      final y1 = (y + half).clamp(0, h - 1);

      double sum = 0;
      double sumSq = 0;
      int count = 0;

      for (int wy = y0; wy <= y1; wy++) {
        for (int wx = x0; wx <= x1; wx++) {
          final lum = img.getLuminance(src.getPixel(wx, wy));
          sum += lum;
          sumSq += lum * lum;
          count++;
        }
      }

      if (count == 0) continue;
      final mean = sum / count;
      final variance = (sumSq / count) - (mean * mean);
      final safeVariance = variance < 0 ? 0.0 : variance;
      // Newton-Raphson sqrt (dart:math not available in isolate without import)
      double std = 0.0;
      if (safeVariance > 0) {
        double sqx = safeVariance;
        double sqprev = -1;
        int iter = 0;
        while ((sqx - sqprev).abs() > 0.001 && iter < 20) {
          sqprev = sqx; sqx = (sqx + safeVariance / sqx) / 2; iter++;
        }
        std = sqx;
      }

      final threshold = mean * (1.0 - k * (1.0 - std / 128.0));
      final lum = img.getLuminance(src.getPixel(x, y));

      final val = lum < threshold ? 0 : 255;
      out.setPixelRgb(x, y, val, val, val);
    }
  }

  return out;
}
