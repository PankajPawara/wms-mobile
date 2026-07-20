// =============================================================================
// ENGINE 01 — IMAGE ACQUISITION
//
// Responsibilities:
//   - Accept image from camera OR gallery
//   - Detect and correct coarse rotation (EXIF orientation)
//   - Save as original_image.jpg in temp directory
//   - Return file path + metadata
//
// Does NOT perform any OCR.
// Does NOT modify image content (brightness, crop, etc.)
// =============================================================================

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

import 'models/pipeline_result.dart';
import 'models/pipeline_stage.dart';

/// Output contract for Engine 01.
class AcquisitionOutput {
  final File originalImage;
  final int widthPx;
  final int heightPx;
  final double fileSizeMB;
  final String source; // 'camera' | 'gallery' | 'asset'

  const AcquisitionOutput({
    required this.originalImage,
    required this.widthPx,
    required this.heightPx,
    required this.fileSizeMB,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
    'path': originalImage.path,
    'widthPx': widthPx,
    'heightPx': heightPx,
    'fileSizeMB': double.parse(fileSizeMB.toStringAsFixed(2)),
    'source': source,
  };
}

class Engine01Acquisition {
  Engine01Acquisition._();

  /// Acquire an image from the gallery and return a normalised output.
  static Future<PipelineResult<AcquisitionOutput>> fromGallery() async {
    return _acquire(source: 'gallery');
  }

  /// Acquire an image from the camera and return a normalised output.
  static Future<PipelineResult<AcquisitionOutput>> fromCamera() async {
    return _acquire(source: 'camera');
  }

  /// Acquire directly from a pre-existing [File] (used in tests / scan doc).
  static Future<PipelineResult<AcquisitionOutput>> fromFile(File file) async {
    final stopwatch = Stopwatch()..start();
    try {
      final saved = await _normaliseAndSave(file, 'file');
      stopwatch.stop();
      return PipelineResult(
        data: saved,
        timingMs: stopwatch.elapsedMilliseconds,
        confidence: 1.0,
        stage: PipelineStage.acquisition,
      );
    } catch (e) {
      stopwatch.stop();
      return PipelineResult.failure(
        stage: PipelineStage.acquisition,
        reason: 'Failed to load file: $e',
        timingMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static Future<PipelineResult<AcquisitionOutput>> _acquire({
    required String source,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final picker = ImagePicker();
      final XFile? picked = source == 'camera'
          ? await picker.pickImage(source: ImageSource.camera, imageQuality: 95)
          : await picker.pickImage(source: ImageSource.gallery, imageQuality: 95);

      if (picked == null) {
        stopwatch.stop();
        return PipelineResult.failure(
          stage: PipelineStage.acquisition,
          reason: 'User cancelled image selection.',
          timingMs: stopwatch.elapsedMilliseconds,
        );
      }

      final file = File(picked.path);
      final output = await _normaliseAndSave(file, source);
      stopwatch.stop();

      return PipelineResult(
        data: output,
        timingMs: stopwatch.elapsedMilliseconds,
        confidence: 1.0,
        stage: PipelineStage.acquisition,
      );
    } catch (e) {
      stopwatch.stop();
      return PipelineResult.failure(
        stage: PipelineStage.acquisition,
        reason: 'Acquisition error: $e',
        timingMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// Correct EXIF orientation, save to temp dir as original_image.jpg.
  static Future<AcquisitionOutput> _normaliseAndSave(
      File sourceFile, String source) async {
    final bytes = await sourceFile.readAsBytes();

    // Decode + auto-orient (fixes EXIF rotation on Android camera images)
    img.Image? decoded = await compute(_decodeAndOrient, bytes);
    if (decoded == null) {
      throw Exception('Could not decode image file.');
    }

    final tempDir = await getTemporaryDirectory();
    final sessionId = DateTime.now().millisecondsSinceEpoch;
    final outPath = '${tempDir.path}/pipeline_${sessionId}_original.jpg';

    final outBytes = img.encodeJpg(decoded, quality: 95);
    final outFile = await File(outPath).writeAsBytes(outBytes);

    final sizeMB = outFile.lengthSync() / (1024 * 1024);

    return AcquisitionOutput(
      originalImage: outFile,
      widthPx: decoded.width,
      heightPx: decoded.height,
      fileSizeMB: sizeMB,
      source: source,
    );
  }
}

/// Runs in an isolate — decodes image bytes and applies EXIF auto-orient.
img.Image? _decodeAndOrient(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return img.bakeOrientation(decoded);
}
