import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:drift/drift.dart' hide Column;

import '../database/app_database.dart';
import '../models/extracted_memo.dart';

// =============================================================================
// MEMO OCR ENGINE
// Coordinate-aware pipeline for extracting pickup list data from memo images.
//
// Pipeline:
//   1. ML Kit OCR → words with bounding boxes
//   2. Row reconstruction by Y-proximity
//   3. Column detection by header word X-positions
//   4. Per-row field extraction
//   5. DB-first part number validation with confidence scoring
// =============================================================================

/// A single OCR word with its position.
class OcrWord {
  final String text;
  final int left;
  final int top;
  final int right;
  final int bottom;

  const OcrWord({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  int get midX => (left + right) ~/ 2;
  int get midY => (top + bottom) ~/ 2;
  int get height => bottom - top;
}

/// A group of OcrWords on the same row (similar Y coordinate).
class OcrRow {
  final List<OcrWord> words;
  final int approximateY;

  const OcrRow({required this.words, required this.approximateY});

  /// Full text of the row, words joined by spaces.
  String get fullText => words.map((w) => w.text).join(' ');

  /// True if row appears to be a table header (contains known column headers).
  bool get isHeaderRow {
    final upper = fullText.toUpperCase();
    return upper.contains('PART') ||
        upper.contains('MRP') ||
        upper.contains('QTY') ||
        upper.contains('LOCATION') ||
        upper.contains('STOCK');
  }
}

/// X-boundaries for each column derived from the header row.
class ColumnLayout {
  final int srEnd;         // x < srEnd → SR No
  final int partNoEnd;     // x < partNoEnd → Part No
  final int descEnd;       // x < descEnd → Description
  final int mrpEnd;        // x < mrpEnd → MRP
  final int qtyEnd;        // x < qtyEnd → Qty
  final int locationEnd;   // x < locationEnd → Location
  final int packEnd;       // x < packEnd → Pack
  // remainder → Stock

  const ColumnLayout({
    required this.srEnd,
    required this.partNoEnd,
    required this.descEnd,
    required this.mrpEnd,
    required this.qtyEnd,
    required this.locationEnd,
    required this.packEnd,
  });

  /// Default layout if no header row is detected.
  /// Based on typical FAS Software memo proportions.
  static const defaultLayout = ColumnLayout(
    srEnd: 60,
    partNoEnd: 280,
    descEnd: 560,
    mrpEnd: 700,
    qtyEnd: 760,
    locationEnd: 850,
    packEnd: 920,
  );

  String columnFor(OcrWord word) {
    final x = word.midX;
    if (x < srEnd)       return 'sr';
    if (x < partNoEnd)   return 'partNo';
    if (x < descEnd)     return 'desc';
    if (x < mrpEnd)      return 'mrp';
    if (x < qtyEnd)      return 'qty';
    if (x < locationEnd) return 'location';
    if (x < packEnd)     return 'pack';
    return 'stock';
  }
}

// =============================================================================
// OCR CORRECTION (database-justified — same rules as PartNumberParser)
// Safe global:    O→0, I→1, Q→0
// Prefix-only:    S→5, B→8, Z→2, G→6, L→1, E→3
// Never:          D→0 (8,355 real D's in DB)
// =============================================================================

String _safeCorrect(String s) =>
    s.replaceAll('O', '0').replaceAll('Q', '0').replaceAll('I', '1');

String _applyOcrCorrection(String normalized) {
  String result = _safeCorrect(normalized);
  final dashIdx = result.indexOf('-');
  if (dashIdx > 0) {
    final prefix = result.substring(0, dashIdx);
    final suffix = result.substring(dashIdx);
    final strippedPrefix = prefix.replaceAll(RegExp(r'[SBZGLE]'), '');
    if (RegExp(r'^\d*$').hasMatch(strippedPrefix) &&
        prefix.length >= 4 &&
        prefix.length <= 6) {
      final correctedPrefix = prefix
          .replaceAll('S', '5')
          .replaceAll('B', '8')
          .replaceAll('Z', '2')
          .replaceAll('G', '6')
          .replaceAll('L', '1')
          .replaceAll('E', '3');
      result = correctedPrefix + suffix;
    }
  }
  return result;
}

String _normalizePartNo(String raw) {
  return raw
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[\.\s]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'[^A-Z0-9\-]'), '')
      .trim();
}

