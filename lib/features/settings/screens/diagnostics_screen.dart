import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column, Table;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/database/app_database.dart';
import '../repositories/inventory_repository.dart';
import '../../picking/repositories/order_repository.dart';

class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  // Sync status states
  String _syncStatus = 'unknown';
  String _syncTime = '--';
  String _syncError = '';
  
  // Database counts states
  int _inventoryCount = 0;
  int _ordersCount = 0;
  int _syncQueueCount = 0;

  // Catalog viewer states
  List<InventoryData> _catalogItems = [];
  int _currentPage = 1;
  int _totalCatalogItems = 0;
  bool _isLoadingCatalog = false;

  // Catalog filter/sort states
  final _searchController = TextEditingController();
  String _searchTerm = '';
  String _searchBy = 'all';
  String _sortBy = 'location';
  String _sortOrder = 'asc';

  @override
  void initState() {
    super.initState();
    _loadSyncAndDiagnosticData();
    _loadLocalCatalog();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSyncAndDiagnosticData() async {
    final db = ref.read(appDatabaseProvider);
    final repo = ref.read(inventoryRepositoryProvider);

    // Read AppSettings
    final settings = await db.select(db.appSettings).get();
    final status = settings.firstWhere((e) => e.key == 'last_sync_status', orElse: () => const AppSetting(key: 'last_sync_status', value: 'unknown')).value;
    final time = settings.firstWhere((e) => e.key == 'last_sync_time', orElse: () => const AppSetting(key: 'last_sync_time', value: '--')).value;
    final error = settings.firstWhere((e) => e.key == 'last_sync_error', orElse: () => const AppSetting(key: 'last_sync_error', value: '')).value;

    // Read DB Counts
    final counts = await repo.getDatabaseSummary();

    if (mounted) {
      setState(() {
        _syncStatus = status;
        _syncTime = time;
        _syncError = error;
        _inventoryCount = counts['inventory'] ?? 0;
        _ordersCount = counts['orders'] ?? 0;
        _syncQueueCount = counts['sync_queue'] ?? 0;
      });
    }
  }

  Future<void> _loadLocalCatalog() async {
    setState(() => _isLoadingCatalog = true);
    final db = ref.read(appDatabaseProvider);

    try {
      Expression<bool> buildFilter(var t) {
        if (_searchTerm.isEmpty) return const Constant(true);
        final pattern = '%$_searchTerm%';
        if (_searchBy == 'part_no') return t.partNo.like(pattern);
        if (_searchBy == 'barcode') return t.barcode.like(pattern);
        if (_searchBy == 'description') return t.description.like(pattern);
        if (_searchBy == 'location') return t.location.like(pattern);
        return t.partNo.like(pattern) | t.barcode.like(pattern) | t.description.like(pattern);
      }

      // Count query
      final countQuery = db.selectOnly(db.inventory)
        ..where(buildFilter(db.inventory))
        ..addColumns([db.inventory.id.count()]);
      final total = (await countQuery.map((row) => row.read(db.inventory.id.count())).getSingle()) ?? 0;

      // Data query
      final dataQuery = db.select(db.inventory)
        ..where((t) => buildFilter(t));

      final sortMode = _sortOrder == 'desc' ? OrderingMode.desc : OrderingMode.asc;
      dataQuery.orderBy([
        (t) {
          if (_sortBy == 'location') return OrderingTerm(expression: t.location, mode: sortMode);
          if (_sortBy == 'barcode') return OrderingTerm(expression: t.barcode, mode: sortMode);
          return OrderingTerm(expression: t.partNo, mode: sortMode);
        }
      ]);

      dataQuery.limit(10, offset: (_currentPage - 1) * 10);
      final items = await dataQuery.get();

      if (mounted) {
        setState(() {
          _catalogItems = items;
          _totalCatalogItems = total;
          _isLoadingCatalog = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _catalogItems = [];
          _totalCatalogItems = 0;
          _isLoadingCatalog = false;
        });
      }
    }
  }

  Future<void> _handleForceSync() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Starting manual synchronization...')),
    );
    final repo = ref.read(inventoryRepositoryProvider);
    final ordersRepo = ref.read(orderRepositoryProvider);
    
    await repo.syncInventory(force: true);
    await ordersRepo.syncOrdersFromServer();

    await _loadSyncAndDiagnosticData();
    await _loadLocalCatalog();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sync execution finished. Status updated!')),
      );
    }
  }

  void _onSearchSubmit() {
    setState(() {
      _searchTerm = _searchController.text.trim();
      _currentPage = 1;
    });
    _loadLocalCatalog();
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _syncStatus == 'success'
        ? AppColors.success
        : (_syncStatus == 'failed' ? AppColors.danger : AppColors.textSecondary);
    final statusLabel = _syncStatus.toUpperCase();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/settings');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          title: const Text('Database & Sync Diagnostics'),
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => context.go('/settings'),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(AppDimensions.md),
          children: [
            // ── SECTION 1: SYNC LOG HEALTH ───────────────────────────────
            _SectionHeader(title: 'SYNC HEALTH LOGS'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Last Sync Status:', style: TextStyle(fontWeight: FontWeight.w600)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Last Execution Time:', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      Text(
                        _syncTime.replaceAll('T', ' ').split('.').first,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  
                  // Render error message block if failed
                  if (_syncStatus == 'failed' && _syncError.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('Error Details:', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxHeight: 140),
                      decoration: BoxDecoration(
                        color: AppColors.dangerLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          _syncError,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _handleForceSync,
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Force Sync Catalog'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── SECTION 2: COUNTS SUMMARY ─────────────────────────────────
            _SectionHeader(title: 'SQLITE STATS'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              ),
              child: Row(
                children: [
                  _CountBadge(label: 'Catalog', count: _inventoryCount, icon: Icons.inventory_2_rounded),
                  _CountBadge(label: 'Sync Queue', count: _syncQueueCount, icon: Icons.cloud_upload_rounded),
                  _CountBadge(label: 'Orders', count: _ordersCount, icon: Icons.receipt_long_rounded),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── SECTION 3: CATALOG VIEWER ──────────────────────────────────
            _SectionHeader(title: 'SQLITE INVENTORY VIEWER (10 PER PAGE)'),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Search & Fields Selector
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search catalog...',
                            hintStyle: const TextStyle(fontSize: 13),
                            prefixIcon: const Icon(Icons.search_rounded, size: 18),
                            isDense: true,
                            contentPadding: const EdgeInsets.all(10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          onSubmitted: (_) => _onSearchSubmit(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _onSearchSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        child: const Text('Go', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  
                  // Dropdown filters
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // Search By
                        _DropdownSelector<String>(
                          label: 'Search Field',
                          value: _searchBy,
                          items: const {
                            'all': 'All Fields',
                            'part_no': 'Part No',
                            'barcode': 'Barcode',
                            'description': 'Description',
                            'location': 'Location',
                          },
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _searchBy = val;
                                _currentPage = 1;
                              });
                              _loadLocalCatalog();
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        
                        // Sort By
                        _DropdownSelector<String>(
                          label: 'Sort Field',
                          value: _sortBy,
                          items: const {
                            'part_no': 'Part No',
                            'location': 'Location',
                            'barcode': 'Barcode',
                          },
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _sortBy = val;
                                _currentPage = 1;
                              });
                              _loadLocalCatalog();
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        
                        // Sort Order
                        _DropdownSelector<String>(
                          label: 'Order',
                          value: _sortOrder,
                          items: const {
                            'asc': 'Ascending',
                            'desc': 'Descending',
                          },
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _sortOrder = val;
                                _currentPage = 1;
                              });
                              _loadLocalCatalog();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),

                  // Catalog Items List
                  if (_isLoadingCatalog) ...[
                    const SizedBox(
                      height: 150,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ] else if (_catalogItems.isEmpty) ...[
                    const SizedBox(
                      height: 150,
                      child: Center(
                        child: Text(
                          'No inventory parts found matching criteria.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ),
                    ),
                  ] else ...[
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _catalogItems.length,
                      separatorBuilder: (_, __) => const Divider(height: 12),
                      itemBuilder: (context, index) {
                        final item = _catalogItems[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    item.partNo,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryLight,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.location,
                                      style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              if (item.description != null && item.description!.isNotEmpty)
                                Text(
                                  item.description!,
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              Text(
                                'Barcode: ${item.barcode}',
                                style: const TextStyle(color: Colors.grey, fontSize: 11),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Pagination Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton(
                          onPressed: _currentPage > 1
                              ? () {
                                  setState(() => _currentPage--);
                                  _loadLocalCatalog();
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.textPrimary,
                            elevation: 0,
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: const Text('Previous'),
                        ),
                        Text(
                          'Page $_currentPage of ${((_totalCatalogItems - 1) / 10).floor() + 1}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                        ),
                        ElevatedButton(
                          onPressed: _currentPage * 10 < _totalCatalogItems
                              ? () {
                                  setState(() => _currentPage++);
                                  _loadLocalCatalog();
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.textPrimary,
                            elevation: 0,
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: const Text('Next'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;

  const _CountBadge({
    required this.label,
    required this.count,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(height: 6),
          Text(
            count.toString(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DropdownSelector<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;

  const _DropdownSelector({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.shade300),
            color: Colors.white,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
              items: items.entries.map((e) {
                return DropdownMenuItem<T>(
                  value: e.key,
                  child: Text(e.value),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
