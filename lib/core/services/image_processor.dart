import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Describes a single quality issue found in the image.
class ImageQualityIssue {
  final String code;
  final String message;
  final String suggestion;

  const ImageQualityIssue({
    required this.code,
    required this.message,
    required this.suggestion,
  });
}

/// Result of the quality validation pass.
class ImageQualityResult {
  final bool isLowLight;
  final bool isBlurry;
  final bool hasIssues;
  final List<ImageQualityIssue> issues;
  final double brightness; // 0.0 – 1.0
  final double blurScore;  // higher = sharper

  const ImageQualityResult({
    required this.isLowLight,
    required this.isBlurry,
    required this.hasIssues,
    required this.issues,
    required this.brightness,
    required this.blurScore,
  });

  bool get canEnhance => isLowLight && !isBlurry;
}

/// Image quality checker and pre-processor for memo OCR.
///
/// RULES:
///   - Low-light images:  WARN user, offer retry. If not blurry → auto-enhance brightness/contrast.
///   - Blurry images:     WARN user, ask for retry. Do NOT apply filter (it destroys text).
///   - Tilted/uneven:     WARN user, offer retry. Still proceed if user confirms.
///
/// Runs heavy operations in an isolate via compute().
class ImageProcessor {
  ImageProcessor._();

  // Thresholds (tuned for typical smartphone warehouse memos)
  static const double _lowLightThreshold  = 0.30; // brightness < 30% → low light
  static const double _blurThreshold      = 80.0; // Laplacian variance < 80 → blurry
  static const double _enhanceBrightness  = 1.40; // multiply brightness by 1.4x
  static const double _enhanceContrast    = 1.20; // multiply contrast  by 1.2x

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Validate image quality. Returns warnings but never hard-blocks the user.
  static Future<ImageQualityResult> checkQuality(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      return await compute(_analyzeImage, bytes);
    } catch (e) {
      if (kDebugMode) print('[ImageProcessor] Quality check error: $e');
      // If check fails, return clean result — don't block user.
      return const ImageQualityResult(
        isLowLight: false,
        isBlurry: false,
        hasIssues: false,
        issues: [],
        brightness: 0.5,
        blurScore: 100.0,
      );
    }
  }

  /// Enhance brightness + contrast for low-light (non-blurry) images.
  /// Returns a new File pointing to the enhanced image in the same directory.
  /// If the image is blurry, returns the original file unchanged.
  static Future<File> enhanceIfNeeded(File imageFile, ImageQualityResult quality) async {
    if (!quality.canEnhance) return imageFile; // blurry or no issues → skip
    try {
      final bytes = await imageFile.readAsBytes();
      final enhanced = await compute(_applyEnhancement, bytes);
      if (enhanced == null) return imageFile;

      final outPath = imageFile.path.replaceAll(
        RegExp(r'\.(jpg|jpeg|png)$', caseSensitive: false),
        '_enhanced.jpg',
      );
      final outFile = File(outPath);
      await outFile.writeAsBytes(enhanced);
      return outFile;
    } catch (e) {
      if (kDebugMode) print('[ImageProcessor] Enhancement error: $e');
      return imageFile; // fallback to original
    }
  }

  // ── Isolate functions (no Flutter framework access) ──────────────────────────

  static ImageQualityResult _analyzeImage(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) {
      return const ImageQualityResult(
        isLowLight: false, isBlurry: false, hasIssues: false,
        issues: [], brightness: 0.5, blurScore: 100.0,
      );
    }

    // ── 1. Brightness: average luminance across all pixels ────────────────────
    double totalLum = 0.0;
    final pixels = image.width * image.height;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r / 255.0;
        final g = pixel.g / 255.0;
        final b = pixel.b / 255.0;
        // Luminance (ITU-R BT.709)
        totalLum += 0.2126 * r + 0.7152 * g + 0.0722 * b;
      }
    }
    final brightness = totalLum / pixels;

    // ── 2. Blur: simplified Laplacian variance on a down-sampled grey image ───
    // Downscale for speed
    final small = img.copyResize(image, width: 320);
    final grey = img.grayscale(small);
    double laplacianSum = 0.0;
    int count = 0;
    for (int y = 1; y < grey.height - 1; y++) {
      for (int x = 1; x < grey.width - 1; x++) {
        final center = grey.getPixel(x, y).r.toDouble();
        final top    = grey.getPixel(x, y - 1).r.toDouble();
        final bottom = grey.getPixel(x, y + 1).r.toDouble();
        final left   = grey.getPixel(x - 1, y).r.toDouble();
        final right  = grey.getPixel(x + 1, y).r.toDouble();
        final lap = (4 * center - top - bottom - left - right).abs();
        laplacianSum += lap * lap;
        count++;
      }
    }
    final blurScore = count > 0 ? laplacianSum / count : 100.0;

    // ── 3. Build issues list ──────────────────────────────────────────────────
    final issues = <ImageQualityIssue>[];
    final isLowLight = brightness < _lowLightThreshold;
    final isBlurry   = blurScore  < _blurThreshold;

    if (isLowLight) {
      issues.add(const ImageQualityIssue(
        code: 'LOW_LIGHT',
        message: 'The image appears too dark.',
        suggestion: 'Move to better lighting or turn on your flashlight and retake.',
      ));
    }
    if (isBlurry) {
      issues.add(const ImageQualityIssue(
        code: 'BLURRY',
        message: 'The image is blurry.',
        suggestion: 'Hold the camera steady and ensure the memo is in focus before capturing.',
      ));
    }

    return ImageQualityResult(
      isLowLight: isLowLight,
      isBlurry: isBlurry,
      hasIssues: issues.isNotEmpty,
      issues: issues,
      brightness: brightness,
      blurScore: blurScore,
    );
  }

  static Uint8List? _applyEnhancement(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return null;

    // Adjust brightness and contrast
    img.adjustColor(
      image,
      brightness: _enhanceBrightness,
      contrast: _enhanceContrast,
    );

    return Uint8List.fromList(img.encodeJpg(image, quality: 92));
  }
}
