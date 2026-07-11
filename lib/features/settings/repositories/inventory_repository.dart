import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

part 'inventory_repository.g.dart';

enum InventoryUpdateStatus {
  needsInitialSync,
  updateAvailable,
  upToDate,
  error,
}

class InventoryRepository {
  final AppDatabase _db;
  final ApiClient _api;

  InventoryRepository(this._db, this._api);

  Future<InventoryUpdateStatus> checkUpdateStatus() async {
    try {
      final res = await _api.get(ApiEndpoints.inventoryVersion);
      final data = res['data'] as Map<String, dynamic>?;
      if (data == null) return InventoryUpdateStatus.error;

      final serverVersion = data['version'] as String? ?? 'v0';
      final localMeta = await _db.select(_db.inventoryMetas).getSingleOrNull();

      if (localMeta == null) {
        return InventoryUpdateStatus.needsInitialSync;
      } else if (localMeta.currentVersion != serverVersion) {
        return InventoryUpdateStatus.updateAvailable;
      } else {
        return InventoryUpdateStatus.upToDate;
      }
    } catch (_) {
      return InventoryUpdateStatus.error;
    }
  }

  /// Run check and sync inventory version
  Future<bool> syncInventory({bool force = false, bool skipCheck = false}) async {
    try {
      String serverVersion = 'v0';
      int totalProducts = 0;

      if (!skipCheck) {
        // 1. Fetch current server version
        final res = await _api.get(ApiEndpoints.inventoryVersion);
        final data = res['data'] as Map<String, dynamic>?;
        if (data == null) return false;

        serverVersion = data['version'] as String? ?? 'v0';
        totalProducts = int.parse((data['total_products'] ?? 0).toString());

        // 2. Fetch local meta
        final localMeta = await _db.select(_db.inventoryMetas).getSingleOrNull();

        if (!force && localMeta != null && localMeta.currentVersion == serverVersion) {
          // Already up to date
          return false;
        }
      }

      // 3. Download full inventory
      final downloadRes = await _api.get(ApiEndpoints.inventoryDownload);
      final downloadData = downloadRes['data'] as Map<String, dynamic>?;
      final items = downloadData?['items'] as List<dynamic>?;

      if (items != null) {
        // If skipCheck is true, we didn't fetch the version above, so we extract it from the payload if possible
        if (skipCheck) {
          serverVersion = downloadData?['version'] ?? 'v0';
          totalProducts = items.length;
        }

        // Drop local inventory
        await _db.delete(_db.inventory).go();

        // Batch insert items
        await _db.batch((batch) {
          for (final rawItem in items) {
            final item = rawItem as Map<String, dynamic>;
            batch.insert(
              _db.inventory,
              InventoryCompanion.insert(
                partNo: item['part_no'] ?? '',
                barcode: item['barcode'] ?? '',
                description: Value(item['description']),
                location: item['location'] ?? '',
                price: Value(double.tryParse(item['price']?.toString() ?? '') ?? 0.0),
                stock: Value(int.tryParse(item['stock']?.toString() ?? '') ?? 0),
                version: serverVersion,
              ),
              mode: InsertMode.insertOrReplace,
            );
          }
        });

        // Update local meta
        await _db.delete(_db.inventoryMetas).go();
        await _db.into(_db.inventoryMetas).insert(
          InventoryMetasCompanion.insert(
            currentVersion: serverVersion,
            totalProducts: totalProducts,
            lastUpdated: DateTime.now().toIso8601String(),
          ),
        );

        // Record success sync status
        await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: 'last_sync_status',
            value: 'success',
          ),
        );
        await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: 'last_sync_time',
            value: DateTime.now().toIso8601String(),
          ),
        );
        await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: 'last_sync_error',
            value: '',
          ),
        );
        return true;
      }
    } catch (e) {
      // Record failed sync status
      try {
        await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: 'last_sync_status',
            value: 'failed',
          ),
        );
        await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: 'last_sync_time',
            value: DateTime.now().toIso8601String(),
          ),
        );
        await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: 'last_sync_error',
            value: e.toString(),
          ),
        );
      } catch (_) {}
    }
    return false;
  }

  /// Get database record counts for diagnostic summary
  Future<Map<String, int>> getDatabaseSummary() async {
    final inventoryCountObj = _db.inventory.id.count();
    final ordersCountObj = _db.orders.id.count();
    final syncCountObj = _db.syncQueues.id.count();

    final queryInv = _db.selectOnly(_db.inventory)..addColumns([inventoryCountObj]);
    final queryOrd = _db.selectOnly(_db.orders)..addColumns([ordersCountObj]);
    final querySync = _db.selectOnly(_db.syncQueues)..addColumns([syncCountObj]);

    final invResult = await queryInv.map((row) => row.read(inventoryCountObj)).getSingle();
    final ordResult = await queryOrd.map((row) => row.read(ordersCountObj)).getSingle();
    final syncResult = await querySync.map((row) => row.read(syncCountObj)).getSingle();

    return {
      'inventory': invResult ?? 0,
      'orders': ordResult ?? 0,
      'sync_queue': syncResult ?? 0,
    };
  }

  Future<List<String>> getAllPartNumbers() async {
    final query = _db.selectOnly(_db.inventory)..addColumns([_db.inventory.partNo]);
    final result = await query.map((row) => row.read(_db.inventory.partNo)).get();
    return result.where((e) => e != null).cast<String>().toList();
  }

  Future<Map<String, String>> getAllPartLocations() async {
    final query = _db.selectOnly(_db.inventory)..addColumns([_db.inventory.partNo, _db.inventory.location]);
    final result = await query.map((row) {
      return MapEntry(
        row.read(_db.inventory.partNo) ?? '',
        row.read(_db.inventory.location) ?? ''
      );
    }).get();
    
    return Map.fromEntries(result.where((e) => e.key.isNotEmpty));
  }

  Future<List<dynamic>> searchByPartNo(String query) async {
    final results = await (_db.select(_db.inventory)..where((t) => t.partNo.equals(query))).get();
    return results; // Returns List<InventoryData> which has .location property
  }
}

@riverpod
InventoryRepository inventoryRepository(InventoryRepositoryRef ref) {
  return InventoryRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(apiClientProvider),
  );
}
