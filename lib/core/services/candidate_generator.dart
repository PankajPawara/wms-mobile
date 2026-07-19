import 'dart:math' as math;
import '../database/app_database.dart';
import '../models/extracted_memo.dart';

class CandidateGenerator {
  final AppDatabase _db;
  List<InventoryData> _cache = [];
  bool _isInitialized = false;

  CandidateGenerator(this._db);

  /// Load all inventory records into memory for fast fuzzy matching.
  /// Typically takes <100ms for ~30k parts.
  Future<void> init() async {
    if (_isInitialized) return;
    _cache = await _db.select(_db.inventory).get();
    _isInitialized = true;
  }

  /// Calculates the Levenshtein distance between two strings.
  /// Returns a similarity score between 0.0 and 1.0 (1.0 = exact match).
  static double _levenshteinSimilarity(String s1, String s2) {
    if (s1.isEmpty && s2.isEmpty) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    s1 = s1.toLowerCase();
    s2 = s2.toLowerCase();

    if (s1 == s2) return 1.0;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        final cost = (s1[i] == s2[j]) ? 0 : 1;
        v1[j + 1] = math.min(
          v1[j] + 1,
          math.min(
            v0[j + 1] + 1,
            v0[j] + cost,
          ),
        );
      }
      for (int j = 0; j < v0.length; j++) {
        v0[j] = v1[j];
      }
    }

    int distance = v1[s2.length];
    int maxLength = math.max(s1.length, s2.length);
    
    return 1.0 - (distance / maxLength);
  }

  /// Normalizes a part number by stripping dashes, spaces, and other common OCR noise chars at boundaries.
  String _normalizePartNo(String partNo) {
    var s = partNo.replaceAll(RegExp(r'[\s\-]'), '');
    while (s.isNotEmpty && (s.startsWith('1') || s.startsWith('|') || s.startsWith('/') || s.startsWith('!'))) {
      s = s.substring(1);
    }
    return s.toUpperCase();
  }

  /// Applies common OCR corrections to a string.
  String _applyOcrCorrection(String input) {
    return input
        .replaceAll(RegExp(r'[0OQD]'), '0')
        .replaceAll(RegExp(r'[1IL|]'), '1')
        .replaceAll('S', '5')
        .replaceAll('G', '6')
        .replaceAll(RegExp(r'[8B3E]'), '8')
        .replaceAll(RegExp(r'[2Z7]'), '2');
  }

  /// Finds the best matching InventoryData for a given raw OCR part number.
  /// Uses a tiered approach: Exact -> Normalized -> Fuzzy.
  Future<ExtractedMemoItem> findBestMatch({
    required String rawPartNo,
    required String description,
    required double mrp,
    required int qty,
    required String location,
    required int pack,
    required int stock,
  }) async {
    if (!_isInitialized) {
      await init();
    }

    if (_cache.isEmpty) {
      // Fallback if DB is empty
      return _buildUnmatchedItem(rawPartNo, description, mrp, qty, location, pack, stock);
    }

    final normalizedRaw = _normalizePartNo(rawPartNo);
    final correctedRaw = _applyOcrCorrection(normalizedRaw);

    InventoryData? bestFuzzyMatch;
    double bestScore = 0.0;

    for (final item in _cache) {
      final dbPartNo = item.partNo;

      // Tier 1: Exact Match (100%)
      if (dbPartNo == rawPartNo) {
        return _buildItem(rawPartNo, rawPartNo, item, MatchConfidence.exact, mrp, qty, pack, description);
      }

      final normalizedDb = _normalizePartNo(dbPartNo);

      // Tier 2: Normalized Match (95%)
      if (normalizedDb == normalizedRaw) {
        return _buildItem(rawPartNo, dbPartNo, item, MatchConfidence.normalized, mrp, qty, pack, description);
      }

      // Tier 3: OCR Corrected Match (85%)
      final correctedDb = _applyOcrCorrection(normalizedDb);
      if (correctedDb == correctedRaw) {
        return _buildItem(rawPartNo, dbPartNo, item, MatchConfidence.fuzzy, mrp, qty, pack, description);
      }

      // Keep track of the best fuzzy match score using Levenshtein distance
      // Compare the normalized strings to ignore dashes
      final score = _levenshteinSimilarity(normalizedDb, normalizedRaw);
      if (score > bestScore) {
        bestScore = score;
        bestFuzzyMatch = item;
      }
    }

    // Tier 4: Best Fuzzy Match (above threshold)
    // 0.8 is typically a good threshold for part numbers (allows ~2 edits on a 10 char string)
    if (bestScore >= 0.80 && bestFuzzyMatch != null) {
      return _buildItem(rawPartNo, bestFuzzyMatch.partNo, bestFuzzyMatch, MatchConfidence.fuzzy, mrp, qty, pack, description);
    }

    // Unmatched
    return _buildUnmatchedItem(rawPartNo, description, mrp, qty, location, pack, stock);
  }

  ExtractedMemoItem _buildItem(
    String rawOcr,
    String corrected,
    InventoryData dbItem,
    MatchConfidence confidence,
    double ocrMrp,
    int qty,
    int pack,
    String ocrDesc,
  ) {
    return ExtractedMemoItem(
      rawOcrPartNo: rawOcr,
      correctedPartNo: corrected,
      confidence: confidence,
      description: dbItem.description?.isNotEmpty == true
          ? dbItem.description!
          : ocrDesc,
      mrp: ocrMrp > 0 ? ocrMrp : dbItem.price,
      qty: qty,
      location: dbItem.location.isNotEmpty ? dbItem.location : 'LOCATION NOT DEFINED',
      pack: pack,
      stock: dbItem.stock,
    );
  }

  ExtractedMemoItem _buildUnmatchedItem(
    String rawPartNo,
    String description,
    double mrp,
    int qty,
    String location,
    int pack,
    int stock,
  ) {
    return ExtractedMemoItem(
      rawOcrPartNo: rawPartNo,
      correctedPartNo: rawPartNo,
      confidence: MatchConfidence.unmatched,
      description: description,
      mrp: mrp,
      qty: qty,
      location: location,
      pack: pack,
      stock: stock,
    );
  }
}
