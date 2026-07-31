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
  IntColumn get id =>
      integer().autoIncrement()();
  TextColumn get mongoId => text().nullable()();
  TextColumn get memoNumber => text()();
  TextColumn get customerName => text().nullable()();
  TextColumn get customerLocation => text().nullable()();
  /// ISO-8601 date string parsed from the physical memo (e.g. "2024-06-15").
  /// Stored separately from createdAt (which is when the order was created in the app).
  TextColumn get memoDate => text().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant('draft'))();
  TextColumn get pickerId => text().nullable()();
  TextColumn get checkerId => text().nullable()();
  TextColumn get pickedAt => text().nullable()();
  TextColumn get checkedAt => text().nullable()();
  RealColumn get finalAmount =>
      real().withDefault(const Constant(0.0))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  IntColumn get isSynced =>
      integer().withDefault(const Constant(0))();
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

/// Self-learning parts master — built from memo scans + red label scans.
/// Acts as the primary lookup cache, superseding the Inventory table for known parts.
class PartsMaster extends Table {
  /// Normalized Honda part number with dashes (e.g. "33610-KSP-860").
  TextColumn get partNo      => text()();
  /// Raw barcode string from QR scan, no dashes (e.g. "33610KSP860").
  TextColumn get barcode     => text().nullable()();
  /// Authoritative product description. Red label overrides OCR.
  TextColumn get description => text().nullable()();
  /// Warehouse shelf location (e.g. "029G").
  TextColumn get location    => text().nullable()();
  /// Latest MRP including all taxes (always overwritten with newest value).
  RealColumn get mrp         => real().withDefault(const Constant(0.0))();
  /// Pack quantity per unit (from memo PACK column).
  IntColumn  get packQty     => integer().withDefault(const Constant(1))();
  /// Actual warehouse stock quantity (from memo STOCK column).
  IntColumn  get stockQty    => integer().withDefault(const Constant(0))();
  /// Manufacturing month string (e.g. "MAY") — from red label.
  TextColumn get mfgMonth    => text().nullable()();
  /// Manufacturing year string (e.g. "2026") — from red label.
  TextColumn get mfgYear     => text().nullable()();
  /// Source of last update: "memo_scan" | "red_label" | "manual".
  TextColumn get source      => text().withDefault(const Constant('memo_scan'))();
  /// ISO-8601 timestamp of last time this part appeared in any scan.
  TextColumn get lastSeenAt  => text()();
  /// ISO-8601 timestamp when first added to the local DB.
  TextColumn get createdAt   => text()();

  @override
  Set<Column> get primaryKey => {partNo};
}

@DriftDatabase(tables: [
  CurrentUsers,
  Inventory,
  InventoryMetas,
  Orders,
  OrderItems,
  SyncQueues,
  AppSettings,
  PartsMaster,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 3) {
            // v3: Drop and recreate inventory table to add price and stock columns
            await m.drop(inventory);
            await m.create(inventory);
          }
          if (from < 4) {
            // v4: Add memoDate column to orders table (ADD COLUMN preserves existing rows)
            await m.addColumn(orders, orders.memoDate);
          }
          if (from < 5) {
            // v5: Add PartsMaster table — self-learning parts DB from memo + red label scans
            await m.create(partsMaster);
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
