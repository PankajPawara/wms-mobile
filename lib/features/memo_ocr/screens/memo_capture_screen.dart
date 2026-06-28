import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/barcode_util.dart';
import '../../../shared/widgets/app_button.dart';

class MemoCaptureScreen extends ConsumerStatefulWidget {
  const MemoCaptureScreen({super.key});

  @override
  ConsumerState<MemoCaptureScreen> createState() => _MemoCaptureScreenState();
}

class _MemoCaptureScreenState extends ConsumerState<MemoCaptureScreen> {
  File? _imageFile;
  bool _isProcessing = false;
  String? _error;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: source, imageQuality: 90, maxWidth: 2000);
    if (picked == null) return;
    setState(() {
      _imageFile = File(picked.path);
      _error = null;
    });
  }

  Future<void> _processOcr() async {
    if (_imageFile == null) return;
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFile(_imageFile!);
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final rawText = recognizedText.text;
      final partNumbers = BarcodeUtil.extractPartNumbers(rawText);

      if (partNumbers.isEmpty) {
        setState(() {
          _error = 'No Honda part numbers found in the image. Try a clearer photo.';
          _isProcessing = false;
        });
        return;
      }

      final items = partNumbers
          .map((p) => {'part_no': p, 'required_qty': 1})
          .toList();

      setState(() => _isProcessing = false);
      if (mounted) {
        context.push('/ocr-review', extra: {'items': items});
      }
    } catch (e) {
      setState(() {
        _error = 'OCR failed: ${e.toString()}';
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.captureMemo),
        backgroundColor: Colors.white,
      ),
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
                                  onPressed: () =>
                                      _pickImage(ImageSource.camera),
                                ),
                              ),
                              const SizedBox(width: AppDimensions.sm),
                              Expanded(
                                child: AppButton(
                                  label: 'Gallery',
                                  variant: AppButtonVariant.secondary,
                                  icon: Icons.photo_library_outlined,
                                  onPressed: () =>
                                      _pickImage(ImageSource.gallery),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
              if (_error != null) ...
                [
                  const SizedBox(height: AppDimensions.sm),
                  Container(
                    padding: const EdgeInsets.all(AppDimensions.sm),
                    decoration: BoxDecoration(
                        color: AppColors.dangerLight,
                        borderRadius:
                            BorderRadius.circular(AppDimensions.radiusMd)),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: AppColors.danger, fontSize: 13)),
                  ),
                ],
              const SizedBox(height: AppDimensions.md),
              AppButton(
                label: _isProcessing
                    ? AppStrings.extracting
                    : AppStrings.generatePickupList,
                icon: Icons.document_scanner_outlined,
                onPressed: _imageFile == null || _isProcessing
                    ? null
                    : _processOcr,
                isLoading: _isProcessing,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyImageState extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  const _EmptyImageState(
      {required this.onCamera, required this.onGallery});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.border.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border:
            Border.all(color: AppColors.border, style: BorderStyle.solid),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.document_scanner_outlined,
              size: 64, color: AppColors.textSecondary),
          const SizedBox(height: AppDimensions.md),
          const Text(
            'Capture or upload the order memo',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: AppDimensions.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SourceButton(
                icon: Icons.camera_alt_rounded,
                label: 'Camera',
                onTap: onCamera,
              ),
              const SizedBox(width: AppDimensions.md),
              _SourceButton(
                icon: Icons.photo_library_outlined,
                label: 'Gallery',
                onTap: onGallery,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SourceButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.lg, vertical: AppDimensions.md),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 28),
            const SizedBox(height: AppDimensions.xs),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
