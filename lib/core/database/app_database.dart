import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_database.g.dart';

class CurrentUsers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get mongoId => text()();
  TextColumn get employeeId => text()();
  TextColumn get name => text()();
  TextColumn get mobile => text()();
  TextColumn get email => text()();
  TextColumn get role => text()();
  TextColumn get token => text()();
  TextColumn get tokenExpiry => text()();
}

class Inventory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get partNo => text()();
  TextColumn get barcode => text()();
  TextColumn get description => text().nullable()();
  TextColumn get location => text()();
  RealColumn get price => real().withDefault(const Constant(0.0))();
  IntColumn get stock => integer().withDefault(const Constant(0))();
  TextColumn get version => text()();
}

class InventoryMetas extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get currentVersion => text()();
  IntColumn get totalProducts => integer()();
  TextColumn get lastUpdated => text()();
}

class Orders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get mongoId => text().nullable()();
  TextColumn get memoNumber => text()();
  TextColumn get customerName => text().nullable()();
  TextColumn get customerLocation => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get pickerId => text().nullable()();
  TextColumn get checkerId => text().nullable()();
  TextColumn get pickedAt => text().nullable()();
  TextColumn get checkedAt => text().nullable()();
  RealColumn get finalAmount => real().withDefault(const Constant(0.0))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  IntColumn get isSynced => integer().withDefault(const Constant(0))();
}

class OrderItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get mongoId => text().nullable()();
  IntColumn get orderId => integer().references(Orders, #id)();
  TextColumn get partNo => text()();
  TextColumn get description => text().nullable()();
  TextColumn get location => text()();
  IntColumn get requiredQty => integer()();
  IntColumn get pickedQty => integer().withDefault(const Constant(0))();
  IntColumn get checkedQty => integer().withDefault(const Constant(0))();
  RealColumn get unitPrice => real().withDefault(const Constant(0.0))();
  RealColumn get finalPrice => real().withDefault(const Constant(0.0))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get isSynced => integer().withDefault(const Constant(0))();
}

class SyncQueues extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payload => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text()();
  TextColumn get lastTriedAt => text().nullable()();
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [
  CurrentUsers,
  Inventory,
  InventoryMetas,
  Orders,
  OrderItems,
  SyncQueues,
  AppSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 3) {
            // Drop and recreate inventory table to add price and stock columns
            await m.drop(inventory);
            await m.create(inventory);
          }
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'wms.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

// Riverpod Provider
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});
