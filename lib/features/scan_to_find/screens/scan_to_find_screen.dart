import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:camera/camera.dart';
import '../widgets/scanner_camera_view.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/utils/barcode_util.dart';
import '../../../shared/widgets/empty_state_placeholder.dart';
import '../../../core/utils/scan_feedback.dart';


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
  final _manualFocusNode = FocusNode();
  final GlobalKey<ScannerCameraViewState> _scannerKey = GlobalKey();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _scanLineController;

  // Result data
  Map<String, dynamic>? _foundProduct;
  String _scannedBarcode = '';
  List<InventoryData> _multipleLocationsList = [];

  // Manual search & automatic triggers state
  bool _isManualMode = false;
  String _manualSearchQuery = '';
  String _searchByField = 'Part No'; // 'Part No', 'Location', 'Description'
  List<InventoryData> _manualSearchResults = [];
  bool _isManualSearching = false;

  bool _isDetecting = false;
  Timer? _detectionTimer;

  // Flash and HDR toggles
  FlashMode _flashMode = FlashMode.off;

  // Event channel for light sensor
  static const EventChannel _lightSensorChannel = EventChannel('com.example.wms_mobile/light_sensor');
  StreamSubscription<double>? _lightSensorSubscription;

  // Recent searches history
  List<String> _recentQueries = [];

  Future<void> _loadRecentQueries() async {
    try {
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      final jsonStr = await storage.read(key: 'wms_search_history');
      if (jsonStr != null) {
        final List<dynamic> decoded = json.decode(jsonStr);
        if (mounted) {
          setState(() {
            _recentQueries = decoded.cast<String>();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _addRecordToHistory(String query) async {
    final trimmed = query.trim().toUpperCase();
    if (trimmed.isEmpty) return;

    _recentQueries.remove(trimmed);
    _recentQueries.insert(0, trimmed);

    if (_recentQueries.length > 8) {
      _recentQueries = _recentQueries.sublist(0, 8);
    }

    if (mounted) setState(() {});

    try {
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      await storage.write(key: 'wms_search_history', value: json.encode(_recentQueries));
    } catch (_) {}
  }

  Future<void> _clearSearchHistory() async {
    if (mounted) {
      setState(() {
        _recentQueries = [];
      });
    }
    try {
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      await storage.delete(key: 'wms_search_history');
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _loadRecentQueries();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 0.85, end: 1.15).animate(_pulseController);

    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    // Subscribe to native light sensor
    try {
      _lightSensorSubscription = _lightSensorChannel
          .receiveBroadcastStream()
          .map((event) => (event as num).toDouble())
          .listen((lux) {
        if (_flashMode == FlashMode.auto && _state == _ScanState.scanning && !_isManualMode) {
          if (lux < 15.0) {
            _setTorch(true);
          } else if (lux > 30.0) {
            _setTorch(false);
          }
        }
      });
    } catch (_) {
      // Light sensor not available on this device
    }
  }

  @override
  void dispose() {
    _lightSensorSubscription?.cancel();
    
    _pulseController.dispose();
    _scanLineController.dispose();
    _manualController.dispose();
    _manualFocusNode.dispose();
    _detectionTimer?.cancel();
    super.dispose();
  }

  Future<bool> _searchProduct(String barcode, bool isOcr) async {
    setState(() {
      _scannedBarcode = barcode;
      _state = _ScanState.searching;
    });

    try {
      final db = ref.read(appDatabaseProvider);
      var queryBarcode = barcode.trim().toUpperCase().replaceAll('O', '0');
      
      var matches = await (db.select(db.inventory)
            ..where((t) => 
              CustomExpression<bool>("REPLACE(UPPER(barcode), 'O', '0') LIKE '%$queryBarcode%' OR REPLACE(UPPER(part_no), 'O', '0') LIKE '%$queryBarcode%'")
            ))
          .get();

      if (matches.isEmpty && isOcr) {
        // Run fuzzy match
        final allParts = await db.select(db.inventory).get();
        final partNumbersList = allParts.map((e) => e.partNo).toList();
        final bestMatch = BarcodeUtil.findBestMatch(queryBarcode, partNumbersList);
        if (bestMatch != null) {
           queryBarcode = bestMatch;
           matches = await (db.select(db.inventory)
                ..where((t) => t.partNo.equals(bestMatch)))
              .get();
        }
      }

      if (matches.isNotEmpty) {
        ScanFeedback.triggerSuccess();
        _addRecordToHistory(matches.first.partNo);
        if (!mounted) return true;
        if (matches.length == 1) {
          final match = matches.first;
          setState(() {
            _scannedBarcode = match.partNo; // update to the matched part no
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
        } else {
          setState(() {
            _multipleLocationsList = matches;
            _state = _ScanState.multipleLocations;
          });
        }
        return true;
      }

      final api = ref.read(apiClientProvider);
      final response = await api.get(ApiEndpoints.inventoryBarcode(queryBarcode));
      final data = response['data'] as Map<String, dynamic>?;
      final product = data?['product'] as Map<String, dynamic>?;

      if (product != null) {
        ScanFeedback.triggerSuccess();
        _addRecordToHistory(product['part_no'] ?? '');
        if (!mounted) return true;
        setState(() {
          _scannedBarcode = product['part_no'] ?? queryBarcode;
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
        return true;
      } else {
        if (!mounted) return false;
        if (!isOcr) {
           // For barcode, we just return false and keep scanning
           setState(() {
             _state = _ScanState.scanning; // Go back to scanning silently
           });
           return false;
        } else {
           ScanFeedback.triggerError();
           setState(() {
             _state = _ScanState.scanning;
             _isManualMode = true;
             _manualController.text = _scannedBarcode;
             _manualSearchQuery = _scannedBarcode;
             _searchByField = 'Part No';
           });
           _performManualSearch();
           return false;
        }
      }
    } catch (e) {
      if (!mounted) return false;
      if (!isOcr) {
         setState(() {
           _state = _ScanState.scanning; // Go back to scanning silently
         });
         return false;
      } else {
         ScanFeedback.triggerError();
         setState(() {
           _state = _ScanState.scanning;
           _isManualMode = true;
           _manualController.text = _scannedBarcode;
           _manualSearchQuery = _scannedBarcode;
           _searchByField = 'Part No';
         });
         _performManualSearch();
         return false;
      }
    }
  }
  void _setTorch(bool turnOn) {
    try {
      _scannerKey.currentState?.setTorch(turnOn);
    } catch (_) {}
  }

  void _cycleFlashMode() {
    setState(() {
      if (_flashMode == FlashMode.off) {
        _flashMode = FlashMode.torch;
        _setTorch(true);
      } else if (_flashMode == FlashMode.torch) {
        _flashMode = FlashMode.auto;
      } else {
        _flashMode = FlashMode.off;
        _setTorch(false);
      }
    });
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
    final location = GoRouterState.of(context).matchedLocation;
    if (location != '/scan-to-find') {
      if (_manualController.text.isNotEmpty || _manualSearchQuery.isNotEmpty || _isManualMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _manualController.clear();
          _manualSearchQuery = '';
          _isManualMode = false;
          if (mounted) setState(() {});
        });
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isManualMode) {
          setState(() {
            _isManualMode = false;
          });
        } else if (_state != _ScanState.scanning) {
          _scanAnother();
        } else {
          context.go('/home');
        }
      },
      child: Scaffold(
        backgroundColor: (_state == _ScanState.scanning || _state == _ScanState.searching) && !_isManualMode
            ? Colors.black
            : Theme.of(context).colorScheme.surface,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _isManualMode && _state == _ScanState.scanning
              ? _buildManualSearch()
              : switch (_state) {
                  _ScanState.scanning => _buildScanning(),
                  _ScanState.searching => _buildSearching(),
                  _ScanState.found => _buildFound(),
                  _ScanState.notFound => _buildNotFound(),
                  _ScanState.multipleLocations => _buildMultipleLocations(),
                },
        ),
      ),
    );
  }

    Widget _buildScanning() {
    return Stack(
      key: const ValueKey('scanning'),
      children: [
        ScannerCameraView(
          key: _scannerKey,
          onResult: (result, isOcr) {
            return _searchProduct(result, isOcr);
          },
          builder: (context, controller) {
            return CameraPreview(controller);
          },
        ),

        ColorFiltered(
          colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.6), BlendMode.srcOut),
          child: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                ),
              ),
              Center(
                child: Container(
                  width: AppDimensions.scannerViewfinderSize,
                  height: AppDimensions.scannerViewfinderSize,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          ),
        ),

        Center(
          child: SizedBox(
            width: AppDimensions.scannerViewfinderSize,
            height: AppDimensions.scannerViewfinderSize,
            child: Stack(
              children: [
                ..._buildCorners(),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 1500),
                  curve: Curves.easeInOut,
                  top: _isDetecting ? AppDimensions.scannerViewfinderSize - 4 : 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.6),
                          blurRadius: 12,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          _flashMode == FlashMode.torch
                              ? Icons.flash_on_rounded
                              : _flashMode == FlashMode.auto
                                  ? Icons.flash_auto_rounded
                                  : Icons.flash_off_rounded,
                          color: Colors.white,
                        ),
                        onPressed: _cycleFlashMode,
                      ),
                      Container(width: 1, height: 24, color: Colors.white24),
                      IconButton(
                        icon: const Icon(Icons.hdr_on_rounded, color: Colors.white),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('HDR Auto-enabled'), duration: Duration(seconds: 1)),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            color: Colors.black.withValues(alpha: 0.7),
            child: SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _BottomActionBtn(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    onTap: _scanFromGallery,
                  ),

                  GestureDetector(
                    onTap: _triggerCameraScan,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _isDetecting ? Colors.grey : AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.3),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: _isDetecting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 22),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isDetecting ? 'Scanning' : 'Scan',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),

                  _BottomActionBtn(
                    icon: Icons.keyboard_rounded,
                    label: 'Manual',
                    onTap: () {
                      setState(() {
                        _isManualMode = true;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCorners() {
    const color = AppColors.primary;
    const size = 20.0;
    const thickness = 5.0;
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
        ],
      ),
    );
  }

  Widget _buildFound() {
    final product = _foundProduct!;
    return Column(
      key: const ValueKey('found'),
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

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Product No.',
                          style: TextStyle(
                              fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      Text(
                        product['partNo'] as String,
                        style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                      const SizedBox(height: 12),
                      Text('Description',
                          style: TextStyle(
                              fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      Text(
                        product['description'] as String,
                        style: TextStyle(
                            fontSize: 15, color: Theme.of(context).colorScheme.onSurface),
                      ),
                      const SizedBox(height: 12),
                      Text('Available Stock',
                          style: TextStyle(
                              fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      Text(
                        '${product['stock'] ?? '--'} NOS',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.success),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primaryLight),
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
                              Text('Location',
                                  style: TextStyle(
                                      fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              Text(
                                product['location'] as String,
                                style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.onSurface),
                              ),
                              Text(
                                product['locationLabel'] as String,
                                style: TextStyle(
                                    fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.warehouse_rounded,
                              color: Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Area',
                                  style: TextStyle(
                                      fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              Text(
                                product['area'] as String,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.onSurface),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),



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
      ],
    );
  }

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
        Expanded(
          child: EmptyStatePlaceholder(
            icon: Icons.search_off_rounded,
            title: 'Product Not Found',
            subtitle: 'Part number "$_scannedBarcode" could not be found in active inventory master records. Double check the label or try manual search.',
            action: ElevatedButton.icon(
              onPressed: _scanAnother,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Try Scanning Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMultipleLocations() {
    final locations = _multipleLocationsList.map((m) => {
      'code': m.location,
      'area': 'MAIN WAREHOUSE',
      'stock': '--',
    }).toList();
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
                Text('Part No:\n${_multipleLocationsList.firstOrNull?.partNo ?? _scannedBarcode}',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface)),
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
                        color: Theme.of(context).colorScheme.surface,
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
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 28,
                                      color: Theme.of(context).colorScheme.onSurface)),
                              Text(loc['area'] as String,
                                  style: TextStyle(
                                      fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                          const Spacer(),
                          Text('Stock: ${loc['stock'] ?? '--'} NOS',
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
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('All locations view coming soon'), duration: Duration(seconds: 1)),
                    ),
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
      ],
    );
  }

  Future<void> _performManualSearch() async {
    if (_manualSearchQuery.trim().isEmpty) {
      setState(() {
        _manualSearchResults = [];
      });
      return;
    }
    setState(() => _isManualSearching = true);
    final db = ref.read(appDatabaseProvider);
    final query = _manualSearchQuery.trim().toUpperCase();

    List<InventoryData> results;
    if (_searchByField == 'Location') {
      results = await (db.select(db.inventory)..where((t) => t.location.upper().like('%$query%'))).get();
    } else if (_searchByField == 'Description') {
      results = await (db.select(db.inventory)..where((t) => t.description.upper().like('%$query%'))).get();
    } else {
      results = await (db.select(db.inventory)..where((t) => t.partNo.upper().like('%$query%') | t.barcode.like('%$query%'))).get();
    }

    if (results.isNotEmpty) {
      _addRecordToHistory(results.first.partNo);
    }

    setState(() {
      _manualSearchResults = results;
      _isManualSearching = false;
    });
  }

  void _triggerCameraScan() {
    setState(() {
      _isDetecting = true;
    });

    _detectionTimer?.cancel();
    _detectionTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isDetecting = false;
        });
      }
    });
  }

  void _showScanFailedDialog() {
    ScanFeedback.triggerError();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Scan Failed'),
        content: const Text(
          'Could not detect a barcode or part number. Would you like to search manually or try scanning again?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isManualMode = true;
              });
            },
            child: const Text('Search Manually', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _triggerCameraScan();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanFromGallery() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Analyzing image...', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.all]);
      final barcodes = await barcodeScanner.processImage(inputImage);
      await barcodeScanner.close();

      if (barcodes.isNotEmpty) {
        final rawVal = barcodes.first.rawValue;
        if (rawVal != null && rawVal.isNotEmpty) {
          if (mounted) {
            Navigator.pop(context);
          }
          await _searchProduct(rawVal, false);
          return;
        }
      }

      final textRecognizer = TextRecognizer();
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final partNumbers = BarcodeUtil.extractPartNumbers(recognizedText.text);

      if (mounted) {
        Navigator.pop(context);
      }

      if (partNumbers.isNotEmpty) {
        await _searchProduct(partNumbers.first, true);
      } else {
        final reg = RegExp(r'\b\d{8,14}\b');
        final matches = reg.allMatches(recognizedText.text);
        if (matches.isNotEmpty) {
          await _searchProduct(matches.first.group(0)!, true);
        } else {
          _showScanFailedDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
      }
      _showScanFailedDialog();
    }
  }

  Widget _buildManualSearch() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      key: const ValueKey('manual_search'),
      child: Column(
        children: [
          Container(
            color: AppColors.primary,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                      onPressed: () {
                        setState(() {
                          _isManualMode = false;
                        });
                      },
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                         child: TextField(
                          controller: _manualController,
                          focusNode: _manualFocusNode,
                          onChanged: (val) {
                            _manualSearchQuery = val;
                            _performManualSearch();
                          },
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Search inventory...',
                            hintStyle: const TextStyle(color: Colors.white60),
                            border: InputBorder.none,
                            prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70),
                            suffixIcon: _manualController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, color: Colors.white70, size: 20),
                                    onPressed: () {
                                      _manualController.clear();
                                      setState(() {
                                        _manualSearchQuery = '';
                                        _performManualSearch();
                                      });
                                      _manualFocusNode.requestFocus();
                                    },
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'Search by: ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 8),
                  _SearchChip(
                    label: 'Part No',
                    selected: _searchByField == 'Part No',
                    onSelected: (sel) {
                      if (sel) {
                        setState(() {
                          _searchByField = 'Part No';
                        });
                        _performManualSearch();
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  _SearchChip(
                    label: 'Location',
                    selected: _searchByField == 'Location',
                    onSelected: (sel) {
                      if (sel) {
                        setState(() {
                          _searchByField = 'Location';
                        });
                        _performManualSearch();
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  _SearchChip(
                    label: 'Description',
                    selected: _searchByField == 'Description',
                    onSelected: (sel) {
                      if (sel) {
                        setState(() {
                          _searchByField = 'Description';
                        });
                        _performManualSearch();
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),

            Expanded(
              child: _isManualSearching
                  ? const Center(child: CircularProgressIndicator())
                  : _manualController.text.isEmpty
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Recent Searches',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                  if (_recentQueries.isNotEmpty)
                                    TextButton(
                                      onPressed: _clearSearchHistory,
                                      child: Text('Clear', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error)),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_recentQueries.isEmpty)
                                 Text(
                                  'No search history yet',
                                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                )
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _recentQueries.map((query) {
                                    return ActionChip(
                                      label: Text(query, style: const TextStyle(fontSize: 12)),
                                      backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                                      side: BorderSide.none,
                                      onPressed: () {
                                        _manualController.text = query;
                                        _manualSearchQuery = query;
                                        _performManualSearch();
                                      },
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    );
                                  }).toList(),
                                ),
                            ],
                          ),
                        )
                      : _manualSearchResults.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off_rounded, size: 48, color: Theme.of(context).colorScheme.outlineVariant),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No items found',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _manualSearchResults.length,
                          itemBuilder: (context, index) {
                            final item = _manualSearchResults[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 1,
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                title: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Part No', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                    Text(
                                      item.partNo,
                                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (item.description != null && item.description!.isNotEmpty) ...[
                                        Text(item.description!, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                        const SizedBox(height: 8),
                                      ],
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 16),
                                            const SizedBox(width: 4),
                                            const Text('Location: ', style: TextStyle(fontSize: 11, color: AppColors.primary)),
                                            Text(
                                              item.location,
                                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.outline),
                                onTap: () {
                                  setState(() {
                                    _foundProduct = {
                                      'partNo': item.partNo,
                                      'description': item.description ?? '',
                                      'location': item.location,
                                      'locationLabel': 'Location: ${item.location}',
                                      'area': 'MAIN WAREHOUSE',
                                      'stock': item.stock,
                                      'multipleLocations': false,
                                    };
                                    _state = _ScanState.found;
                                  });
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      );
  }
}


class _BottomActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BottomActionBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white10,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _SearchChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  const _SearchChip({required this.label, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : Theme.of(context).colorScheme.onSurface)),
      selected: selected,
      onSelected: onSelected,
      selectedColor: AppColors.primary,
      checkmarkColor: Colors.white,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
