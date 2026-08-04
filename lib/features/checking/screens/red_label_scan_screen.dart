import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/database/app_database.dart';
import '../../../core/pipeline/red_label_parser.dart';
import '../../../core/services/parts_master_service.dart';

/// Screen for the checking team to scan Honda red labels.
///
/// Flow:
///   1. ML Kit mobile_scanner reads QR code → gets part number instantly.
///   2. ML Kit OCR reads remaining text → description, mfg date, MRP, qty.
///   3. Confirmation card shown — checker reviews & confirms.
///   4. On confirm → PartsMasterService.learnFromRedLabel() updates the DB.
///
/// Roles: accessible to checker, stock_manager, admin.
class RedLabelScanScreen extends ConsumerStatefulWidget {
  const RedLabelScanScreen({super.key});

  @override
  ConsumerState<RedLabelScanScreen> createState() => _RedLabelScanScreenState();
}

class _RedLabelScanScreenState extends ConsumerState<RedLabelScanScreen> {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: [BarcodeFormat.qrCode, BarcodeFormat.code128, BarcodeFormat.code39],
  );
  final TextRecognizer _textRecognizer = TextRecognizer();

  RedLabelData? _parsedData;
  bool _isSaving = false;
  bool _saved = false;
  String? _error;

  // Track processed QR values to avoid re-processing the same barcode
  String? _lastProcessedQr;

  @override
  void dispose() {
    _scanner.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Called when mobile_scanner detects a barcode / QR code.
  // ---------------------------------------------------------------------------
  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_parsedData != null || _isSaving) return;

    final barcode = capture.barcodes.firstOrNull;
    final qrValue = barcode?.rawValue?.trim() ?? '';

    if (qrValue.isEmpty || qrValue == _lastProcessedQr) return;
    _lastProcessedQr = qrValue;

    // Use the QR value as the part number (primary path — no OCR needed for part no)
    // The QR on Honda labels encodes the raw part number without dashes (e.g. "33610KSP860")
    _processQrAndOcr(qrPartNo: qrValue, imageBytes: capture.image);
  }

  Future<void> _processQrAndOcr({
    required String qrPartNo,
    required Uint8List? imageBytes,
  }) async {
    String ocrText = '';

    // Try OCR on the captured image bytes to extract the other label fields.
    // We create an InputImage from raw bytes; size is required by ML Kit.
    if (imageBytes != null) {
      try {
        // Decode image dimensions from the bytes
        final codec = await decodeImageFromList(imageBytes);
        final inputImage = InputImage.fromBytes(
          bytes: imageBytes,
          metadata: InputImageMetadata(
            size: Size(codec.width.toDouble(), codec.height.toDouble()),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.bgra8888,
            bytesPerRow: codec.width * 4,
          ),
        );
        final result = await _textRecognizer.processImage(inputImage);
        ocrText = result.text;
      } catch (_) {
        // OCR failure is non-fatal — we still have the QR part number
      }
    }

    final parsed = RedLabelParser.parse(ocrText, qrPartNo: qrPartNo);

    if (mounted) {
      await _scanner.stop();
      setState(() {
        _parsedData = parsed;
        _error = null;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Confirm and save to PartsMaster
  // ---------------------------------------------------------------------------
  Future<void> _confirmAndSave() async {
    if (_parsedData == null) return;
    setState(() => _isSaving = true);

    try {
      final db = ref.read(appDatabaseProvider);
      final service = PartsMasterService(db);

      await service.learnFromRedLabel(
        rawBarcode:  _parsedData!.partNoRaw,
        description: _parsedData!.description,
        mrp:         _parsedData!.mrp,
        qty:         _parsedData!.qty,
        mfgMonth:    _parsedData!.mfgMonth,
        mfgYear:     _parsedData!.mfgYear,
      );

      if (mounted) {
        setState(() {
          _isSaving = false;
          _saved = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = 'Save failed: $e';
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Reset to scan another label
  // ---------------------------------------------------------------------------
  void _reset() {
    setState(() {
      _parsedData = null;
      _saved = false;
      _error = null;
      _lastProcessedQr = null;
    });
    _scanner.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _parsedData == null
          ? _buildScannerView()
          : _buildConfirmationView(),
    );
  }

  // ---------------------------------------------------------------------------
  // Scanner view — camera live feed with QR targeting overlay
  // ---------------------------------------------------------------------------
  Widget _buildScannerView() {
    return Stack(
      children: [
        MobileScanner(
          controller: _scanner,
          onDetect: _onBarcodeDetected,
        ),
        // Targeting overlay
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        // Instruction banner
        Positioned(
          bottom: 48,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Text(
                'Point at the QR code on the Honda red label',
                style: TextStyle(color: Colors.white, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Confirmation view — shows parsed data for checker to review
  // ---------------------------------------------------------------------------
  Widget _buildConfirmationView() {
    final d = _parsedData!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _saved ? Colors.green.withOpacity(0.2) : AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _saved ? Colors.green : AppColors.primary,
                    width: 1,
                  ),
                ),
                child: Text(
                  _saved ? '✅ Saved to DB' : '📋 Review & Confirm',
                  style: TextStyle(
                    color: _saved ? Colors.green : AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Data card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _saved ? Colors.green.withOpacity(0.4) : AppColors.primary.withOpacity(0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _labelRow('Part No (Normalized)', d.partNoNorm, isHighlight: true),
                _labelRow('Part No (Raw Barcode)', d.partNoRaw),
                const Divider(height: 24),
                _labelRow('Description', d.description.isNotEmpty ? d.description : '—'),
                _labelRow('MRP', d.mrp > 0 ? '₹${d.mrp.toStringAsFixed(2)}' : '—'),
                _labelRow('Quantity', '${d.qty}'),
                _labelRow(
                  'Manufactured In',
                  (d.mfgMonth.isNotEmpty && d.mfgYear.isNotEmpty)
                      ? '${d.mfgMonth} ${d.mfgYear}'
                      : '—',
                  isHighlight: d.mfgMonth.isNotEmpty,
                ),
              ],
            ),
          ),

          // Warning if OCR couldn't extract some fields
          if (!d.isValid || d.description.isEmpty || d.mfgMonth.isEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.amber, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Some fields could not be read by OCR. '
                      'You can still save the part number${d.mrp > 0 ? " and MRP" : ""}.',
                      style: const TextStyle(color: Colors.amber, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withOpacity(0.4)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          ],

          const SizedBox(height: 28),

          // Action buttons
          if (!_saved) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _confirmAndSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(_isSaving ? 'Saving…' : 'Confirm & Save to Parts Master'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : _reset,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan Again'),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _reset,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan Next Label'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.done_all),
                label: const Text('Done'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _labelRow(String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isHighlight ? AppColors.primary : AppColors.textPrimary,
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
