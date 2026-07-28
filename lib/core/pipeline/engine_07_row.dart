import 'models/pipeline_result.dart';
import 'models/pipeline_stage.dart';
import 'engine_06_cell.dart' show CellAssignmentOutput, CellData;
import 'engine_04_table_detection.dart' show TableGeometryOutput;

class PartRow {
  final String sr;
  final String partNo;
  final String description;
  final String mrp;
  final String qty;
  final String location;
  final String pack;
  final String stock;
  final bool isDbVerified;

  PartRow({
    required this.sr,
    required this.partNo,
    required this.description,
    required this.mrp,
    required this.qty,
    required this.location,
    required this.pack,
    required this.stock,
    this.isDbVerified = false,
  });

  Map<String, dynamic> toJson() => {
        'sr': sr,
        'partNo': partNo,
        'description': description,
        'mrp': mrp,
        'qty': qty,
        'location': location,
        'pack': pack,
        'stock': stock,
        'isDbVerified': isDbVerified,
      };
}

class RowBuilderOutput {
  final TableGeometryOutput tableGeometry;
  final List<PartRow> rows;

  RowBuilderOutput({
    required this.tableGeometry,
    required this.rows,
  });

  Map<String, dynamic> toJson() {
    return {
      'tableGeometry': tableGeometry.toJson(),
      'rows': rows.map((r) => r.toJson()).toList(),
    };
  }
}

class Engine07RowBuilder {
  // Priority order for anchor column selection.
  // MRP has exactly one clean price-format cell per data row — the best anchor.
  static const _anchorPriority = ['MRP', 'PART', 'DESC', 'QTY', 'SR'];

  // Honda part number: exactly 5 digits, two alphanumeric segments.
  // Uses (?<!\d) negative lookbehind so "135010-KWP-H10" does NOT match
  // "135010" (6 digits) — it only matches when 5 digits are not preceded by
  // another digit, which after progressive stripping resolves to "35010".
  static final _hondaPartRegex =
      RegExp(r'(?<!\d)(\d{5}-[A-Z0-9]{2,5}-[A-Z0-9]{2,5})(?!\d)');

  // Location code: exactly 3 digits + 1 capital letter  (001L, 035X, 219A …)
  static final _locRegex = RegExp(r'\b([0-9]{3}[A-Z])\b');

