import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

enum _ScanState { scanning, searching, found, notFound, multipleLocations }

class ScanToFindScreen extends ConsumerStatefulWidget {
  const ScanToFindScreen({super.key});

  @override
  ConsumerState<ScanToFindScreen> createState() => _ScanToFindScreenState();
}

class _ScanToFindScreenState extends ConsumerState<ScanToFindScreen>
    with TickerProviderStateMixin {
  _ScanState _state = _ScanState.scanning;
  final _manualController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Mock result data (will be replaced by real API calls)
  Map<String, dynamic>? _foundProduct;
  String _scannedBarcode = '';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 0.85, end: 1.15).animate(_pulseController);
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _pulseController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null || _state != _ScanState.scanning) return;
    HapticFeedback.mediumImpact();
    _searchProduct(barcode);
  }

  Future<void> _searchProduct(String barcode) async {
    setState(() {
      _scannedBarcode = barcode;
      _state = _ScanState.searching;
    });

    try {
      final db = ref.read(appDatabaseProvider);
      final match = await (db.select(db.inventory)
            ..where((t) => t.barcode.equals(barcode)))
          .getSingleOrNull();

      if (match != null) {
        if (!mounted) return;
        setState(() {
          _foundProduct = {
            'partNo': match.partNo,
            'description': match.description ?? '',
            'location': match.location,
            'locationLabel': 'Location: ${match.location}',
            'area': 'MAIN WAREHOUSE',
            'multipleLocations': false,
          };
          _state = _ScanState.found;
        });
        return;
      }

      final api = ref.read(apiClientProvider);
      final response = await api.get(ApiEndpoints.inventoryBarcode(barcode));
      final data = response['data'] as Map<String, dynamic>?;
      final product = data?['product'] as Map<String, dynamic>?;

      if (product != null) {
        if (!mounted) return;
        setState(() {
          _foundProduct = {
            'partNo': product['part_no'] ?? '',
            'description': product['description'] ?? '',
            'location': product['location'] ?? '',
            'locationLabel': 'Location: ${product['location'] ?? ''}',
            'area': 'MAIN WAREHOUSE',
            'multipleLocations': false,
          };
          _state = _ScanState.found;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _state = _ScanState.notFound;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ScanState.notFound;
      });
    }
  }

  void _scanAnother() {
    setState(() {
      _state = _ScanState.scanning;
      _foundProduct = null;
      _scannedBarcode = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _state == _ScanState.scanning || _state == _ScanState.searching
          ? Colors.black
          : Colors.white,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: switch (_state) {
          _ScanState.scanning => _buildScanning(),
          _ScanState.searching => _buildSearching(),
          _ScanState.found => _buildFound(),
          _ScanState.notFound => _buildNotFound(),
          _ScanState.multipleLocations => _buildMultipleLocations(),
        },
      ),
    );
  }

  // ─── SCANNING STATE ────────────────────────────────────────────────────
  Widget _buildScanning() {
    return Stack(
      key: const ValueKey('scanning'),
      children: [
        // Camera preview
        MobileScanner(
          controller: _scannerController,
          onDetect: _onBarcodeDetected,
        ),

        // Dark overlay with viewfinder cutout
        SafeArea(
          child: Column(
            children: [
              // App bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white),
                      onPressed: () => context.go('/home'),
                    ),
                    const Expanded(
                      child: Text('Scan To Find',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.history_rounded, color: Colors.white),
                      onPressed: () => context.push('/history'),
                    ),
                  ],
                ),
              ),

              // Instruction text
              const SizedBox(height: 16),
              const Text(
                'Scan product barcode to\nfind its location',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 20),

              // Viewfinder box
              Container(
                width: 250,
                height: 160,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    children: [
                      // Corner decorations
                      ..._buildCorners(),
                      // Red scan line
                      Positioned(
                        top: 70,
                        left: 0,
                        right: 0,
                        child: Container(height: 2, color: AppColors.scannerLine),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Flashlight + Gallery buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CameraButton(
                    icon: Icons.bolt_rounded,
                    onTap: () => _scannerController.toggleTorch(),
                  ),
                  const SizedBox(width: 24),
                  _CameraButton(
                    icon: Icons.image_outlined,
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: 24),

              const Text(
                'or enter product number',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 10),

              // Manual input
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Enter product number',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white12,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: const Icon(Icons.keyboard_rounded,
                              color: Colors.white38, size: 20),
                        ),
                        onSubmitted: (v) {
                          if (v.trim().isNotEmpty) _searchProduct(v.trim());
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Bottom nav
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: const AppBottomNav(currentIndex: 1),
        ),
      ],
    );
  }

  List<Widget> _buildCorners() {
    const color = AppColors.primary;
    const size = 20.0;
    const thickness = 3.0;
    return [
      Positioned(
          top: 0,
          left: 0,
          child: Container(
              width: size,
              height: thickness,
              color: color)),
      Positioned(
          top: 0,
          left: 0,
          child: Container(
              width: thickness,
              height: size,
              color: color)),
      Positioned(
          top: 0,
          right: 0,
          child: Container(
              width: size,
              height: thickness,
              color: color)),
      Positioned(
          top: 0,
          right: 0,
          child: Container(
              width: thickness,
              height: size,
              color: color)),
      Positioned(
          bottom: 0,
          left: 0,
          child: Container(
              width: size,
              height: thickness,
              color: color)),
      Positioned(
          bottom: 0,
          left: 0,
          child: Container(
              width: thickness,
              height: size,
              color: color)),
      Positioned(
          bottom: 0,
          right: 0,
          child: Container(
              width: size,
              height: thickness,
              color: color)),
      Positioned(
          bottom: 0,
          right: 0,
          child: Container(
              width: thickness,
              height: size,
              color: color)),
    ];
  }

  // ─── SEARCHING STATE ────────────────────────────────────────────────────
  Widget _buildSearching() {
    return SafeArea(
      key: const ValueKey('searching'),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white),
                  onPressed: _scanAnother,
                ),
                const Text('Scan To Find',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Spacer(),
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.15),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.5), width: 2),
              ),
              child: const Icon(Icons.search_rounded,
                  color: AppColors.primary, size: 48),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Searching...',
            style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Please wait',
            style: TextStyle(color: Colors.white60, fontSize: 14),
          ),
          const SizedBox(height: 8),
          const Text(
            'Checking inventory locations\nand storage area',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
          ),
          const Spacer(),
          const AppBottomNav(currentIndex: 1),
        ],
      ),
    );
  }

  // ─── FOUND STATE ────────────────────────────────────────────────────────
  Widget _buildFound() {
    final product = _foundProduct!;
    return Column(
      key: const ValueKey('found'),
      children: [
        // App bar (purple)
        Container(
          color: AppColors.primary,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white),
                    onPressed: _scanAnother,
                  ),
                  const Text('Scan To Find',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.history_rounded, color: Colors.white),
                    onPressed: () => context.push('/history'),
                  ),
                ],
              ),
            ),
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Product Found badge
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.success),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: AppColors.success, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Product Found',
                          style: TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Product details card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Product No.',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF6B7280))),
                      Text(
                        product['partNo'] as String,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111827)),
                      ),
                      const SizedBox(height: 12),
                      const Text('Description',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF6B7280))),
                      Text(
                        product['description'] as String,
                        style: const TextStyle(
                            fontSize: 15, color: Color(0xFF374151)),
                      ),
                      const SizedBox(height: 12),
                      const Text('Available Stock',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF6B7280))),
                      Text(
                        '${product['stock']} NOS',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.success),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Location details card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFDDD6FE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Location Details',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded,
                              color: AppColors.primary, size: 20),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Location',
                                  style: TextStyle(
                                      fontSize: 10, color: Color(0xFF6B7280))),
                              Text(
                                product['location'] as String,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF111827)),
                              ),
                              Text(
                                product['locationLabel'] as String,
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF6B7280)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.warehouse_rounded,
                              color: Color(0xFF6B7280), size: 18),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Area',
                                  style: TextStyle(
                                      fontSize: 10, color: Color(0xFF6B7280))),
                              Text(
                                product['area'] as String,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF374151)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Get Directions button
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Get Directions',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 10),

                // Scan Another button
                SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _scanAnother,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Scan Another',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),

        const AppBottomNav(currentIndex: 1),
      ],
    );
  }

  // ─── NOT FOUND STATE ─────────────────────────────────────────────────────
  Widget _buildNotFound() {
    return Column(
      key: const ValueKey('notFound'),
      children: [
        Container(
          color: AppColors.primary,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white),
                    onPressed: _scanAnother,
                  ),
                  const Text('Scan To Find',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
        const Icon(Icons.warning_amber_rounded,
            color: AppColors.warning, size: 64),
        const SizedBox(height: 16),
        const Text('Product Not Found',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
        const SizedBox(height: 8),
        Text(
          'Product No. $_scannedBarcode',
          style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'This product is not available in locations or storage.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF), height: 1.5),
          ),
        ),
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: SizedBox(
            height: 50,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _scanAnother,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Scan Another',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
        const Spacer(),
        const AppBottomNav(currentIndex: 1),
      ],
    );
  }

  // ─── MULTIPLE LOCATIONS STATE ─────────────────────────────────────────────
  Widget _buildMultipleLocations() {
    final locations = [
      {'code': 'A2-15-03', 'area': 'MAIN WAREHOUSE', 'stock': 6},
      {'code': 'B1-07-02', 'area': 'MAIN WAREHOUSE', 'stock': 6},
    ];
    return Column(
      key: const ValueKey('multiple'),
      children: [
        Container(
          color: AppColors.primary,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white),
                    onPressed: _scanAnother,
                  ),
                  const Text('Scan To Find',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on_rounded,
                            color: AppColors.warning, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Multiple Locations',
                          style: TextStyle(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Product No.\n$_scannedBarcode',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827))),
                const SizedBox(height: 4),
                Text('Available Locations (${locations.length})',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                const SizedBox(height: 12),
                ...locations.map((loc) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x0F000000),
                              blurRadius: 6,
                              offset: Offset(0, 2)),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_rounded,
                              color: AppColors.primary, size: 22),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(loc['code'] as String,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Color(0xFF111827))),
                              Text(loc['area'] as String,
                                  style: const TextStyle(
                                      fontSize: 11, color: Color(0xFF6B7280))),
                            ],
                          ),
                          const Spacer(),
                          Text('Stock: ${loc['stock']} NOS',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.success)),
                        ],
                      ),
                    )),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('View All Locations',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _scanAnother,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Scan Another',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const AppBottomNav(currentIndex: 1),
      ],
    );
  }
}

class _CameraButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CameraButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white12,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}
