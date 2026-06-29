import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/app_database.dart';

class QueueService {
  final AppDatabase _db;

  QueueService(this._db);

  /// Queue an entity for offline background sync
  Future<void> queueSync({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    final companion = SyncQueuesCompanion.insert(
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: jsonEncode(payload),
      createdAt: DateTime.now().toIso8601String(),
    );
    await _db.into(_db.syncQueues).insert(companion);
  }
}

final queueServiceProvider = Provider<QueueService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return QueueService(db);
});
