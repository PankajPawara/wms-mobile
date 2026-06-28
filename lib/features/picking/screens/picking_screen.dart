import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/status_badge.dart';

class PickingScreen extends ConsumerStatefulWidget {
  final String orderId;
  const PickingScreen({super.key, required this.orderId});

  @override
  ConsumerState<PickingScreen> createState() => _PickingScreenState();
}

class _PickingScreenState extends ConsumerState<PickingScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _scannerOpen = true;
  String? _lastScanResult;
  bool _lastScanCorrect = false;

  // Dummy items for UI demo — replace with real provider
  final List<Map<String, dynamic>> _items = [
    {
      'part_no': '22201-KON-DU2',
      'description': 'DISK CLUTCH FRICTION',
      'location': 'A2-15',
      'required_qty': 10,
      'picked_qty': 7,
      'status': 'pending',
    },
    {
      'part_no': '31500-KWN-921',
      'description': 'BATTERY 12V 3AH',
      'location': 'B1-03',
      'required_qty': 5,
      'picked_qty': 5,
      'status': 'picked',
    },
  ];

  int get _currentIndex =>
      _items.indexWhere((i) => i['status'] == 'pending');
  bool get _allDone => _items.every((i) => i['status'] == 'picked');

  void _onBarcodeDetected(BarcodeCapture capture) {
    final barcode = capture.barcodes.firstOrNull?.rawValue ?? '';
    if (_currentIndex < 0) return;
    final current = _items[_currentIndex];
    final expected = current['part_no'] as String;

    if (barcode.toUpperCase() == expected.toUpperCase()) {
      HapticFeedback.mediumImpact();
      setState(() {
        final picked = (current['picked_qty'] as int) + 1;
        current['picked_qty'] = picked;
        if (picked >= (current['required_qty'] as int)) {
          current['status'] = 'picked';
        }
        _lastScanResult = expected;
        _lastScanCorrect = true;
      });
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _lastScanResult = barcode;
        _lastScanCorrect = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current =
        _currentIndex >= 0 ? _items[_currentIndex] : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Picking — ${widget.orderId}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppDimensions.md),
            child: Center(
              child: Text(
                '${_items.where((i) => i['status'] == 'picked').length}/${_items.length}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Current item card
          if (current != null) ...
            [
              Container(
                margin: const EdgeInsets.all(AppDimensions.md),
                padding: const EdgeInsets.all(AppDimensions.md),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(AppDimensions.radiusLg),
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Current Item',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppDimensions.xs),
                    Text(
                      current['part_no'] as String,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      current['description'] as String,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: AppDimensions.sm),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            color: AppColors.primary, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          current['location'] as String,
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text(
                          '${current['picked_qty']}/${current['required_qty']} picked',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.sm),
                    LinearProgressIndicator(
                      value: (current['picked_qty'] as int) /
                          (current['required_qty'] as int),
                      backgroundColor: AppColors.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primary),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
            ],

          // Scan result feedback
          if (_lastScanResult != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.md),
              padding: const EdgeInsets.all(AppDimensions.sm),
              decoration: BoxDecoration(
                color: _lastScanCorrect
                    ? AppColors.successLight
                    : AppColors.dangerLight,
                borderRadius:
                    BorderRadius.circular(AppDimensions.radiusMd),
              ),
              child: Row(
                children: [
                  Icon(
                    _lastScanCorrect
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    color: _lastScanCorrect
                        ? AppColors.success
                        : AppColors.danger,
                  ),
                  const SizedBox(width: AppDimensions.sm),
                  Expanded(
                    child: Text(
                      _lastScanCorrect
                          ? AppStrings.correctProduct
                          : '${AppStrings.wrongProduct} Expected: ${current?['part_no']}',
                      style: TextStyle(
                          color: _lastScanCorrect
                              ? AppColors.success
                              : AppColors.danger,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: AppDimensions.sm),

          // Remaining items list
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.md),
              itemCount: _items.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppDimensions.xs),
              itemBuilder: (context, i) {
                final item = _items[i];
                final isCurrent = i == _currentIndex;
                return Opacity(
                  opacity: isCurrent ? 1 : 0.6,
                  child: Container(
                    padding: const EdgeInsets.all(AppDimensions.sm),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(
                          AppDimensions.radiusMd),
                      border: Border.all(
                          color: isCurrent
                              ? AppColors.primary
                              : AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(item['part_no'] as String,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              Text(item['location'] as String,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        Text(
                            '${item['picked_qty']}/${item['required_qty']}',
                            style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: AppDimensions.sm),
                        StatusBadge(status: item['status'] as String),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Scanner / Complete button
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(AppDimensions.md),
            child: _allDone
                ? AppButton(
                    label: AppStrings.completePicking,
                    icon: Icons.check_rounded,
                    onPressed: () =>
                        context.replace('/picking-summary/${widget.orderId}'),
                  )
                : Column(
                    children: [
                      if (_scannerOpen)
                        SizedBox(
                          height: 120,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                                AppDimensions.radiusMd),
                            child: MobileScanner(
                              controller: _controller,
                              onDetect: _onBarcodeDetected,
                            ),
                          ),
                        ),
                      const SizedBox(height: AppDimensions.sm),
                      AppButton(
                        label: _scannerOpen ? 'Hide Scanner' : 'Open Scanner',
                        variant: AppButtonVariant.outline,
                        icon: Icons.qr_code_scanner_rounded,
                        onPressed: () =>
                            setState(() => _scannerOpen = !_scannerOpen),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
