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
import '../../../core/pipeline/ocr_pipeline_manager.dart';
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
  List<File> _imageFiles = [];
  _PipelineStep _currentStep = _PipelineStep.idle;
  bool get _isProcessing => _currentStep != _PipelineStep.idle && _currentStep != _PipelineStep.done;
  List<ImageQualityIssue> _qualityWarnings = [];
  String? _error;

  void _setStep(_PipelineStep step) {
    if (mounted) setState(() => _currentStep = step);
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    List<XFile> pickedFiles = [];
    
    if (source == ImageSource.gallery) {
      pickedFiles = await picker.pickMultiImage(imageQuality: 90, maxWidth: 2000);
    } else {
      final picked = await picker.pickImage(source: source, imageQuality: 90, maxWidth: 2000);
      if (picked != null) pickedFiles.add(picked);
    }
    
    if (pickedFiles.isEmpty) return;
    
    setState(() {
      _imageFiles.addAll(pickedFiles.map((x) => File(x.path)));
      _error = null;
      _qualityWarnings = [];
      _currentStep = _PipelineStep.idle;
    });
  }

  void _removeImage(int index) {
    setState(() {
      _imageFiles.removeAt(index);
    });
  }

  Future<void> _processOcr() async {
    if (_imageFiles.isEmpty) return;
    setState(() {
      _error = null;
      _qualityWarnings = [];
    });

    final db = ref.read(appDatabaseProvider);
    
    List<ExtractedMemoItem> allItems = [];
    ExtractedMemoHeader? finalHeader;
    String finalDump = '';
    
    for (int i = 0; i < _imageFiles.length; i++) {
      File workingFile = _imageFiles[i];

      _setStep(_PipelineStep.checkingQuality);
      final quality = await ImageProcessor.checkQuality(workingFile);

      if (quality.hasIssues) {
        if (mounted) setState(() => _qualityWarnings = quality.issues);
        final shouldContinue = await _showQualityWarningDialog(quality);
        if (!mounted) return;
        if (!shouldContinue) {
          setState(() => _currentStep = _PipelineStep.idle);
          return;
        }
      }

      if (quality.canEnhance) {
        _setStep(_PipelineStep.enhancing);
        workingFile = await ImageProcessor.enhanceIfNeeded(workingFile, quality);
      }

      _setStep(_PipelineStep.runningOcr);
      try {
        _setStep(_PipelineStep.reconstructingRows);
        _setStep(_PipelineStep.validatingDb);
        
        final result = await OcrPipelineManager.process(workingFile, db);
        
        // Merge results
        allItems.addAll(result.items);
        finalDump += '\n\n--- Page ${i + 1} ---\n' + result.rawOcrDump;
        
        // Use the first valid header we find
        if (finalHeader == null || finalHeader.memoNumber.contains('OCR Generated')) {
          finalHeader = result.header;
        }
      } catch (e) {
        if (e.toString().contains('NO_HEADER_DETECTED')) {
           if (mounted) {
             setState(() {
               _error = 'No table header detected on Image ${i+1}. Please retake the photo clearly.';
               _currentStep = _PipelineStep.idle;
               _imageFiles.removeAt(i);
             });
             if (_imageFiles.isEmpty) {
               _pickImage(ImageSource.camera);
             }
           }
           return;
        }
      
        if (mounted) {
          setState(() {
            _error = 'OCR failed on Image ${i+1}: ${e.toString()}';
            _currentStep = _PipelineStep.idle;
          });
        }
        return;
      }
    }

    if (allItems.isEmpty) {
      if (mounted) {
        setState(() {
          _error = 'No Honda part numbers found across ${_imageFiles.length} images. Try clearer photos.';
          _currentStep = _PipelineStep.idle;
        });
      }
      return;
    }

    // Deduplicate across all pages
    final seen = <String>{};
    final deduped = allItems.where((i) => seen.add(i.correctedPartNo)).toList();

    _setStep(_PipelineStep.done);

    final mergedResult = MemoOcrResult(
      header: finalHeader ?? ExtractedMemoHeader(
        customerName: 'OCR Generated Order',
        area: 'Warehouse Floor',
        memoNumber: 'MEMO-OCR-${DateTime.now().millisecondsSinceEpoch}',
      ),
      items: deduped,
      rawOcrDump: finalDump,
      imagePath: _imageFiles.first.path, // Pass first image path as primary
    );

    if (mounted) {
      context.push('/ocr-review', extra: {
        'ocrResult': mergedResult,
        'imagePath': _imageFiles.first.path,
      });
      
      // Clear images after successful parsing so user starts fresh next time
      setState(() {
        _imageFiles.clear();
        _currentStep = _PipelineStep.idle;
      });
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
                  child: _imageFiles.isEmpty
                      ? _EmptyImageState(
                          onCamera: () => _pickImage(ImageSource.camera),
                          onGallery: () => _pickImage(ImageSource.gallery),
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _imageFiles.length,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                                          child: Image.file(_imageFiles[index], fit: BoxFit.cover, width: 220),
                                        ),
                                        if (!_isProcessing)
                                          Positioned(
                                            top: 8,
                                            right: 8,
                                            child: InkWell(
                                              onTap: () => _removeImage(index),
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: const BoxDecoration(
                                                  color: Colors.black54,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.close, color: Colors.white, size: 20),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: AppDimensions.md),
                            Row(
                              children: [
                                Expanded(
                                  child: AppButton(
                                    label: 'Add Photo',
                                    variant: AppButtonVariant.outline,
                                    icon: Icons.camera_alt_outlined,
                                    onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
                                  ),
                                ),
                                const SizedBox(width: AppDimensions.sm),
                                Expanded(
                                  child: AppButton(
                                    label: 'Gallery',
                                    variant: AppButtonVariant.secondary,
                                    icon: Icons.photo_library_outlined,
                                    onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
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
                    onPressed: _imageFiles.isEmpty || _isProcessing
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
