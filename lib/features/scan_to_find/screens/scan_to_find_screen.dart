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
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/utils/barcode_util.dart';
import '../../../core/utils/scan_feedback.dart';
import '../../../shared/widgets/advanced_search_bar.dart';

enum _ScanState { scanning, searching, found, notFound, multipleLocations }

class ScanToFindScreen extends ConsumerStatefulWidget {
  final bool initialManualMode;
  final String? initialQuery;
  final String? initialRouteState;
  final Map<String, dynamic>? extraData;

  const ScanToFindScreen({
    super.key,
    this.initialManualMode = false,
    this.initialQuery,
    this.initialRouteState,
    this.extraData,
  });

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

  // _isManualMode is now immutable per instance
  bool get _isManualMode => widget.initialManualMode;
  String _manualSearchQuery = '';
  String _searchByField = 'All Fields';
  String _sortField = 'Part No';
  String _sortOrder = 'Ascending'; // 'Part No', 'Location', 'Description'
  List<InventoryData> _manualSearchResults = [];
  bool _isManualSearching = false;

  String _formatLocation(String? loc) {
    if (loc == null || loc.trim().isEmpty) return 'NN';
    if (loc.trim().toLowerCase() == 'location not defined') return 'NN';
    return loc;
  }


  bool _isDetecting = false;
  Timer? _detectionTimer;
  Timer? _notFoundTimer;

  // Flash and HDR toggles
  FlashMode _flashMode = FlashMode.off;

  // Event channel for light sensor
  static const EventChannel _lightSensorChannel =
      EventChannel('com.example.wms_mobile/light_sensor');
  StreamSubscription<double>? _lightSensorSubscription;

  // Recent searches history
  List<Map<String, dynamic>> _recentQueries = [];

