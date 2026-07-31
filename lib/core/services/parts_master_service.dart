import 'package:drift/drift.dart';
import '../database/app_database.dart';

/// Service for the self-learning Parts Master database.
///
/// Priority rules:
///   - MRP:         Always overwrite with latest value (no history).
///   - Location:    Always overwrite with latest (memo is ground truth).
///   - Stock:       Always overwrite with latest (memo STOCK = actual qty).
///   - Description: Write only if currently null/empty (OCR); red label always overrides.
///   - Mfg Date:    Only written by red label scans, never by memo scans.
class PartsMasterService {
  final AppDatabase _db;

  PartsMasterService(this._db);

  // ---------------------------------------------------------------------------
  // Normalize a raw Honda part number to canonical dash format.
  //   "33610KSP860"    -> "33610-KSP-860"
  //   "64304K0PD00ZZ"  -> "64304-K0P-D00ZZ"
  //   "14680-K0N-D01"  -> "14680-K0N-D01" (already normalized, pass-through)
  // ---------------------------------------------------------------------------
  static String normalizePart(String raw) {
    final s = raw.replaceAll('-', '').trim().toUpperCase();
    if (s.length < 8) return raw.toUpperCase(); // too short to normalize
    final prefix = s.substring(0, 5);
    final mid    = s.substring(5, 8);
    final suffix = s.substring(8);
    return '$prefix-$mid-$suffix';
  }

  // ---------------------------------------------------------------------------
  // Look up a part by raw part number (with or without dashes).
  // Returns null if not yet in the Parts Master.
  // ---------------------------------------------------------------------------
  Future<PartsMasterData?> lookup(String rawPartNo) async {
    final normalized = normalizePart(rawPartNo);
    final query = _db.select(_db.partsMaster)
      ..where((t) => t.partNo.equals(normalized));
    return query.getSingleOrNull();
  }

