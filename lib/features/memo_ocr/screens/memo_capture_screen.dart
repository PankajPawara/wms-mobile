import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/extracted_memo.dart';
import '../../../core/services/image_processor.dart';
import '../../../core/services/memo_ocr_engine.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/empty_state_placeholder.dart';
import 'package:image_picker/image_picker.dart';

/// Pipeline step labels shown in the progress UI.
enum _PipelineStep {
  idle,
  checkingQuality,
  enhancing,
  runningOcr,
  reconstructingRows,
  validatingDb,
  done,
}

extension _PipelineStepExt on _PipelineStep {
  String get label => switch (this) {
    _PipelineStep.idle              => '',
    _PipelineStep.checkingQuality   => 'Checking image quality...',
    _PipelineStep.enhancing         => 'Enhancing brightness & contrast...',
    _PipelineStep.runningOcr        => 'Reading text from memo...',
    _PipelineStep.reconstructingRows => 'Reconstructing table rows...',
    _PipelineStep.validatingDb      => 'Validating parts against database...',
    _PipelineStep.done              => 'Done!',
  };

  int get stepIndex => index;
  static const int totalSteps = 5; // excludes idle and done
}

class MemoCaptureScreen extends ConsumerStatefulWidget {
  const MemoCaptureScreen({super.key});

  @override
  ConsumerState<MemoCaptureScreen> createState() => _MemoCaptureScreenState();
}

class _MemoCaptureScreenState extends ConsumerState<MemoCaptureScreen> {
  File? _imageFile;
  _PipelineStep _currentStep = _PipelineStep.idle;
  bool get _isProcessing => _currentStep != _PipelineStep.idle && _currentStep != _PipelineStep.done;
  List<ImageQualityIssue> _qualityWarnings = [];
  String? _error;