  Future<void> _loadRecentQueries() async {
    try {
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      final jsonStr = await storage.read(key: 'wms_search_history_v2');
      if (jsonStr != null) {
        final List<dynamic> decoded = json.decode(jsonStr);
        if (mounted) {
          setState(() {
            _recentQueries = decoded.map((e) => e as Map<String, dynamic>).toList();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _addRecordToHistory(Map<String, dynamic> record) async {
    if (record['partNo'] == null || record['partNo'].toString().trim().isEmpty) return;
    
    final trimmedPartNo = record['partNo'].toString().trim().toUpperCase();
    record['partNo'] = trimmedPartNo;
    record['timestamp'] = DateTime.now().toIso8601String();

    _recentQueries.removeWhere((r) => r['partNo']?.toString().toUpperCase() == trimmedPartNo);
    _recentQueries.insert(0, record);

    if (_recentQueries.length > 20) {
      _recentQueries = _recentQueries.sublist(0, 20);
    }

    if (mounted) setState(() {});

    try {
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      await storage.write(
          key: 'wms_search_history_v2', value: json.encode(_recentQueries));
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
    if (widget.initialRouteState == 'found') {
      _state = _ScanState.found;
      _foundProduct = widget.extraData?['product'] as Map<String, dynamic>?;
    } else if (widget.initialRouteState == 'not-found') {
      _state = _ScanState.notFound;
      _scannedBarcode = widget.extraData?['query'] ?? '';
    } else if (widget.initialRouteState == 'multiple') {
      _state = _ScanState.multipleLocations;
      _multipleLocationsList = widget.extraData?['products'] as List<InventoryData>? ?? [];
      _scannedBarcode = widget.extraData?['query'] ?? '';
    }

    if (widget.initialQuery != null) {
      _manualController.text = widget.initialQuery!;
      _manualSearchQuery = widget.initialQuery!;
      // Auto-trigger search after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performManualSearch();
      });
    }
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
        if (_flashMode == FlashMode.auto &&
            _state == _ScanState.scanning &&
            !_isManualMode) {
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
    _notFoundTimer?.cancel();
    _pulseController.dispose();
    _scanLineController.dispose();
    _manualController.dispose();
    _manualFocusNode.dispose();
    _detectionTimer?.cancel();
    super.dispose();
  }

  Future<bool> _searchProduct(String rawInput, bool isOcr) async {
    // Prevent concurrent searches - block during searching OR a notFound cooldown
    if (_state == _ScanState.searching) return false;
    if (_state == _ScanState.notFound) return false;

    // ── Parse the input using the centralized PartNumberParser ───────────────
    final parsed = PartNumberParser.parse(rawInput);
    final bestCandidate = parsed.ocrCorrected.isNotEmpty
        ? parsed.ocrCorrected
        : parsed.normalized;

    setState(() {
      _scannedBarcode = bestCandidate.isNotEmpty ? bestCandidate : rawInput;
      _state = _ScanState.searching;
    });

    try {
      final db = ref.read(appDatabaseProvider);
      List<InventoryData> matches = [];
      String matchedQuery = '';
      String matchMethod = '';

      // ── TIER 1: Exact Match ───────────────────────────────────────────────
      for (final candidate in parsed.candidates) {
        if (candidate.isEmpty) continue;
        final results = await (db.select(db.inventory)
              ..where((t) => CustomExpression<bool>(
                  "UPPER(part_no) = '${candidate.replaceAll("'", "''")}' OR UPPER(barcode) = '${candidate.replaceAll("'", "''")}'")))
            .get();
        if (results.isNotEmpty) {
          matches = results;
          matchedQuery = candidate;
          matchMethod = 'exact';
          break;
        }
      }

      // ── TIER 2: Normalized Match (strip all separators, LIKE search) ──────
      if (matches.isEmpty) {
        for (final candidate in parsed.candidates) {
          if (candidate.isEmpty) continue;
          final stripped = candidate.replaceAll(RegExp(r'[-.\s]'), '');
          if (stripped.length < 5) continue;
          final results = await (db.select(db.inventory)
                ..where((t) => CustomExpression<bool>(
                    "REPLACE(REPLACE(UPPER(part_no),'-',''),' ','') LIKE '%$stripped%' OR REPLACE(REPLACE(UPPER(barcode),'-',''),' ','') LIKE '%$stripped%'")))
              .get();
          if (results.isNotEmpty) {
            // Prefer exact stripped match over LIKE
            final exactStripped = results.where((r) {
              final pn =
                  r.partNo.toUpperCase().replaceAll(RegExp(r'[-.\s]'), '');
              return pn == stripped;
            }).toList();
            matches = exactStripped.isNotEmpty ? exactStripped : results;
            matchedQuery = candidate;
            matchMethod = 'normalized';
            break;
          }
        }
      }

      // ── TIER 3: OCR Corrected Match ───────────────────────────────────────
      if (matches.isEmpty) {
        final corrected = parsed.ocrCorrected;
        if (corrected.isNotEmpty) {
          // SQL-level O→0 replacement + LIKE
          final correctedQuery = corrected.replaceAll("'", "''");
          final results = await (db.select(db.inventory)
                ..where((t) => CustomExpression<bool>(
                    "REPLACE(UPPER(part_no),'O','0') LIKE '%${correctedQuery.replaceAll('O', '0')}%' OR REPLACE(UPPER(barcode),'O','0') LIKE '%${correctedQuery.replaceAll('O', '0')}%'")))
              .get();
          if (results.isNotEmpty) {
            matches = results;
            matchedQuery = corrected;
            matchMethod = 'ocr_corrected';
          }
        }
      }

      // ── TIER 4: Fuzzy Candidate Match (BarcodeUtil.findBestMatch) ─────────
      if (matches.isEmpty && isOcr) {
        final allParts = await db.select(db.inventory).get();
        final partNumbersList = allParts.map((e) => e.partNo).toList();
        for (final candidate in parsed.candidates) {
          final bestMatch =
              BarcodeUtil.findBestMatch(candidate, partNumbersList);
          if (bestMatch != null) {
            final results = await (db.select(db.inventory)
                  ..where((t) => t.partNo.equals(bestMatch)))
                .get();
            if (results.isNotEmpty) {
              matches = results;
              matchedQuery = bestMatch;
              matchMethod = 'fuzzy';
              break;
            }
          }
        }
      }

      // ── Filter out sub-matches to prefer the most exact hit ──────────────
      if (matches.length > 1) {
        final mq = matchedQuery.replaceAll(RegExp(r'[-.\s]'), '');
        final exactMatches = matches.where((m) {
          final pn = m.partNo.toUpperCase().replaceAll(RegExp(r'[-.\s]'), '');
          final bc = m.barcode.toUpperCase().replaceAll(RegExp(r'[-.\s]'), '');
          return pn == mq || bc == mq;
        }).toList();
        if (exactMatches.isNotEmpty) matches = exactMatches;
      }

      // ── Handle local DB match ─────────────────────────────────────────────
      if (matches.isNotEmpty) {
        ScanFeedback.triggerSuccess();
        _addRecordToHistory({
          'partNo': matches.first.partNo,
          'description': matches.first.description ?? '',
          'location': _formatLocation(matches.first.location),
          'stock': matches.first.stock,
        });
        if (!mounted) return true;
        if (matches.length == 1) {
          final match = matches.first;
          final product = {
            'partNo': match.partNo,
            'description': match.description ?? '',
            'location': _formatLocation(match.location),
            'locationLabel': 'Location: ',
            'area': 'MAIN WAREHOUSE',
            'multipleLocations': false,
            'matchMethod': matchMethod,
          };
          setState(() => _state = _ScanState.scanning);
          if (mounted) setState(() { _foundProduct = product; _state = _ScanState.found; });
        } else {
          setState(() => _state = _ScanState.scanning);
          if (mounted) setState(() { _multipleLocationsList = matches; _state = _ScanState.multipleLocations; });
        }
        return true;
      }

      // ── API Fallback ──────────────────────────────────────────────────────
      try {
        // To save latency and avoid spamming the backend with OCR false positives,
        // we only perform the API fallback for explicit barcodes.
        if (!isOcr) {
          final api = ref.read(apiClientProvider);
          final queryForApi =
              parsed.ocrCorrected.isNotEmpty ? parsed.ocrCorrected : rawInput;
          final response = await api
              .get(ApiEndpoints.inventoryBarcode(queryForApi))
              .timeout(const Duration(seconds: 5));
          final data = response['data'] as Map<String, dynamic>?;
          final product = data?['product'] as Map<String, dynamic>?;

          if (product != null) {
            ScanFeedback.triggerSuccess();
            _addRecordToHistory({
              'partNo': product['part_no'] ?? '',
              'description': product['description'] ?? '',
              'location': _formatLocation(product['location']),
              'stock': product['stock'] ?? 0,
            });
            if (!mounted) return true;
            final productInfo = {
              'partNo': product['part_no'] ?? '',
              'description': product['description'] ?? '',
              'location': _formatLocation(product['location']),
              'locationLabel': 'Location: ',
              'area': 'MAIN WAREHOUSE',
              'multipleLocations': false,
              'matchMethod': 'api',
            };
            setState(() => _state = _ScanState.scanning);
            if (mounted) setState(() { _foundProduct = productInfo; _state = _ScanState.found; });
            return true;
          }
        }
      } catch (_) {
        // API failed, fall through to not-found handling
      }

      // ── Not Found ─────────────────────────────────────────────────────────
      if (isOcr) {
        // Silently ignore OCR mismatches (likely random text false positives)
        // so the camera keeps scanning smoothly without locking the user out.
        if (mounted) {
          setState(() {
            _scannedBarcode = '';
            _state = _ScanState.scanning;
          });
        }
        return false;
      }

      if (!mounted) return true;
      ScanFeedback.triggerError();
      _showNotFoundInline(bestCandidate.isNotEmpty ? bestCandidate : rawInput);
      return true;
    } catch (e) {
      if (isOcr) {
        if (mounted) {
          setState(() {
            _scannedBarcode = '';
            _state = _ScanState.scanning;
          });
        }
        return false;
      }
      
      if (!mounted) return true;
      ScanFeedback.triggerError();
      _showNotFoundInline(rawInput);
      return true;
    }
  }

  /// Show "not found" inline (no dialog) and auto-reset after 3 seconds.
  void _showNotFoundInline(String scannedCode) {
    _notFoundTimer?.cancel();
    setState(() {
      _scannedBarcode = '';
      _state = _ScanState.scanning;
    });
    setState(() => _state = _ScanState.notFound);
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
    if (widget.initialRouteState != null && context.canPop()) {
      context.pop();
      return;
    }
    setState(() {
      _state = _ScanState.scanning;
      _foundProduct = null;
      _scannedBarcode = '';
    });
  }

  @override
  Widget build(BuildContext context) {

    // If this screen was pushed onto the stack (e.g. from home screen Manual
    // Search button), the system back gesture / button should simply pop it.
    // Only intercept back when it is the shell-tab root (cannot pop).
    final canPop = context.canPop();
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return; // System already popped — nothing to do
        // canPop=false means we're at the shell-tab root (no parent to pop to)
        if (_state != _ScanState.scanning) {
          _scanAnother();
        } else {
          context.go('/home');
        }
      },
      child: Scaffold(
        backgroundColor:
            (_state == _ScanState.scanning || _state == _ScanState.searching) &&
                    !_isManualMode
                ? Colors.black
                : Theme.of(context).colorScheme.surface,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _isManualMode && _state == _ScanState.scanning
              ? _buildManualSearch(canPop)
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
                  top: _isDetecting
                      ? AppDimensions.scannerViewfinderSize - 4
                      : 0,
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
                        icon: const Icon(Icons.hdr_on_rounded,
                            color: Colors.white),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('HDR Auto-enabled'),
                                duration: Duration(seconds: 1)),
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
                            color:
                                _isDetecting ? Colors.grey : AppColors.primary,
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
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.qr_code_scanner_rounded,
                                  color: Colors.white, size: 22),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isDetecting ? 'Scanning' : 'Scan',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  _BottomActionBtn(
                    icon: Icons.keyboard_rounded,
                    label: 'Manual',
                    onTap: () {
                      context.push('/manual-search');
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
          child: Container(width: size, height: thickness, color: color)),
      Positioned(
          top: 0,
          left: 0,
          child: Container(width: thickness, height: size, color: color)),
      Positioned(
          top: 0,
          right: 0,
          child: Container(width: size, height: thickness, color: color)),
      Positioned(
          top: 0,
          right: 0,
          child: Container(width: thickness, height: size, color: color)),
      Positioned(
          bottom: 0,
          left: 0,
          child: Container(width: size, height: thickness, color: color)),
      Positioned(
          bottom: 0,
          left: 0,
          child: Container(width: thickness, height: size, color: color)),
      Positioned(
          bottom: 0,
          right: 0,
          child: Container(width: size, height: thickness, color: color)),
      Positioned(
          bottom: 0,
          right: 0,
          child: Container(width: thickness, height: size, color: color)),
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
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
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
    return Scaffold(
      key: const ValueKey('found'),
      body: Column(
        children: [
          Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                          color: Color(0x0F000000),
                          blurRadius: 8,
                          offset: Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Product No.',
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                      Text(
                        product['partNo'] as String,
                        style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface),
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Text('Description',
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                      Text(
                        product['description'] as String,
                        style: TextStyle(
                            fontSize: 15,
                            color: Theme.of(context).colorScheme.onSurface),
                        maxLines: 3,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Text('Available Stock',
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Location',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)),
                                Text(
                                  product['location'] as String,
                                  style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface),
                                  maxLines: 2,
                                  softWrap: true,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  product['locationLabel'] as String,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                                  maxLines: 2,
                                  softWrap: true,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.warehouse_rounded,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Area',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)),
                                Text(
                                  product['area'] as String,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface),
                                  maxLines: 2,
                                  softWrap: true,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
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
      ),
    );
  }

  Widget _buildNotFound() {
    return Scaffold(
      key: const ValueKey('not_found'),
      body: Column(
        children: [
          Expanded(
            child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search_off_rounded,
                  size: 72, color: AppColors.danger),
              const SizedBox(height: 16),
              const Text(
                'Product Not Found',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  '"$_scannedBarcode" was not found.\nReturning to scanner in 3 seconds…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, color: Colors.black54, height: 1.5),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      _notFoundTimer?.cancel();
                      _scanAnother();
                      _scannerKey.currentState?.restartFeed();
                    },
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Scan Again'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      _notFoundTimer?.cancel();
                      if (_isManualMode) {
                        setState(() { _state = _ScanState.scanning; });
                      } else {
                        context.push('/manual-search', extra: {'initialQuery': _scannedBarcode});
                      }
                    },
                    icon: const Icon(Icons.keyboard_rounded),
                    label: const Text('Search Manually'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultipleLocations() {
    final locations = _multipleLocationsList
        .map((m) => {
              'code': m.location,
              'area': 'MAIN WAREHOUSE',
              'stock': '--',
              'partNo': m.partNo,
            })
        .toList();
    return Scaffold(
      key: const ValueKey('multiple'),
      body: Column(
        children: [
          Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                Text(
                    'Part No:\n${_multipleLocationsList.firstOrNull?.partNo ?? _scannedBarcode}',
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface)),
                              Text('${loc['partNo']}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary)),
                              Text(loc['area'] as String,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
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
                      const SnackBar(
                          content: Text('All locations view coming soon'),
                          duration: Duration(seconds: 1)),
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
      ),
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

    var selectStmt = db.select(db.inventory);
    
    if (_searchByField == 'Location') {
      selectStmt.where((t) => t.location.upper().like('%$query%'));
    } else if (_searchByField == 'Description') {
      selectStmt.where((t) => t.description.upper().like('%$query%'));
    } else if (_searchByField == 'Part No') {
      selectStmt.where((t) => t.partNo.upper().like('%$query%') | t.barcode.like('%$query%'));
    } else {
      selectStmt.where((t) => t.partNo.upper().like('%$query%') | t.barcode.like('%$query%') | t.location.upper().like('%$query%') | t.description.upper().like('%$query%'));
    }
    
    if (_sortField == 'Location') {
      selectStmt.orderBy([(t) => OrderingTerm(expression: t.location, mode: _sortOrder == 'Descending' ? OrderingMode.desc : OrderingMode.asc)]);
    } else {
      selectStmt.orderBy([(t) => OrderingTerm(expression: t.partNo, mode: _sortOrder == 'Descending' ? OrderingMode.desc : OrderingMode.asc)]);
    }
    
    List<InventoryData> results = await selectStmt.get();

    setState(() {
      _manualSearchResults = results;
      _isManualSearching = false;
    });
  }

  Future<void> _triggerCameraScan() async {
    setState(() {
      _isDetecting = true;
    });

    try {
      final image = await _scannerKey.currentState?.takePicture();
      if (image == null) {
        setState(() {
          _isDetecting = false;
        });
        return;
      }

      final inputImage = InputImage.fromFilePath(image.path);

      // Also try barcode scanning on the captured image just in case
      final barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.all]);
      final barcodes = await barcodeScanner.processImage(inputImage);
      await barcodeScanner.close();

      if (barcodes.isNotEmpty) {
        final rawVal = barcodes.first.rawValue;
        if (rawVal != null && rawVal.isNotEmpty) {
          await _searchProduct(rawVal, false);
          return;
        }
      }

      // If no barcode, try OCR
      final textRecognizer = TextRecognizer();
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final partNumbers = BarcodeUtil.extractPartNumbers(recognizedText.text);

      if (partNumbers.isNotEmpty) {
        await _searchProduct(partNumbers.first, true);
      } else {
        // Fallback simple regex
        final reg = RegExp(r'\b\d{8,14}\b');
        final matches = reg.allMatches(recognizedText.text);
        if (matches.isNotEmpty) {
          await _searchProduct(matches.first.group(0)!, true);
        } else {
          _showScanFailedDialog();
        }
      }
    } catch (e) {
      _showScanFailedDialog();
    } finally {
      if (mounted) {
        setState(() {
          _isDetecting = false;
        });
        _scannerKey.currentState?.restartFeed();
      }
    }
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
              context.push('/manual-search');
            },
            child: const Text('Search Manually',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold)),
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
                Text('Analyzing image...',
                    style: TextStyle(fontWeight: FontWeight.w600)),
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

  Widget _buildManualSearch([bool pushedFromOutside = false]) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      key: const ValueKey('manual_search'),
      body: Column(
        children: [
          const SizedBox(height: 16), // A little spacing since we removed the row
          AdvancedSearchBar(
            controller: _manualController,
            focusNode: _manualFocusNode,
            onGoPressed: () {
              _manualFocusNode.unfocus();
            },
            onChanged: (val) {
              _manualSearchQuery = val;
              _performManualSearch();
            },
            onClear: () {
              _manualController.clear();
              setState(() {
                _manualSearchQuery = '';
                _performManualSearch();
              });
              _manualFocusNode.requestFocus();
            },
            searchField: _searchByField,
            onSearchFieldChanged: (val) {
              if (val != null) {
                setState(() => _searchByField = val);
                _performManualSearch();
              }
            },
            sortField: _sortField,
            onSortFieldChanged: (val) {
              if (val != null) {
                setState(() => _sortField = val);
                _performManualSearch();
              }
            },
            sortOrder: _sortOrder,
            onSortOrderChanged: (val) {
              if (val != null) {
                setState(() => _sortOrder = val);
                _performManualSearch();
              }
            },
          ),
          const Divider(height: 1, thickness: 1),
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
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                                ),
                                if (_recentQueries.isNotEmpty)
                                  TextButton(
                                    onPressed: _clearSearchHistory,
                                    child: Text('Clear',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_recentQueries.isEmpty)
                              Text(
                                'No search history yet',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                              )
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _recentQueries.length,
                                itemBuilder: (context, index) {
                                  final query = _recentQueries[index];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    elevation: 1,
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.all(16),
                                      title: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            query['partNo']?.toString() ?? '',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context).colorScheme.onSurface,
                                            ),
                                          ),
                                          if (query['location'] != null && query['location'].toString().isNotEmpty)
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
                                                  Text(
                                                    query['location'].toString(),
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppColors.primary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 8.0),
                                        child: Text(
                                          query['timestamp'] != null 
                                            ? DateFormat('MMM d, yyyy h:mm a').format(DateTime.tryParse(query['timestamp'].toString()) ?? DateTime.now()) 
                                            : '',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      onTap: () {
                                        final productInfo = {
                                          'partNo': query['partNo'] ?? '',
                                          'description': query['description'] ?? '',
                                          'location': _formatLocation(query['location']?.toString()),
                                          'locationLabel': 'Location: ',
                                          'area': 'MAIN WAREHOUSE',
                                          'stock': query['stock'] ?? 0,
                                          'multipleLocations': false,
                                        };
                                        if (mounted) setState(() { _foundProduct = productInfo; _state = _ScanState.found; });
                                      },
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      )
                    : _manualSearchResults.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off_rounded,
                                    size: 48,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant),
                                const SizedBox(height: 12),
                                Text(
                                  'No items found',
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
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
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                elevation: 1,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(16),
                                  title: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Part No',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant)),
                                      Text(
                                        item.partNo,
                                        style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface),
                                      ),
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (item.description != null &&
                                            item.description!.isNotEmpty) ...[
                                          Text(item.description!,
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant),),
                                          const SizedBox(height: 8),
                                        ],
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                  Icons.location_on_rounded,
                                                  color: AppColors.primary,
                                                  size: 16),
                                              const SizedBox(width: 4),
                                              const Text('Location: ',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color:
                                                          AppColors.primary)),
                                              Text(
_formatLocation(item.location),
                                                style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppColors.primary),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  trailing: Icon(Icons.chevron_right_rounded,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline),
                                  onTap: () {
                                    final productInfo = {
                                      'partNo': item.partNo,
                                      'description': item.description ?? '',
                                      'location': _formatLocation(item.location),
                                      'locationLabel': 'Location: ',
                                      'area': 'MAIN WAREHOUSE',
                                      'stock': item.stock,
                                      'multipleLocations': false,
                                    };
                                    _addRecordToHistory(productInfo);
                                    if (mounted) setState(() { _foundProduct = productInfo; _state = _ScanState.found; });
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
  const _BottomActionBtn(
      {required this.icon, required this.label, required this.onTap});

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
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}


