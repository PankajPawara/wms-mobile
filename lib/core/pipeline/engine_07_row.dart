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

class _ProjectedCell {
  final String columnKey;
  final CellData cell;
  final double baseY;

  _ProjectedCell(this.columnKey, this.cell, this.baseY);
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
      // STEP 1 — Calculate Global Skew (Slope)
      // -----------------------------------------------------------------------
      // Pre-calculate column center X coordinates
      final colCenters = <String, double>{};
      for (final col in input.gridGeometry.columns) {
        colCenters[col.key] = (col.leftX + col.rightX) / 2.0;
      }

      // Collect pairs of adjacent cells to calculate slopes
      final slopes = <double>[];
      final colKeys = input.gridGeometry.columns.map((c) => c.key).toList();
      
      for (int i = 0; i < colKeys.length - 1; i++) {
        final leftKey = colKeys[i];
        final rightKey = colKeys[i + 1];
        final leftCells = input.columns[leftKey] ?? [];
        final rightCells = input.columns[rightKey] ?? [];
        
        final leftX = colCenters[leftKey] ?? 0.0;
        final rightX = colCenters[rightKey] ?? 0.0;
        if (rightX - leftX < 10) continue; // avoid divide by zero

        // For each left cell, find the closest right cell in Y
        for (final lCell in leftCells) {
          CellData? bestR;
          int bestDist = 30; // max reasonable Y drift between adjacent columns
          for (final rCell in rightCells) {
            final dist = (lCell.topY - rCell.topY).abs();
            if (dist < bestDist) {
              bestDist = dist;
              bestR = rCell;
            }
          }
          if (bestR != null) {
            final slope = (bestR.topY - lCell.topY) / (rightX - leftX);
            slopes.add(slope);
          }
        }
      }

      double globalSlope = 0.0;
      if (slopes.isNotEmpty) {
        slopes.sort();
        globalSlope = slopes[slopes.length ~/ 2];
      }

      // -----------------------------------------------------------------------
      // STEP 2 — Project all cells to Base Y (X = 0) and Cluster
      // -----------------------------------------------------------------------
      // Wrapper to hold cell with its projected base Y
      final allProjected = <_ProjectedCell>[];
      for (final entry in input.columns.entries) {
        final key = entry.key;
        final centerX = colCenters[key] ?? 0.0;
        for (final cell in entry.value) {
          final baseY = cell.topY - (centerX * globalSlope);
          allProjected.add(_ProjectedCell(key, cell, baseY));
        }
      }

      // Sort all cells globally by their flattened baseY
      allProjected.sort((a, b) => a.baseY.compareTo(b.baseY));

      // 1D Clustering
      final rowClusters = <List<_ProjectedCell>>[];
      List<_ProjectedCell> currentCluster = [];
      
      for (final pc in allProjected) {
        if (currentCluster.isEmpty) {
          currentCluster.add(pc);
        } else {
          final avgBaseY = currentCluster.map((c) => c.baseY).reduce((a, b) => a + b) / currentCluster.length;
          if ((pc.baseY - avgBaseY).abs() < 15.0) { // row tolerance
            currentCluster.add(pc);
          } else {
            rowClusters.add(currentCluster);
            currentCluster = [pc];
          }
        }
      }
      if (currentCluster.isNotEmpty) {
        rowClusters.add(currentCluster);
      }

      // -----------------------------------------------------------------------
      // STEP 3 — Assemble Rows
      // -----------------------------------------------------------------------
      final rows = <PartRow>[];

      for (final cluster in rowClusters) {
        // Find average BaseY for this cluster to resolve duplicate columns
        final avgBaseY = cluster.map((c) => c.baseY).reduce((a, b) => a + b) / cluster.length;

        // If multiple cells in the cluster belong to the SAME column, pick the one closest to avgBaseY
        final columnMap = <String, CellData>{};
        final columnBestDist = <String, double>{};

        for (final pc in cluster) {
          final dist = (pc.baseY - avgBaseY).abs();
          if (!columnMap.containsKey(pc.columnKey) || dist < columnBestDist[pc.columnKey]!) {
            columnMap[pc.columnKey] = pc.cell;
            columnBestDist[pc.columnKey] = dist;
          }
        }

        final rawSr    = columnMap['SR']?.text ?? '';
        final rawPart  = columnMap['PART']?.text ?? '';
        final rawDesc  = columnMap['DESC']?.text ?? '';
        final rawMrp   = columnMap['MRP']?.text ?? '';
        final rawQty   = columnMap['QTY']?.text ?? '';
        final rawLoc   = columnMap['LOC']?.text ?? '';
        final rawPack  = columnMap['PACK']?.text ?? '';
        final rawStock = columnMap['STOCK']?.text ?? '';

        // Clean SR — digits only
        final sr = rawSr.replaceAll(RegExp(r'[^0-9]'), '').trim();

        // Extract part number and recover leaked description prefix words
        final partResult = _processPartAndDesc(rawPart, rawDesc);
        final partNo = partResult['part']!;
        final desc   = partResult['desc']!;

        // Extract QTY, MRP, and LOC together from right-side columns
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