  // ---------------------------------------------------------------------------
  // Main
  // ---------------------------------------------------------------------------
  static Future<PipelineResult<RowBuilderOutput>> build(
      CellAssignmentOutput input) async {
    final stopwatch = Stopwatch()..start();
    final errors = <String>[];

    try {
      // -----------------------------------------------------------------------
      // STEP 1 — Choose the anchor column
      // -----------------------------------------------------------------------
      String? anchorKey;
      List<CellData> anchorCells = [];

      // Find the most common cell count among the major columns (mode)
      final counts = <int, int>{};
      for (final key in _anchorPriority) {
        if (input.columns[key] != null) {
          final c = input.columns[key]!.length;
          if (c > 0) {
            counts[c] = (counts[c] ?? 0) + 1;
          }
        }
      }
      
      int bestCount = 0;
      int maxFreq = 0;
      for (final entry in counts.entries) {
        if (entry.value > maxFreq || (entry.value == maxFreq && entry.key > bestCount)) {
          maxFreq = entry.value;
          bestCount = entry.key;
        }
      }

      // Pick the highest priority column that has EXACTLY bestCount cells
      for (final key in _anchorPriority) {
        final cells = input.columns[key];
        if (cells != null && cells.length == bestCount) {
          anchorKey = key;
          anchorCells = List.from(cells);
          break;
        }
      }

      // Fallback if no major columns found
      if (anchorCells.isEmpty) {
        for (final entry in input.columns.entries) {
          if (entry.value.length > anchorCells.length) {
            anchorKey = entry.key;
            anchorCells = List.from(entry.value);
          }
        }
      }

      if (anchorCells.isEmpty) {
        stopwatch.stop();
        return PipelineResult.failure(
          stage: PipelineStage.rowBuilder,
          reason: 'No cells found in any column.',
          timingMs: stopwatch.elapsedMilliseconds,
        );
      }

      anchorCells.sort((a, b) => a.topY.compareTo(b.topY));

      // -----------------------------------------------------------------------
      // STEP 2 — Calculate regression line for each row to handle perspective skew
      // -----------------------------------------------------------------------
      // Find all columns that perfectly match the row count (mode)
      final referenceColumns = <String, List<CellData>>{};
      for (final entry in input.columns.entries) {
        if (entry.value.length == bestCount) {
          final sorted = List<CellData>.from(entry.value)..sort((a, b) => a.topY.compareTo(b.topY));
          referenceColumns[entry.key] = sorted;
        }
      }

      // Pre-calculate column center X coordinates
      final colCenters = <String, double>{};
      for (final col in input.gridGeometry.columns) {
        colCenters[col.key] = (col.leftX + col.rightX) / 2.0;
      }

      // For each row (0 to bestCount - 1), calculate slope and intercept
      final rowRegressions = <int, (double slope, double intercept)>{};
      for (int i = 0; i < bestCount; i++) {
        final xs = <double>[];
        final ys = <double>[];
        for (final entry in referenceColumns.entries) {
          final colKey = entry.key;
          final cell = entry.value[i];
          final centerX = colCenters[colKey] ?? 0.0;
          xs.add(centerX);
          ys.add(cell.topY.toDouble());
        }

        double slope = 0.0;
        double intercept = anchorCells[i].topY.toDouble();

        if (xs.length >= 2) {
          double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
          for (int j = 0; j < xs.length; j++) {
            sumX += xs[j];
            sumY += ys[j];
            sumXY += xs[j] * ys[j];
            sumX2 += xs[j] * xs[j];
          }
          final n = xs.length.toDouble();
          final denom = (n * sumX2 - sumX * sumX);
          if (denom != 0) {
            slope = (n * sumXY - sumX * sumY) / denom;
            intercept = (sumY - slope * sumX) / n;
          }
        }
        rowRegressions[i] = (slope, intercept);
      }

      // -----------------------------------------------------------------------
      // STEP 3 — Hybrid cell matching strategy (Perspective Projection)
      // -----------------------------------------------------------------------
      // Pre-sort all column cells by topY once
      final sortedColumns = <String, List<CellData>>{};
      for (final entry in input.columns.entries) {
        final sorted = List<CellData>.from(entry.value)
          ..sort((a, b) => a.topY.compareTo(b.topY));
        sortedColumns[entry.key] = sorted;
      }

      String getRaw(String key, int rowIndex) {
        final cells = sortedColumns[key] ?? [];
        if (cells.isEmpty) return '';
        
        // If column has perfect cell count, map 1-to-1 by order
        if (cells.length == bestCount) {
          return cells[rowIndex].text;
        }

        // If not, use regression projection to find the closest expected Y
        final regression = rowRegressions[rowIndex]!;
        final slope = regression.$1;
        final intercept = regression.$2;
        
        double bestDist = 40.0; // threshold
        CellData? bestCell;
        final centerX = colCenters[key] ?? 0.0;
        
        for (final cell in cells) {
          final expectedY = slope * centerX + intercept;
          final dist = (cell.topY - expectedY).abs();
          if (dist < bestDist) {
            bestDist = dist;
            bestCell = cell;
          }
        }
        
        return bestCell?.text ?? '';
      }

      final rows = <PartRow>[];

      for (int i = 0; i < bestCount; i++) {
        final rawSr    = getRaw('SR',    i);
        final rawPart  = getRaw('PART',  i);
        final rawDesc  = getRaw('DESC',  i);
        final rawMrp   = getRaw('MRP',   i);
        final rawQty   = getRaw('QTY',   i);
        final rawLoc   = getRaw('LOC',   i);
        final rawPack  = getRaw('PACK',  i);
        final rawStock = getRaw('STOCK', i);

        // Clean SR — digits only
        final sr = rawSr.replaceAll(RegExp(r'[^0-9]'), '').trim();

        // Extract part number and recover leaked description prefix words
        final partResult = _processPartAndDesc(rawPart, rawDesc);
        final partNo = partResult['part']!;
        final desc   = partResult['desc']!;

        // Extract QTY, MRP, and LOC together from right-side columns
        // Physical misalignment often merges these three into one or two cells
        final rightSideData = _extractMrpQtyLoc(rawMrp, rawQty, rawLoc);
        final mrp = rightSideData['mrp']!;
        final qty = rightSideData['qty']!;
        final loc = rightSideData['loc']!;

        // Clean PACK — first number only
        final pack = _cleanCount(rawPack);

        // Clean STOCK — OCR letter substitutions
        final stock = rawStock
            .replaceAll(RegExp(r'[|!]'), '')
            .replaceAll('l', '1')
            .replaceAll('O', '0')
            .trim();

        if (partNo.isEmpty && desc.isEmpty && mrp.isEmpty) continue;
        if (_isNoiseLine(partNo, desc)) continue;

        rows.add(PartRow(
          sr: sr,
          partNo: partNo,
          description: desc,
          mrp: mrp,
          qty: qty,
          location: loc,
          pack: pack,
          stock: stock,
        ));
      }

      stopwatch.stop();

      return PipelineResult(
        data: RowBuilderOutput(
          tableGeometry: input.gridGeometry.tableGeometry,
          rows: rows,
        ),
        timingMs: stopwatch.elapsedMilliseconds,
        confidence: 1.0,
        stage: PipelineStage.rowBuilder,
        errors: errors,
      );
    } catch (e) {
      stopwatch.stop();
      return PipelineResult.failure(
        stage: PipelineStage.rowBuilder,
        reason: e.toString(),
        timingMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Extract Honda part number from raw PART-column text, and recover any
  // description words that leaked across the column boundary.
  //
  // Common OCR patterns that must be handled:
  //   "|61102-KTE-910 |STAY"  → pipe + part + pipe + leaked desc word
  //   "1STAY"                 → pipe read as "1" glued to desc word
  //   "I02380-KTE-P12 |KIT"  → pipe read as "I" glued to part number digits
  //   "135010-KWP-H10 KEY"   → pipe read as "1" prepended to 5-digit part number
  //
  // Strategy:
  //   1. Replace explicit pipes with spaces.
  //   2. Remove standalone "I" (pipe read as letter with spaces around it).
  //   3. Remove leading "I"/"l" directly touching a digit (pipe touching part).
  //   4. Remove leading single digit directly touching a letter ("1STAY"→"STAY").
  //   5. Try to match exactly-5-digit Honda part number with (?<!\d) lookbehind.
  //   6. If no match, strip the first character and retry up to 3 times.
  //      This handles "135010..." → strip "1" → "35010..." which now matches.
  //   7. Any remaining alphabetic words = leaked description prefix.
  // ---------------------------------------------------------------------------
  static Map<String, String> _processPartAndDesc(
      String rawPart, String rawDesc) {
    // Step 1-4: clean up
    String cleaned = rawPart.replaceAll('|', ' ').trim();
    cleaned = cleaned.replaceAll(RegExp(r'\bI\b'), ' ').trim(); // standalone I
    cleaned = cleaned.replaceAll(RegExp(r'^[Il](?=\d)'), '').trim(); // I/l before digit
    cleaned = cleaned.replaceAll(RegExp(r'^\d(?=[A-Z])'), '').trim(); // digit before letter
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Step 5-6: progressive match for Honda part number
    String partNo = '';
    String workStr = cleaned;
    for (int attempt = 0; attempt <= 2 && workStr.isNotEmpty; attempt++) {
      final m = _hondaPartRegex.firstMatch(workStr);
      if (m != null) {
        partNo = m.group(1)!;
        break;
      }
      workStr = workStr.substring(1).trim(); // strip one leading char and retry
    }

    // Step 7: recover leaked description words from PART text
    String scanStr = partNo.isNotEmpty
        ? cleaned.replaceAll(partNo, '').trim()
        : cleaned;

    final descPrefixWords = scanStr
        .split(RegExp(r'\s+'))
        .where((w) =>
            RegExp(r'[A-Z]{2,}').hasMatch(w) && !RegExp(r'^\d+$').hasMatch(w))
        .map((w) => w.replaceAll(RegExp(r'^\d+'), '').trim()) // strip leading artefact digits
        .where((w) => w.length >= 2)
        .toList();

    final descPrefix = descPrefixWords.join(' ');
    final fullDesc = descPrefix.isNotEmpty
        ? '$descPrefix $rawDesc'.trim()
        : rawDesc.trim();

    return {'part': partNo, 'desc': fullDesc};
  }

  // ---------------------------------------------------------------------------
  // Unified extraction of QTY, MRP, and LOC from the right-side columns.
  //
  // Root cause: E05 grid detection often merges MRP, QTY, and LOC into just
  // one or two columns.
  //   e.g. "20 6.00|" (QTY 20, MRP 6.00) in MRP column
  //   e.g. "92-001 5" (MRP 92.00, QTY 5) in MRP column
  // ---------------------------------------------------------------------------
  static Map<String, String> _extractMrpQtyLoc(String rawMrp, String rawQty, String rawLoc) {
    // Combine everything on the right side
    String rawRightSide = '$rawMrp $rawQty $rawLoc'
        .replaceAll(RegExp(r'[|!\}]'), ' ')
        .replaceAll(RegExp(r'\b[Il](?=\d)'), ' ') // strip I/l attached to start of digits (e.g. I035X)
        .replaceAll(RegExp(r'\bI\b'), ' ')
        .replaceAll('O', '0')
        .replaceAll('o', '0')
        .replaceAll('d', '0')
        .replaceAll('l', '1')
        .trim();

    // Fix colon in decimals (e.g. "92:00" -> "92.00")
    rawRightSide = rawRightSide.replaceAllMapped(RegExp(r':(\d{2})\b'), (m) => '.${m.group(1)}');

    // Fix hyphenated decimals (e.g. "92-00" -> "92.00")
    rawRightSide = rawRightSide.replaceAllMapped(RegExp(r'(\d+)-(\d{2})\b'), (m) => '${m.group(1)}.${m.group(2)}');
    // Fix OCR pipe attached to decimal (e.g. "0.001" -> "0.00")
    rawRightSide = rawRightSide.replaceAllMapped(RegExp(r'(\.\d{2})1\b'), (m) => m.group(1)!);

    String loc = '';
    final locMatch = _locRegex.firstMatch(rawRightSide);
    if (locMatch != null) {
      loc = locMatch.group(1)!;
      rawRightSide = rawRightSide.replaceAll(locMatch.group(0)!, ' ');
    }

    String mrp = '';
    final mrpMatch = RegExp(r'\d[\d,]*\.\d{2}').firstMatch(rawRightSide);
    if (mrpMatch != null) {
      mrp = mrpMatch.group(0)!;
      rawRightSide = rawRightSide.replaceAll(mrpMatch.group(0)!, ' ');
    }

    String qty = '';
    final qtyMatch = RegExp(r'\b\d+\b').firstMatch(rawRightSide);
    if (qtyMatch != null) {
      qty = qtyMatch.group(0)!;
    }

    return {'qty': qty, 'mrp': mrp, 'loc': loc};
  }

  // ---------------------------------------------------------------------------
  // Clean a count column (PACK, STOCK): strip pipe/letter noise, return first number.
  // "6 I" → "6",  "6 !" → "6",  "1" → "1"
  // ---------------------------------------------------------------------------
  static String _cleanCount(String raw) {
    final s = raw.replaceAll(RegExp(r'[|!]'), ' ').trim();
    final m = RegExp(r'^\d+').firstMatch(s);
    return m != null ? m.group(0)! : s.replaceAll(RegExp(r'[^0-9]'), '').trim();
  }

  static bool _isNoiseLine(String partNo, String desc) {
    final combined = '$partNo $desc'.toUpperCase();
    return combined.contains('PICKING LIST') ||
        combined.contains('NET AMOUNT') ||
        combined.contains('TOTAL') ||
        combined.contains('MEMO NO');
  }
}