  void _setStep(_PipelineStep step) {
    if (mounted) setState(() => _currentStep = step);
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: source, imageQuality: 90, maxWidth: 2000);
    if (picked == null) return;
    setState(() {
      _imageFile = File(picked.path);
      _error = null;
      _qualityWarnings = [];
      _currentStep = _PipelineStep.idle;
    });
  }

  Future<void> _processOcr() async {
    if (_imageFile == null) return;
    setState(() {
      _error = null;
      _qualityWarnings = [];
    });

    File workingFile = _imageFile!;

    // ── STEP 1: Image quality check ────────────────────────────────────
    _setStep(_PipelineStep.checkingQuality);
    final quality = await ImageProcessor.checkQuality(workingFile);

    if (quality.hasIssues) {
      if (mounted) setState(() => _qualityWarnings = quality.issues);

      // Show warning dialog — user can retry or continue
      final shouldContinue = await _showQualityWarningDialog(quality);
      if (!mounted) return;
      if (!shouldContinue) {
        // User chose to cancel — reset to idle
        setState(() => _currentStep = _PipelineStep.idle);
        return;
      }
    }

    // ── STEP 2: Enhance brightness/contrast (only for low-light, non-blurry) ──
    if (quality.canEnhance) {
      _setStep(_PipelineStep.enhancing);
      workingFile = await ImageProcessor.enhanceIfNeeded(workingFile, quality);
    }

    // ── STEP 3: ML Kit OCR + row reconstruction ──────────────────────────
    _setStep(_PipelineStep.runningOcr);
    MemoOcrResult ocrResult;
    try {
      _setStep(_PipelineStep.reconstructingRows);
      _setStep(_PipelineStep.validatingDb);
      final db = ref.read(appDatabaseProvider);
      ocrResult = await MemoOcrEngine.process(workingFile, db);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'OCR failed: ${e.toString()}';
          _currentStep = _PipelineStep.idle;
        });
      }
      return;
    }

    if (ocrResult.items.isEmpty) {
      if (mounted) {
        setState(() {
          _error = 'No Honda part numbers found. Try a clearer photo or better lighting.';
          _currentStep = _PipelineStep.idle;
        });
      }
      return;
    }

    _setStep(_PipelineStep.done);

    if (mounted) {
      context.push('/ocr-review', extra: {
        'ocrResult': ocrResult,
        'imagePath': workingFile.path,
      });
      setState(() => _currentStep = _PipelineStep.idle);
    }
  }

  Future<bool> _showQualityWarningDialog(ImageQualityResult quality) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 24),
            SizedBox(width: 8),
            Text('Image Quality Warning',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...quality.issues.map((issue) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(issue.message,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(issue.suggestion,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                )),
            if (quality.canEnhance) ...[
              const Divider(),
              const Text(
                '\u2728 We will automatically enhance brightness and contrast to improve text extraction.',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel & Retake',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continue Anyway'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/home');
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppDimensions.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _imageFile == null
                      ? _EmptyImageState(
                          onCamera: () => _pickImage(ImageSource.camera),
                          onGallery: () => _pickImage(ImageSource.gallery),
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                    AppDimensions.radiusLg),
                                child: Image.file(_imageFile!,
                                    fit: BoxFit.contain),
                              ),
                            ),
                            const SizedBox(height: AppDimensions.md),
                            Row(
                              children: [
                                Expanded(
                                  child: AppButton(
                                    label: 'Retake',
                                    variant: AppButtonVariant.outline,
                                    icon: Icons.camera_alt_outlined,
                                    onPressed: _isProcessing
                                        ? null
                                        : () => _pickImage(ImageSource.camera),
                                  ),
                                ),
                                const SizedBox(width: AppDimensions.sm),
                                Expanded(
                                  child: AppButton(
                                    label: 'Gallery',
                                    variant: AppButtonVariant.secondary,
                                    icon: Icons.photo_library_outlined,
                                    onPressed: _isProcessing
                                        ? null
                                        : () => _pickImage(ImageSource.gallery),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),

                // Pipeline progress indicator
                if (_isProcessing) ...[
                  const SizedBox(height: AppDimensions.md),
                  _PipelineProgressIndicator(step: _currentStep),
                ],

                // Quality warnings (shown under the image)
                if (_qualityWarnings.isNotEmpty && !_isProcessing) ...[
                  const SizedBox(height: AppDimensions.sm),
                  Container(
                    padding: const EdgeInsets.all(AppDimensions.sm),
                    decoration: BoxDecoration(
                      color: AppColors.warningLight,
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusMd),
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _qualityWarnings
                          .map((w) => Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      color: AppColors.warning, size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(w.message,
                                        style: const TextStyle(
                                            color: AppColors.warning,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500)),
                                  ),
                                ],
                              ))
                          .toList(),
                    ),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: AppDimensions.sm),
                  Container(
                    padding: const EdgeInsets.all(AppDimensions.sm),
                    decoration: BoxDecoration(
                        color: AppColors.dangerLight,
                        borderRadius:
                            BorderRadius.circular(AppDimensions.radiusMd)),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.danger, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: AppColors.danger, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppDimensions.md),
                Padding(
                  padding: const EdgeInsets.only(bottom: 84),
                  child: AppButton(
                    label: _isProcessing
                        ? _currentStep.label
                        : AppStrings.generatePickupList,
                    icon: Icons.document_scanner_outlined,
                    onPressed: _imageFile == null || _isProcessing
                        ? null
                        : _processOcr,
                    isLoading: _isProcessing,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a step-by-step pipeline progress bar.
class _PipelineProgressIndicator extends StatelessWidget {
  final _PipelineStep step;
  const _PipelineProgressIndicator({required this.step});

  @override
  Widget build(BuildContext context) {
    final progress = step.stepIndex / _PipelineStepExt.totalSteps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
            Text(
              step.label,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          backgroundColor: AppColors.primaryLight,
          valueColor:
              const AlwaysStoppedAnimation<Color>(AppColors.primary),
          minHeight: 4,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
}

class _EmptyImageState extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  const _EmptyImageState({required this.onCamera, required this.onGallery});

  @override
  Widget build(BuildContext context) {
    return EmptyStatePlaceholder(
      icon: Icons.document_scanner_outlined,
      title: 'Generate Pickup List',
      subtitle:
          'Capture or upload an order memo. We will automatically detect quality issues, enhance brightness if needed, extract all parts, and validate against your local database.',
      action: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            onPressed: onCamera,
            icon: const Icon(Icons.camera_alt_rounded),
            label: const Text('Camera'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: onGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Gallery'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
