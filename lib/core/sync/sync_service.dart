import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../database/app_database.dart';
import '../network/api_client.dart';
import '../network/api_endpoints.dart';

class SyncService {
  final AppDatabase _db;
  final ApiClient _api;
  bool _isSyncing = false;

  SyncService(this._db, this._api);

  bool get isSyncing => _isSyncing;

  /// Run background synchronisation for all pending items in the queue
  Future<void> runSync() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        _isSyncing = false;
        return;
      }

      final pendingItems = await (_db.select(_db.syncQueues)
            ..where((t) => t.status.equals('pending'))
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .get();

      if (pendingItems.isEmpty) {
        _isSyncing = false;
        return;
      }

      for (final item in pendingItems) {
        try {
          await _processQueueItem(item);
        } catch (e) {
          final retryCount = item.retryCount + 1;
          final newStatus = retryCount >= 10 ? 'failed' : 'pending';
          
          await (_db.update(_db.syncQueues)..where((t) => t.id.equals(item.id)))
              .write(SyncQueuesCompanion(
            retryCount: Value(retryCount),
            status: Value(newStatus),
            lastTriedAt: Value(DateTime.now().toIso8601String()),
          ));
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _processQueueItem(SyncQueue item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;

    if (item.entityType == 'order') {
      if (item.operation == 'CREATE') {
        final response = await _api.post(ApiEndpoints.orders, data: payload);
        final data = response['data'] as Map<String, dynamic>?;
        final orderObj = data?['order'] as Map<String, dynamic>?;
        final itemsList = data?['items'] as List<dynamic>?;
        
        final mongoId = orderObj?['_id'] as String?;
        if (mongoId != null) {
          final localOrderId = int.parse(item.entityId);
          await (_db.update(_db.orders)..where((t) => t.id.equals(localOrderId)))
              .write(OrdersCompanion(
            mongoId: Value(mongoId),
            isSynced: const Value(1),
          ));

          if (itemsList != null) {
            for (final rawItem in itemsList) {
              final itemObj = rawItem as Map<String, dynamic>;
              final localPartNo = itemObj['part_no'] as String;
              final itemMongoId = itemObj['_id'] as String;
              
              await (_db.update(_db.orderItems)
                    ..where((t) => t.orderId.equals(localOrderId) & t.partNo.equals(localPartNo)))
                  .write(OrderItemsCompanion(
                mongoId: Value(itemMongoId),
                isSynced: const Value(1),
              ));
            }
          }
        }
      } else if (item.operation == 'UPDATE') {
        final mongoId = payload['mongo_id'] as String?;
        final status = payload['status'] as String?;
        if (mongoId != null && status != null) {
          await _api.patch(ApiEndpoints.orderStatus(mongoId), data: {'status': status});
          final localOrderId = int.parse(item.entityId);
          await (_db.update(_db.orders)..where((t) => t.id.equals(localOrderId)))
              .write(const OrdersCompanion(isSynced: Value(1)));
        }
      }
    } else if (item.entityType == 'order_item') {
      if (item.operation == 'UPDATE_PICKED' || item.operation == 'UPDATE_CHECKED') {
        final mongoOrderId = payload['mongo_order_id'] as String?;
        final mongoItemId = payload['mongo_item_id'] as String?;
        if (mongoOrderId != null && mongoItemId != null) {
          await _api.patch(
            ApiEndpoints.orderItem(mongoOrderId, mongoItemId),
            data: {
              'picked_qty': payload['picked_qty'],
              'checked_qty': payload['checked_qty'],
              'status': payload['status'],
            },
          );
          final localItemId = int.parse(item.entityId);
          await (_db.update(_db.orderItems)..where((t) => t.id.equals(localItemId)))
              .write(const OrderItemsCompanion(isSynced: Value(1)));
        }
      }
    }

    await (_db.delete(_db.syncQueues)..where((t) => t.id.equals(item.id))).go();
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final api = ref.watch(apiClientProvider);
  return SyncService(db, api);
});