/// Flexible part number pattern — matches OCR-damaged values.
final _partNoPattern = RegExp(
  r'\b[A-Z0-9]{4,7}[.\s\-]+[A-Z0-9]{3}(?:[.\s\-]+[A-Z0-9]{2,7})?\b',
);

/// Numeric-only price pattern (e.g. 123.45 or 12345)
final _pricePattern = RegExp(r'\b(\d{2,6}(?:[\.,]\d{2})?)\b');

// =============================================================================
// MEMO OCR ENGINE
// =============================================================================

class MemoOcrEngine {
  MemoOcrEngine._();

  // Y-grouping tolerance — words within 15px of each other are on the same row
  static const int _yThreshold = 15;

  // ───────────────────────────────────────────────────────────────
  // STEP 1+2: ML Kit OCR → OcrRows
  // ───────────────────────────────────────────────────────────────

  /// Run ML Kit OCR and reconstruct rows by Y-coordinate proximity.
  static Future<({List<OcrRow> rows, String rawDump})> runOcr(File imageFile) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognized = await textRecognizer.processImage(inputImage);

      final allWords = <OcrWord>[];
      final dumpBuffer = StringBuffer();

      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            final bb = element.boundingBox;
            if (bb == null) continue;
            allWords.add(OcrWord(
              text: element.text,
              left: bb.left.toInt(),
              top: bb.top.toInt(),
              right: bb.right.toInt(),
              bottom: bb.bottom.toInt(),
            ));
            dumpBuffer.write('[y=${bb.top.toInt()}] ${element.text} ');
          }
          dumpBuffer.writeln();
        }
      }

      // Sort all words top-to-bottom, then left-to-right
      allWords.sort((a, b) {
        final yDiff = a.midY - b.midY;
        return yDiff.abs() <= _yThreshold ? a.midX - b.midX : yDiff;
      });

      // Group words into rows by Y proximity
      final rows = <OcrRow>[];
      var currentWords = <OcrWord>[];
      int? currentY;

      for (final word in allWords) {
        if (currentY == null || (word.midY - currentY).abs() <= _yThreshold) {
          currentWords.add(word);
          currentY = currentY == null
              ? word.midY
              : ((currentY + word.midY) ~/ 2);
        } else {
          if (currentWords.isNotEmpty) {
            currentWords.sort((a, b) => a.midX - b.midX);
            rows.add(OcrRow(
              words: List.unmodifiable(currentWords),
              approximateY: currentY!,
            ));
          }
          currentWords = [word];
          currentY = word.midY;
        }
      }
      if (currentWords.isNotEmpty) {
        currentWords.sort((a, b) => a.midX - b.midX);
        rows.add(OcrRow(
          words: List.unmodifiable(currentWords),
          approximateY: currentY!,
        ));
      }

      return (rows: rows, rawDump: dumpBuffer.toString());
    } finally {
      await textRecognizer.close();
    }
  }

  // ───────────────────────────────────────────────────────────────
  // STEP 3: Column layout detection
  // ───────────────────────────────────────────────────────────────

  static ColumnLayout detectColumns(List<OcrRow> rows) {
    // Find the header row
    OcrRow? headerRow;
    for (final row in rows) {
      if (row.isHeaderRow) {
        headerRow = row;
        break;
      }
    }
    if (headerRow == null) return ColumnLayout.defaultLayout;

    // Map header keyword → midX
    final xMap = <String, int>{};
    for (final word in headerRow.words) {
      final upper = word.text.toUpperCase();
      if (upper.contains('SR') || upper.contains('S.R')) xMap['sr'] = word.midX;
      if (upper.contains('PART')) xMap['partNo'] = word.midX;
      if (upper.contains('DESC')) xMap['desc'] = word.midX;
      if (upper.contains('MRP'))  xMap['mrp'] = word.midX;
      if (upper.contains('QTY'))  xMap['qty'] = word.midX;
      if (upper.contains('LOC'))  xMap['location'] = word.midX;
      if (upper.contains('PACK') || upper.contains('PKT')) xMap['pack'] = word.midX;
      if (upper.contains('STOCK') || upper.contains('STK')) xMap['stock'] = word.midX;
    }

    // Build boundaries using midpoints between adjacent columns
    int midpoint(String a, String b) {
      final xA = xMap[a];
      final xB = xMap[b];
      if (xA == null || xB == null) return ColumnLayout.defaultLayout.srEnd;
      return (xA + xB) ~/ 2;
    }

    return ColumnLayout(
      srEnd: xMap['sr'] != null && xMap['partNo'] != null
          ? midpoint('sr', 'partNo')
          : ColumnLayout.defaultLayout.srEnd,
      partNoEnd: xMap['partNo'] != null && xMap['desc'] != null
          ? midpoint('partNo', 'desc')
          : ColumnLayout.defaultLayout.partNoEnd,
      descEnd: xMap['desc'] != null && xMap['mrp'] != null
          ? midpoint('desc', 'mrp')
          : ColumnLayout.defaultLayout.descEnd,
      mrpEnd: xMap['mrp'] != null && xMap['qty'] != null
          ? midpoint('mrp', 'qty')
          : ColumnLayout.defaultLayout.mrpEnd,
      qtyEnd: xMap['qty'] != null && xMap['location'] != null
          ? midpoint('qty', 'location')
          : ColumnLayout.defaultLayout.qtyEnd,
      locationEnd: xMap['location'] != null && xMap['pack'] != null
          ? midpoint('location', 'pack')
          : ColumnLayout.defaultLayout.locationEnd,
      packEnd: xMap['pack'] != null && xMap['stock'] != null
          ? midpoint('pack', 'stock')
          : ColumnLayout.defaultLayout.packEnd,
    );
  }

  // ───────────────────────────────────────────────────────────────
  // STEP 4+5: Row extraction + DB-first validation
  // ───────────────────────────────────────────────────────────────

  /// Extract a single item from a row using column layout.
  /// Returns null if the row doesn't contain a part number.
  static Future<ExtractedMemoItem?> extractItemFromRow(
    OcrRow row,
    ColumnLayout cols,
    AppDatabase db,
  ) async {
    // Assign words to columns
    final colTexts = <String, List<String>>{
      'sr': [],
      'partNo': [],
      'desc': [],
      'mrp': [],
      'qty': [],
      'location': [],
      'pack': [],
      'stock': [],
    };
    for (final word in row.words) {
      colTexts[cols.columnFor(word)]!.add(word.text);
    }

    final rawPartNoText = colTexts['partNo']!.join(' ').trim().toUpperCase();
    if (rawPartNoText.isEmpty) return null;

    // Check if this row could be a part number row
    // Must contain at least 7 chars resembling a part number
    final partNoMatch = _partNoPattern.firstMatch(rawPartNoText);
    if (partNoMatch == null && rawPartNoText.length < 7) return null;

    final rawPartNo = partNoMatch != null
        ? partNoMatch.group(0)!.replaceAll(RegExp(r'[\.\s]+'), '-').toUpperCase()
        : rawPartNoText;

    // Extract other fields
    final descText = colTexts['desc']!.join(' ').trim();
    final mrpText = colTexts['mrp']!.join('').trim();
    final qtyText = colTexts['qty']!.join('').trim();
    final locationText = colTexts['location']!.join(' ').trim().toUpperCase();
    final packText = colTexts['pack']!.join('').trim();
    final stockText = colTexts['stock']!.join('').trim();

    // Parse numeric fields
    double mrp = 0.0;
    final priceMatch = _pricePattern.firstMatch(
        mrpText.replaceAll(RegExp(r'[Oo]'), '0').replaceAll(RegExp(r'[Il]'), '1'));
    if (priceMatch != null) {
      mrp = double.tryParse(
              priceMatch.group(1)!.replaceAll(',', '.')) ??
          0.0;
    }

    final cleanNum = (String s) =>
        s.replaceAll(RegExp(r'[Oo]'), '0').replaceAll(RegExp(r'[Il]'), '1');

    final qty = int.tryParse(cleanNum(qtyText)) ?? 1;
    final pack = int.tryParse(cleanNum(packText)) ?? 0;
    final stock = int.tryParse(cleanNum(stockText)) ?? 0;

    // DB-first validation with confidence scoring
    return await _validateWithDb(
      rawPartNo: rawPartNo,
      description: descText,
      mrp: mrp,
      qty: qty,
      location: locationText,
      pack: pack,
      stock: stock,
      db: db,
    );
  }

  /// Validate and resolve a part number against the local DB.
  /// Returns an [ExtractedMemoItem] with the highest achievable confidence.
  static Future<ExtractedMemoItem> _validateWithDb({
    required String rawPartNo,
    required String description,
    required double mrp,
    required int qty,
    required String location,
    required int pack,
    required int stock,
    required AppDatabase db,
  }) async {
    // ── Tier 1: Exact match (100%) ──────────────────────────────────────────
    var matches = await (db.select(db.inventory)
          ..where((t) => t.partNo.equals(rawPartNo)))
        .get();
    if (matches.isNotEmpty) {
      return _buildItem(rawPartNo, rawPartNo, matches.first,
          MatchConfidence.exact, mrp, qty, pack, description);
    }

    // ── Tier 2: Normalized match (95%) — strip dashes/spaces ────────────────
    final normalized = _normalizePartNo(rawPartNo);
    if (normalized != rawPartNo) {
      matches = await (db.select(db.inventory)
            ..where((t) => t.partNo.equals(normalized)))
          .get();
      if (matches.isNotEmpty) {
        return _buildItem(rawPartNo, normalized, matches.first,
            MatchConfidence.normalized, mrp, qty, pack, description);
      }
    }

    // ── Tier 3: OCR correction (85%) ────────────────────────────────────────
    final corrected = _applyOcrCorrection(normalized);
    if (corrected != normalized) {
      matches = await (db.select(db.inventory)
            ..where((t) => t.partNo.equals(corrected)))
          .get();
      if (matches.isNotEmpty) {
        return _buildItem(rawPartNo, corrected, matches.first,
            MatchConfidence.fuzzy, mrp, qty, pack, description);
      }
    }

    // ── Tier 4: LIKE partial match (sends to Gemini) ─────────────────────────
    // Try stripping leading garbage (pipe chars, spaces)
    var cleaned = rawPartNo;
    while (cleaned.length > 7 &&
        (cleaned.startsWith('1') ||
            cleaned.startsWith('|') ||
            cleaned.startsWith('/') ||
            cleaned.startsWith('!'))) {
      cleaned = cleaned.substring(1);
      matches = await (db.select(db.inventory)
            ..where((t) => t.partNo.equals(cleaned)))
          .get();
      if (matches.isNotEmpty) {
        return _buildItem(rawPartNo, cleaned, matches.first,
            MatchConfidence.normalized, mrp, qty, pack, description);
      }
    }

    // ── No DB match → unmatched (will be sent to Gemini) ─────────────────────
    return ExtractedMemoItem(
      rawOcrPartNo: rawPartNo,
      correctedPartNo: corrected.isNotEmpty ? corrected : rawPartNo,
      confidence: MatchConfidence.unmatched,
      description: description,
      mrp: mrp,
      qty: qty,
      location: location,
      pack: pack,
      stock: stock,
    );
  }

  static ExtractedMemoItem _buildItem(
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

  // ───────────────────────────────────────────────────────────────
  // STEP 6: Header extraction
  // ───────────────────────────────────────────────────────────────

  static ExtractedMemoHeader extractHeader(String rawText) {
    // Customer name
    String customerName = 'OCR Generated Order';
    final custMatch = RegExp(
      r'M/S\.?,?\s*([^\n\r]+)',
      caseSensitive: false,
    ).firstMatch(rawText);
    if (custMatch != null) {
      customerName = custMatch.group(1)!.trim();
      // Remove trailing address suffixes
      customerName = customerName.replaceAll(
        RegExp(r'\s+(VANSADA|SURAT|KIM|RUSTAMPURA|KOSAMBA|BILIMORA|NAVSARI|BHARUCH).*$',
            caseSensitive: false),
        '',
      );
    }

    // Area
    String area = 'Warehouse Floor';
    final areaMatch = RegExp(
      r'AREA\s*:\s*([^\n\r]+)',
      caseSensitive: false,
    ).firstMatch(rawText);
    if (areaMatch != null) {
      area = areaMatch.group(1)!.trim();
    } else {
      final cityMatch = RegExp(
        r'(VANSADA|RUSTAMPURA|SURAT|KIM|KOSAMBA|BILIMORA|NAVSARI|BHARUCH)',
        caseSensitive: false,
      ).firstMatch(rawText);
      if (cityMatch != null) area = cityMatch.group(1)!.trim().toUpperCase();
    }

    // Memo number
    String memoNumber =
        'MEMO-OCR-${DateTime.now().millisecondsSinceEpoch}';
    final memoMatch = RegExp(
      r'MEMO\s*NO\.?\s*:?\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(rawText);
    if (memoMatch != null) memoNumber = memoMatch.group(1)!.trim();

    // Memo date (dd/mm/yyyy or dd-mm-yyyy or similar)
    String? memoDate;
    final dateMatch = RegExp(
      r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\b',
    ).firstMatch(rawText);
    if (dateMatch != null) {
      try {
        final day   = int.parse(dateMatch.group(1)!);
        final month = int.parse(dateMatch.group(2)!);
        var year    = int.parse(dateMatch.group(3)!);
        if (year < 100) year += 2000;
        memoDate = DateTime(year, month, day).toIso8601String();
      } catch (_) {}
    }

    return ExtractedMemoHeader(
      customerName: customerName,
      area: area,
      memoNumber: memoNumber,
      memoDate: memoDate,
    );
  }

  // ───────────────────────────────────────────────────────────────
  // STEP 7: Full pipeline runner
  // ───────────────────────────────────────────────────────────────

  /// Run the complete pipeline on a memo image file.
  /// Returns a [MemoOcrResult] with header, items, and raw OCR dump.
  static Future<MemoOcrResult> process(File imageFile, AppDatabase db) async {
    // Step 1+2: OCR → rows
    final (:rows, :rawDump) = await runOcr(imageFile);

    // Step 3: Column detection
    final cols = detectColumns(rows);

    // Step 4+5: Item extraction + DB validation
    final items = <ExtractedMemoItem>[];
    final headerText = rows
        .where((r) => !r.isHeaderRow)
        .take(5)
        .map((r) => r.fullText)
        .join('\n');
    final header = extractHeader('$headerText\n$rawDump');

    // Find the header row Y to skip anything above it (title/company info)
    int? headerRowY;
    for (final row in rows) {
      if (row.isHeaderRow) {
        headerRowY = row.approximateY;
        break;
      }
    }

    for (final row in rows) {
      if (row.isHeaderRow) continue;
      if (headerRowY != null && row.approximateY <= headerRowY) continue;
      if (row.words.isEmpty) continue;

      try {
        final item = await extractItemFromRow(row, cols, db);
        if (item != null) items.add(item);
      } catch (e) {
        if (kDebugMode) print('[MemoOcrEngine] Row extraction error: $e');
      }
    }

    // Deduplicate by correctedPartNo (keep first occurrence)
    final seen = <String>{};
    final deduped = items.where((i) => seen.add(i.correctedPartNo)).toList();

    return MemoOcrResult(
      header: header,
      items: deduped,
      rawOcrDump: rawDump,
      imagePath: imageFile.path,
    );
  }
}