  // ---------------------------------------------------------------------------
  // Learn from a memo scan row. Called after every successful pipeline run.
  //   - Always updates: mrp, location, stockQty, packQty, lastSeenAt
  //   - Conditionally updates: description (only if currently null/empty)
  //   - Never updates: mfgMonth, mfgYear (memo does not have these)
  // ---------------------------------------------------------------------------
  Future<void> learnFromMemo({
    required String rawPartNo,
    required String description,
    required String location,
    required double mrp,
    required int packQty,
    required int stockQty,
  }) async {
    if (rawPartNo.trim().isEmpty) return;

    final normalized = normalizePart(rawPartNo);
    final now = DateTime.now().toIso8601String();
    final existing = await lookup(rawPartNo);

    if (existing == null) {
      await _db.into(_db.partsMaster).insertOnConflictUpdate(
        PartsMasterCompanion.insert(
          partNo:      normalized,
          barcode:     Value(rawPartNo.replaceAll('-', '')),
          description: Value(description.isNotEmpty ? description : null),
          location:    Value(location.isNotEmpty ? location : null),
          mrp:         Value(mrp),
          packQty:     Value(packQty > 0 ? packQty : 1),
          stockQty:    Value(stockQty),
          source:      const Value('memo_scan'),
          lastSeenAt:  now,
          createdAt:   now,
        ),
      );
    } else {
      await (_db.update(_db.partsMaster)
            ..where((t) => t.partNo.equals(normalized)))
          .write(PartsMasterCompanion(
        mrp:        Value(mrp > 0 ? mrp : existing.mrp),
        location:   Value(location.isNotEmpty ? location : (existing.location ?? '')),
        stockQty:   Value(stockQty),
        packQty:    Value(packQty > 0 ? packQty : existing.packQty),
        source:     const Value('memo_scan'),
        lastSeenAt: Value(now),
        // Only write description if currently missing
        description: Value(
          (existing.description == null || existing.description!.isEmpty)
              ? (description.isNotEmpty ? description : null)
              : existing.description,
        ),
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Learn from a red label scan. Authoritative — always overrides description + mrp.
  //   - Always updates: description, mrp, mfgMonth, mfgYear, barcode, lastSeenAt
  // ---------------------------------------------------------------------------
  Future<void> learnFromRedLabel({
    required String rawBarcode,
    required String description,
    required double mrp,
    required int qty,
    required String mfgMonth,
    required String mfgYear,
  }) async {
    if (rawBarcode.trim().isEmpty) return;

    final normalized = normalizePart(rawBarcode);
    final now = DateTime.now().toIso8601String();
    final existing = await lookup(rawBarcode);

    if (existing == null) {
      await _db.into(_db.partsMaster).insertOnConflictUpdate(
        PartsMasterCompanion.insert(
          partNo:      normalized,
          barcode:     Value(rawBarcode.replaceAll('-', '')),
          description: Value(description.isNotEmpty ? description : null),
          mrp:         Value(mrp),
          mfgMonth:    Value(mfgMonth.isNotEmpty ? mfgMonth : null),
          mfgYear:     Value(mfgYear.isNotEmpty ? mfgYear : null),
          packQty:     Value(qty > 0 ? qty : 1),
          source:      const Value('red_label'),
          lastSeenAt:  now,
          createdAt:   now,
        ),
      );
    } else {
      await (_db.update(_db.partsMaster)
            ..where((t) => t.partNo.equals(normalized)))
          .write(PartsMasterCompanion(
        barcode:     Value(rawBarcode.replaceAll('-', '')),
        description: Value(description.isNotEmpty ? description : existing.description),
        mrp:         Value(mrp > 0 ? mrp : existing.mrp),
        mfgMonth:    Value(mfgMonth.isNotEmpty ? mfgMonth : existing.mfgMonth),
        mfgYear:     Value(mfgYear.isNotEmpty ? mfgYear : existing.mfgYear),
        source:      const Value('red_label'),
        lastSeenAt:  Value(now),
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Manual edit — only admin / stock_manager. Caller must verify role.
  // ---------------------------------------------------------------------------
  Future<void> manualUpdate({
    required String partNo,
    String? description,
    String? location,
    double? mrp,
  }) async {
    final normalized = normalizePart(partNo);
    final now = DateTime.now().toIso8601String();

    await (_db.update(_db.partsMaster)
          ..where((t) => t.partNo.equals(normalized)))
        .write(PartsMasterCompanion(
      description: description != null ? Value(description) : const Value.absent(),
      location:    location    != null ? Value(location)    : const Value.absent(),
      mrp:         mrp         != null ? Value(mrp)         : const Value.absent(),
      source:      const Value('manual'),
      lastSeenAt:  Value(now),
    ));
  }

  // ---------------------------------------------------------------------------
  // Get all records sorted by most recently seen.
  // ---------------------------------------------------------------------------
  Future<List<PartsMasterData>> getAll() {
    return (_db.select(_db.partsMaster)
          ..orderBy([(t) => OrderingTerm(
                expression: t.lastSeenAt, mode: OrderingMode.desc)]))
        .get();
  }

  // ---------------------------------------------------------------------------
  // Search by part number or description (case-insensitive, max 50 results).
  // ---------------------------------------------------------------------------
  Future<List<PartsMasterData>> search(String query) {
    final q = '%${query.toLowerCase()}%';
    return (_db.select(_db.partsMaster)
          ..where((t) =>
              t.partNo.lower().like(q) | t.description.lower().like(q))
          ..limit(50))
        .get();
  }

  // ---------------------------------------------------------------------------
  // Build MongoDB sync payload for a list of parts.
  // Called at: picker submit + checker submit for billing.
  // ---------------------------------------------------------------------------
  List<Map<String, dynamic>> toSyncPayload(List<PartsMasterData> items) {
    return items.map((p) => {
      'partNo':      p.partNo,
      'barcode':     p.barcode,
      'description': p.description,
      'location':    p.location,
      'mrp':         p.mrp,
      'packQty':     p.packQty,
      'stockQty':    p.stockQty,
      'mfgMonth':    p.mfgMonth,
      'mfgYear':     p.mfgYear,
      'source':      p.source,
      'lastSeenAt':  p.lastSeenAt,
    }).toList();
  }
}
