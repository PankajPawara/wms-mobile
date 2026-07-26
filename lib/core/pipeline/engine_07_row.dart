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

  PartRow({
    required this.sr,
    required this.partNo,
    required this.description,
    required this.mrp,
    required this.qty,
    required this.location,
    required this.pack,
    required this.stock,
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

      for (final key in _anchorPriority) {
        final cells = input.columns[key];
        if (cells != null && cells.length > anchorCells.length) {
          anchorKey = key;
          anchorCells = List.from(cells);
        }
      }

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
      // STEP 2 — Derive non-overlapping row bands from anchor cell top-Y values
      // -----------------------------------------------------------------------
      final rowBands = <(int, int)>[];
      for (int i = 0; i < anchorCells.length; i++) {
        final cell = anchorCells[i];
        final bandStart = i == 0
            ? cell.topY - 30
            : (anchorCells[i - 1].topY + cell.topY) ~/ 2;
        final bandEnd = i == anchorCells.length - 1
            ? cell.bottomY + 30
            : (cell.topY + anchorCells[i + 1].topY) ~/ 2;
        rowBands.add((bandStart, bandEnd));
      }

      // -----------------------------------------------------------------------
      // STEP 3 — Hybrid cell matching strategy
      //
      // PROBLEM: Different columns have a consistent vertical offset from the
      // anchor column. E.g., PART cells are ~28px HIGHER than the corresponding
      // MRP cells on the same physical row. This causes two PART cells to fall
      // within the first MRP band when the band is defined by midpoints.
      //
      // SOLUTION:
      //   - If a column has the SAME number of cells as the anchor → ORDER match
      //     (assign column[i] to anchor row[i] by sorted topY). This perfectly
      //     handles the vertical-offset case since both columns have equal counts.
      //   - If a column has DIFFERENT (usually fewer) cells → BAND match using
      //     topY (not center-Y) as the inclusion test; when multiple cells fall
      //     in a band, pick the one with topY closest to anchor cell's topY.
      // -----------------------------------------------------------------------

      // Pre-sort all column cells by topY once
      final sortedColumns = <String, List<CellData>>{};
      for (final entry in input.columns.entries) {
        final sorted = List<CellData>.from(entry.value)
          ..sort((a, b) => a.topY.compareTo(b.topY));
        sortedColumns[entry.key] = sorted;
      }
      final anchorCount = anchorCells.length;

      // Order-based getter: returns the i-th cell text (used when column count == anchor count)
      String getByOrder(String key, int index) {
        final cells = sortedColumns[key] ?? [];
        if (index >= cells.length) return '';
        return cells[index].text;
      }

      // Band-based getter: returns best matching cell within [bandStart, bandEnd)
      // "Best" = topY inside band; if multiple, closest to anchorTopY.
      String getByBand(String key, int bandStart, int bandEnd, int anchorTopY) {
        final cells = sortedColumns[key] ?? [];
        final inBand = cells.where((c) => c.topY >= bandStart && c.topY < bandEnd).toList();
        if (inBand.isEmpty) return '';
        if (inBand.length == 1) return inBand.first.text;
        inBand.sort((a, b) =>
            (a.topY - anchorTopY).abs().compareTo((b.topY - anchorTopY).abs()));
        return inBand.first.text;
      }

      String getRaw(String key, int bandIndex, int bandStart, int bandEnd, int anchorTopY) {
        final cellCount = (sortedColumns[key] ?? []).length;
        if (cellCount == anchorCount) {
          return getByOrder(key, bandIndex);
        }
        return getByBand(key, bandStart, bandEnd, anchorTopY);
      }

      final rows = <PartRow>[];

      for (int bandIndex = 0; bandIndex < rowBands.length; bandIndex++) {
        final (bandStart, bandEnd) = rowBands[bandIndex];
        final anchorTopY = anchorCells[bandIndex].topY;

        final rawSr    = getRaw('SR',    bandIndex, bandStart, bandEnd, anchorTopY);
        final rawPart  = getRaw('PART',  bandIndex, bandStart, bandEnd, anchorTopY);
        final rawDesc  = getRaw('DESC',  bandIndex, bandStart, bandEnd, anchorTopY);
        final rawMrp   = getRaw('MRP',   bandIndex, bandStart, bandEnd, anchorTopY);
        final rawQty   = getRaw('QTY',   bandIndex, bandStart, bandEnd, anchorTopY);
        final rawLoc   = getRaw('LOC',   bandIndex, bandStart, bandEnd, anchorTopY);
        final rawPack  = getRaw('PACK',  bandIndex, bandStart, bandEnd, anchorTopY);
        final rawStock = getRaw('STOCK', bandIndex, bandStart, bandEnd, anchorTopY);

        // Clean SR — digits only
        final sr = rawSr.replaceAll(RegExp(r'[^0-9]'), '').trim();

        // Extract part number and recover leaked description prefix words
        final partResult = _processPartAndDesc(rawPart, rawDesc);
        final partNo = partResult['part']!;
        final desc   = partResult['desc']!;

        // Clean MRP — OCR substitutions, trailing noise
        final mrp = _cleanMrp(rawMrp);

        // Extract QTY (numeric) and LOC (location code) — may be interleaved
        final qtyLoc = _extractQtyAndLoc(rawQty, rawLoc);
        final qty = qtyLoc['qty']!;
        final loc = qtyLoc['loc']!;

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
  // Extract QTY and LOC from the raw QTY-column text.
  //
  // Root cause: E05 sometimes defines the QTY column boundary too wide, causing
  // location codes (e.g. 001L, 035X) to land in the QTY column during E06
  // cell assignment. This post-processing step separates them.
  //
  // Examples:
  //   "5 001L"   → qty=5,  loc=001L
  //   "20 021G"  → qty=20, loc=021G
  //   "035X 6"   → qty=6,  loc=035X   (loc before qty)
  //   "I 219A"   → qty="", loc=219A   (pipe artefact + loc only, qty OCR-missed)
  //   "5 I 311A" → qty=5,  loc=311A
  // ---------------------------------------------------------------------------
  static Map<String, String> _extractQtyAndLoc(
      String rawQty, String rawLoc) {
    // Remove pipe characters and known artefacts
    String qtyText = rawQty
        .replaceAll(RegExp(r'[|!]'), ' ')
        .replaceAll(RegExp(r'\bI\b'), ' ')
        .replaceAll(RegExp(r'\bl\b'), ' ')
        .trim();

    String loc = rawLoc.replaceAll(RegExp(r'[|!]'), '').trim();

    // Extract location code from QTY text if LOC is empty
    if (loc.isEmpty) {
      final locMatch = _locRegex.firstMatch(qtyText);
      if (locMatch != null) {
        loc = locMatch.group(1)!;
        qtyText = qtyText.replaceAll(locMatch.group(0)!, ' ').trim();
      }
    }

    // Extract the leading numeric quantity
    final numMatch = RegExp(r'\d+')
        .firstMatch(qtyText.replaceAll(RegExp(r'[^0-9 ]'), ' ').trim());
    final qty = numMatch != null ? numMatch.group(0)! : '';

    return {'qty': qty, 'loc': loc};
  }

  // ---------------------------------------------------------------------------
  // Clean MRP value.
  // Handles: "77.00|"→"77.00", "192.d0"→"192.00", "860.001"→"860.00"
  // OCR often reads 0 as d, O, or o; and appends the next column pipe as 1.
  // ---------------------------------------------------------------------------
  static String _cleanMrp(String raw) {
    final s = raw
        .replaceAll(RegExp(r'[|!]'), '')
        .replaceAll('O', '0') // letter O → digit 0
        .replaceAll('o', '0')
        .replaceAll('d', '0') // d misread for 0
        .replaceAll('l', '1')
        .trim();
    final m = RegExp(r'\d[\d,]*\.\d{2}').firstMatch(s);
    return m != null ? m.group(0)! : s;
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
