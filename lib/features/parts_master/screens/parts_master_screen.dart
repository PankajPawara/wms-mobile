import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/parts_master_service.dart';
import '../../../features/auth/providers/auth_provider.dart';

/// Parts Master browser screen.
///
/// All authenticated users can VIEW. Only admin / stock_manager can EDIT.
/// Source badges: 🟢 Memo Scan | 🔵 Red Label | ✏️ Manual
class PartsMasterScreen extends ConsumerStatefulWidget {
  const PartsMasterScreen({super.key});

  @override
  ConsumerState<PartsMasterScreen> createState() => _PartsMasterScreenState();
}

class _PartsMasterScreenState extends ConsumerState<PartsMasterScreen> {
  late final PartsMasterService _service;
  final TextEditingController _searchCtrl = TextEditingController();

  List<PartsMasterData> _allItems = [];
  List<PartsMasterData> _filtered = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final db = ref.read(appDatabaseProvider);
    _service = PartsMasterService(db);
    _load();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_applyFilter);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final items = await _service.getAll();
    if (mounted) {
      setState(() {
        _allItems = items;
        _filtered = items;
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _allItems
          : _allItems.where((p) {
              return (p.partNo.toLowerCase().contains(q)) ||
                  (p.description?.toLowerCase().contains(q) ?? false) ||
                  (p.location?.toLowerCase().contains(q) ?? false);
            }).toList();
    });
  }

  // ---------------------------------------------------------------------------
  // Edit bottom sheet — only for admin / stock_manager
  // ---------------------------------------------------------------------------
  void _showEditSheet(PartsMasterData part) {
    final descCtrl = TextEditingController(text: part.description ?? '');
    final locCtrl  = TextEditingController(text: part.location ?? '');
    final mrpCtrl  = TextEditingController(
        text: part.mrp > 0 ? part.mrp.toStringAsFixed(2) : '');
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20, 20, 20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Edit — ${part.partNo}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              _editField(descCtrl, 'Description', Icons.label_outline),
              const SizedBox(height: 12),
              _editField(locCtrl, 'Location', Icons.location_on_outlined),
              const SizedBox(height: 12),
              _editField(mrpCtrl, 'MRP (₹)', Icons.currency_rupee,
                  keyboardType: TextInputType.number),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setSheet(() => saving = true);
                          await _service.manualUpdate(
                            partNo:      part.partNo,
                            description: descCtrl.text.trim().isNotEmpty
                                ? descCtrl.text.trim() : null,
                            location:    locCtrl.text.trim().isNotEmpty
                                ? locCtrl.text.trim() : null,
                            mrp: double.tryParse(mrpCtrl.text.trim()),
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _load();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editField(TextEditingController ctrl, String label, IconData icon,
      {TextInputType keyboardType = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: AppColors.primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final canEdit = authState.user?.canManagePartsMaster ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Search bar
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(
                AppDimensions.md, AppDimensions.sm,
                AppDimensions.md, AppDimensions.md),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search by part no, description or location…',
                prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _applyFilter();
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppDimensions.radiusMd),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          // Stats bar
          if (!_isLoading)
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Text(
                    '${_filtered.length} of ${_allItems.length} parts',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const Spacer(),
                  if (canEdit)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '✏️ Edit enabled',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),

          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 64, color: AppColors.textDisabled),
                            const SizedBox(height: 12),
                            Text(
                              _allItems.isEmpty
                                  ? 'No parts yet.\nScan a memo to start building the DB.'
                                  : 'No results for "${_searchCtrl.text}"',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(AppDimensions.md),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppDimensions.sm),
                          itemBuilder: (_, i) =>
                              _PartCard(
                            part: _filtered[i],
                            canEdit: canEdit,
                            onEdit: () => _showEditSheet(_filtered[i]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual part card widget
// ---------------------------------------------------------------------------
class _PartCard extends StatelessWidget {
  final PartsMasterData part;
  final bool canEdit;
  final VoidCallback onEdit;

  const _PartCard({
    required this.part,
    required this.canEdit,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: part no + source badge + edit button
          Row(
            children: [
              Expanded(
                child: Text(
                  part.partNo,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.primary,
                  ),
                ),
              ),
              _SourceBadge(source: part.source),
              if (canEdit) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onEdit,
                  child: const Icon(Icons.edit_outlined,
                      size: 18, color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),

          // Description
          Text(
            part.description ?? '—',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),

          const SizedBox(height: 8),

          // Details row
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (part.location?.isNotEmpty == true)
                _chip(Icons.location_on_outlined, part.location!),
              _chip(Icons.currency_rupee,
                  part.mrp > 0 ? part.mrp.toStringAsFixed(2) : '—'),
              _chip(Icons.inventory_2_outlined, 'Stock: ${part.stockQty}'),
              if (part.mfgMonth?.isNotEmpty == true &&
                  part.mfgYear?.isNotEmpty == true)
                _chip(Icons.calendar_month_outlined,
                    '${part.mfgMonth} ${part.mfgYear}'),
            ],
          ),

          // Last seen
          const SizedBox(height: 6),
          Text(
            'Last updated: ${_formatDate(part.lastSeenAt)}',
            style: TextStyle(color: AppColors.textDisabled, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 3),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day}/${d.month}/${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

// ---------------------------------------------------------------------------
// Source badge widget
// ---------------------------------------------------------------------------
class _SourceBadge extends StatelessWidget {
  final String source;
  const _SourceBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (source) {
      'red_label' => ('🔵 Red Label', AppColors.info),
      'manual'    => ('✏️ Manual',    AppColors.warning),
      _           => ('🟢 Memo',      AppColors.success),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
