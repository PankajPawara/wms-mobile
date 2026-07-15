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
import '../../../shared/widgets/empty_state_placeholder.dart';

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

    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFile(_imageFile!);
      final recognizedText = await textRecognizer.processImage(inputImage);

      final rawText = recognizedText.text;
      final parsedItems = BarcodeUtil.parseOcrText(rawText);

      if (parsedItems.isEmpty) {
        if (mounted) {
          setState(() {
            _error = 'No Honda part numbers found in the image. Try a clearer photo.';
            _isProcessing = false;
          });
        }
        return;
      }

      final customerName = BarcodeUtil.extractCustomerName(rawText) ?? 'OCR Generated Order';
      final customerLocation = BarcodeUtil.extractArea(rawText) ?? 'Warehouse Floor';
      // Use full millisecond timestamp for uniqueness (no modulo collision risk)
      final memoNumber = BarcodeUtil.extractMemoNumber(rawText) ?? 'MEMO-OCR-${DateTime.now().millisecondsSinceEpoch}';

      final items = parsedItems
          .map((item) => {
                'part_no': item['part_no'],
                'required_qty': item['quantity'],
                'price': item['price'],
                'description': item['description'],
                'location': item['location'],
                'stock': item['stock'],
              })
          .toList();

      if (mounted) {
        setState(() => _isProcessing = false);
        context.push('/ocr-review', extra: {
          'items': items,
          'customerName': customerName,
          'customerLocation': customerLocation,
          'memoNumber': memoNumber,
          'rawText': rawText,
          'imagePath': _imageFile?.path,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'OCR failed: ${e.toString()}';
          _isProcessing = false;
        });
      }
    } finally {
      // Always close the recognizer to prevent resource leaks
      await textRecognizer.close();
    }
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
              Padding(
                padding: const EdgeInsets.only(bottom: 84), // Spacing to avoid overlap with floating bottom nav
                child: AppButton(
                  label: _isProcessing
                      ? AppStrings.extracting
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

class _EmptyImageState extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  const _EmptyImageState({required this.onCamera, required this.onGallery});

  @override
  Widget build(BuildContext context) {
    return EmptyStatePlaceholder(
      icon: Icons.document_scanner_outlined,
      title: 'Generate Pickup List',
      subtitle: 'Capture or upload an order memo image to automatically extract items, descriptions, locations, prices, and stock counts.',
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
