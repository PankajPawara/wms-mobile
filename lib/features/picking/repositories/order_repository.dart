import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/sync/queue_service.dart';

part 'order_repository.g.dart';

class OrderRepository {
  final AppDatabase _db;
  final ApiClient _api;
  final QueueService _queue;

  OrderRepository(this._db, this._api, this._queue);

  /// Fetch all orders locally
  Future<List<Order>> getLocalOrders({String? status, String? search}) async {
    final query = _db.select(_db.orders);
    if (status != null && status.isNotEmpty) {
      query.where((t) => t.status.equals(status));
    }
    if (search != null && search.isNotEmpty) {
      query.where((t) => t.memoNumber.like('%$search%') | t.customerName.like('%$search%'));
    }
    query.orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]);
    return await query.get();
  }

  /// Get local order by SQLite ID
  Future<Order?> getLocalOrderById(int id) async {
    return await (_db.select(_db.orders)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Get local order items for a specific order
  Future<List<OrderItem>> getLocalOrderItems(int orderId) async {
    return await (_db.select(_db.orderItems)..where((t) => t.orderId.equals(orderId))).get();
  }

  /// Update order item pick/check quantities locally and queue for background sync
  Future<void> updateOrderItemQty({
    required int itemId,
    int? pickedQty,
    int? checkedQty,
    String? status,
  }) async {
    final item = await (_db.select(_db.orderItems)..where((t) => t.id.equals(itemId))).getSingleOrNull();
    if (item == null) return;

    final companion = OrderItemsCompanion(
      id: Value(itemId),
      pickedQty: pickedQty != null ? Value(pickedQty) : const Value.absent(),
      checkedQty: checkedQty != null ? Value(checkedQty) : const Value.absent(),
      status: status != null ? Value(status) : const Value.absent(),
      isSynced: const Value(0),
    );

    await _db.update(_db.orderItems).write(companion);

    // Fetch the updated item to get the latest values
    final updated = await (_db.select(_db.orderItems)..where((t) => t.id.equals(itemId))).getSingle();
    final order = await (_db.select(_db.orders)..where((t) => t.id.equals(updated.orderId))).getSingleOrNull();

    // Queue for sync only if it has a server mongo_id
    if (order?.mongoId != null && updated.mongoId != null) {
      await _queue.queueSync(
        entityType: 'order_item',
        entityId: itemId.toString(),
        operation: checkedQty != null ? 'UPDATE_CHECKED' : 'UPDATE_PICKED',
        payload: {
          'mongo_order_id': order!.mongoId,
          'mongo_item_id': updated.mongoId,
          'picked_qty': updated.pickedQty,
          'checked_qty': updated.checkedQty,
          'status': updated.status,
        },
      );
    }
  }

  /// Update order status locally and sync with remote server
  Future<void> updateOrderStatus(int orderId, String status) async {
    final companion = OrdersCompanion(
      id: Value(orderId),
      status: Value(status),
      updatedAt: Value(DateTime.now().toIso8601String()),
      isSynced: const Value(0),
    );
    await _db.update(_db.orders).write(companion);

    final order = await getLocalOrderById(orderId);
    if (order?.mongoId != null) {
      await _queue.queueSync(
        entityType: 'order',
        entityId: orderId.toString(),
        operation: 'UPDATE',
        payload: {
          'mongo_id': order!.mongoId,
          'status': status,
        },
      );
    }
  }

  /// Download orders list from backend and sync to local database
  Future<void> syncOrdersFromServer() async {
    try {
      final response = await _api.get(ApiEndpoints.orders, queryParams: {'limit': 100});
      final data = response['data'] as Map<String, dynamic>?;
      final ordersList = data?['orders'] as List<dynamic>?;

      if (ordersList != null) {
        for (final rawOrder in ordersList) {
          final orderObj = rawOrder as Map<String, dynamic>;
          final mongoId = orderObj['_id'] as String;

          // Check if already exists locally by mongo_id
          final localOrder = await (_db.select(_db.orders)..where((t) => t.mongoId.equals(mongoId))).getSingleOrNull();

          final ordersCompanion = OrdersCompanion.insert(
            mongoId: Value(mongoId),
            memoNumber: orderObj['memo_number'] ?? '',
            customerName: Value(orderObj['customer_name']),
            customerLocation: Value(orderObj['customer_location']),
            status: Value(orderObj['status'] ?? 'draft'),
            pickerId: Value(orderObj['picker_id']?['_id'] ?? orderObj['picker_id']),
            checkerId: Value(orderObj['checker_id']?['_id'] ?? orderObj['checker_id']),
            pickedAt: Value(orderObj['picked_at']),
            checkedAt: Value(orderObj['checked_at']),
            finalAmount: Value(double.parse((orderObj['final_amount'] ?? 0.0).toString())),
            createdAt: orderObj['createdAt'] ?? DateTime.now().toIso8601String(),
            updatedAt: orderObj['updatedAt'] ?? DateTime.now().toIso8601String(),
            isSynced: const Value(1),
          );

          int localId;
          if (localOrder != null) {
            localId = localOrder.id;
            await (_db.update(_db.orders)..where((t) => t.id.equals(localId))).write(ordersCompanion);
          } else {
            localId = await _db.into(_db.orders).insert(ordersCompanion);
          }

          // Fetch items for this order
          final itemsRes = await _api.get('${ApiEndpoints.orders}/$mongoId');
          final itemsData = itemsRes['data']?['items'] as List<dynamic>?;

          if (itemsData != null) {
            for (final rawItem in itemsData) {
              final itemObj = rawItem as Map<String, dynamic>;
              final itemMongoId = itemObj['_id'] as String;

              final localItem = await (_db.select(_db.orderItems)
                    ..where((t) => t.mongoId.equals(itemMongoId)))
                  .getSingleOrNull();

              final itemsCompanion = OrderItemsCompanion.insert(
                mongoId: Value(itemMongoId),
                orderId: localId,
                partNo: itemObj['part_no'] ?? '',
                description: Value(itemObj['description']),
                location: itemObj['location'] ?? '',
                requiredQty: int.parse((itemObj['required_qty'] ?? 0).toString()),
                pickedQty: Value(int.parse((itemObj['picked_qty'] ?? 0).toString())),
                checkedQty: Value(int.parse((itemObj['checked_qty'] ?? 0).toString())),
                unitPrice: Value(double.parse((itemObj['unit_price'] ?? 0.0).toString())),
                finalPrice: Value(double.parse((itemObj['final_price'] ?? 0.0).toString())),
                status: Value(itemObj['status'] ?? 'pending'),
                isSynced: const Value(1),
              );

              if (localItem != null) {
                await (_db.update(_db.orderItems)..where((t) => t.id.equals(localItem.id))).write(itemsCompanion);
              } else {
                await _db.into(_db.orderItems).insert(itemsCompanion);
              }
            }
          }
        }
      }
    } catch (_) {
      // Offline fallback: do nothing, proceed with existing local items
    }
  }

  /// Create local order and queue sync
  Future<int> createLocalOrder({
    required String memoNumber,
    required String customerName,
    required String customerLocation,
    required List<Map<String, dynamic>> items,
  }) async {
    final totalAmount = items.fold<double>(0.0, (sum, i) {
      final qty = double.parse((i['required_qty'] ?? 1).toString());
      final price = double.parse((i['unit_price'] ?? 0.0).toString());
      return sum + (qty * price);
    });

    final orderCompanion = OrdersCompanion.insert(
      memoNumber: memoNumber,
      customerName: Value(customerName),
      customerLocation: Value(customerLocation),
      status: const Value('draft'),
      finalAmount: Value(totalAmount),
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
      isSynced: const Value(0),
    );

    final localId = await _db.into(_db.orders).insert(orderCompanion);

    final List<Map<String, dynamic>> syncItems = [];

    for (final i in items) {
      final partNo = i['part_no'] as String;
      final requiredQty = int.parse((i['required_qty'] ?? 1).toString());
      final unitPrice = double.parse((i['unit_price'] ?? 0.0).toString());
      final description = i['description'] as String?;
      final location = i['location'] as String? ?? 'TEMP-LOC';

      final itemCompanion = OrderItemsCompanion.insert(
        orderId: localId,
        partNo: partNo,
        description: Value(description),
        location: location,
        requiredQty: requiredQty,
        unitPrice: Value(unitPrice),
        finalPrice: Value(requiredQty * unitPrice),
        status: const Value('pending'),
        isSynced: const Value(0),
      );

      await _db.into(_db.orderItems).insert(itemCompanion);

      syncItems.add({
        'part_no': partNo,
        'description': description,
        'location': location,
        'required_qty': requiredQty,
        'unit_price': unitPrice,
      });
    }

    // Queue creation to server
    await _queue.queueSync(
      entityType: 'order',
      entityId: localId.toString(),
      operation: 'CREATE',
      payload: {
        'device_id': 'device_order_$localId',
        'memo_number': memoNumber,
        'customer_name': customerName,
        'customer_location': customerLocation,
        'final_amount': totalAmount,
        'items': syncItems,
      },
    );

    return localId;
  }
}

@riverpod
OrderRepository orderRepository(OrderRepositoryRef ref) {
  return OrderRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(apiClientProvider),
    ref.watch(queueServiceProvider),
  );
}
