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
  // We prefer columns that have one clean cell per row.
  static const _anchorPriority = ['MRP', 'PART', 'DESC', 'QTY', 'SR'];

  static Future<PipelineResult<RowBuilderOutput>> build(CellAssignmentOutput input) async {
    final stopwatch = Stopwatch()..start();
    final errors = <String>[];

    try {
      // -----------------------------------------------------------------------
      // STEP 1: Pick the best anchor column.
      // The anchor column drives the row band boundaries. We pick the column
      // that (a) has the most cells and (b) its cells are most evenly spaced.
      // -----------------------------------------------------------------------
      String? anchorKey;
      List<CellData> anchorCells = [];

      // Try preferred columns first
      for (final key in _anchorPriority) {
        final cells = input.columns[key];
        if (cells != null && cells.length > anchorCells.length) {
          anchorKey = key;
          anchorCells = List.from(cells);
        }
      }

      // Fall back to whichever column has the most cells
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

      // Sort anchor cells top-to-bottom
      anchorCells.sort((a, b) => a.topY.compareTo(b.topY));

      // -----------------------------------------------------------------------
      // STEP 2: Derive row band boundaries from anchor column.
      // Band start = midpoint between previous anchor cell top and this one.
      // Band end   = midpoint between this anchor cell top and next one.
      // This gives clean, non-overlapping, non-missing bands that perfectly
      // tile the document regardless of per-column Y jitter.
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
      // STEP 3: For each band, collect matching cells from every column.
      // A cell "matches" a band if its center-Y falls within [bandStart, bandEnd].
      // -----------------------------------------------------------------------
      String getTextForBand(String key, int bandStart, int bandEnd) {
        final cells = input.columns[key] ?? [];
        final matching = cells.where((c) {
          final cy = (c.topY + c.bottomY) ~/ 2;
          return cy >= bandStart && cy <= bandEnd;
        }).toList();
        if (matching.isEmpty) return '';
        matching.sort((a, b) => a.topY.compareTo(b.topY));
        return matching.map((c) => c.text).join(' ').trim();
      }

      final rows = <PartRow>[];

      for (final band in rowBands) {
        final (bandStart, bandEnd) = band;

        String sr      = getTextForBand('SR',    bandStart, bandEnd);
        String partNo  = getTextForBand('PART',  bandStart, bandEnd);
        String desc    = getTextForBand('DESC',  bandStart, bandEnd);
        String mrp     = getTextForBand('MRP',   bandStart, bandEnd);
        String qty     = getTextForBand('QTY',   bandStart, bandEnd);
        String loc     = getTextForBand('LOC',   bandStart, bandEnd);
        String pack    = getTextForBand('PACK',  bandStart, bandEnd);
        String stock   = getTextForBand('STOCK', bandStart, bandEnd);

        // ---- Clean up OCR noise ----
        // Strip leading/trailing pipe characters and OCR artefacts
        partNo = _cleanPartNo(partNo);
        mrp    = _cleanMrp(mrp);
        qty    = _cleanQty(qty);
        loc    = loc.replaceAll('|', '').trim();
        pack   = pack.replaceAll(RegExp(r'[|!]'), '').trim();

        // Skip completely empty rows
        if (partNo.isEmpty && desc.isEmpty && mrp.isEmpty) continue;

        // Skip known noise / footer lines
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
  // Helpers
  // ---------------------------------------------------------------------------

  /// Remove leading pipe/number artifacts OCR attaches to part numbers.
  /// e.g. "|35150-KTE-600 SW" → "35150-KTE-600"
  /// "1STAY" where 1 is OCR pipe artifact → "STAY"
  static String _cleanPartNo(String raw) {
    // Remove pipe characters
    String s = raw.replaceAll('|', '').replaceAll('I', ' ').trim();
    // Remove leading single digit that is an OCR artefact of a pipe/column separator
    s = s.replaceAll(RegExp(r'^\d\s+(?=[A-Z])'), '').trim();
    // Extract only the first token that looks like a valid Honda part number
    // Honda format: digits-LETTERS-digits or pure alphanumeric with hyphens
    final partMatch = RegExp(r'\b\d{4,6}-[A-Z0-9]{2,4}-[A-Z0-9]{2,4}\b').firstMatch(s);
    if (partMatch != null) {
      return partMatch.group(0)!;
    }
    // Otherwise return cleaned string
    return s;
  }

  /// Clean MRP value — strip trailing pipe/letter OCR noise.
  static String _cleanMrp(String raw) {
    String s = raw.replaceAll('|', '').trim();
    // Match a valid price like 77.00 or 1295.00
    final m = RegExp(r'\d[\d,]*\.\d{2}').firstMatch(s);
    return m != null ? m.group(0)! : s;
  }

  /// Clean QTY value — extract leading number (quantity), strip location code.
  static String _cleanQty(String raw) {
    String s = raw.replaceAll('|', '').replaceAll('I', '').trim();
    // QTY is just the leading number, location code comes after a space
    final m = RegExp(r'^\d+').firstMatch(s);
    return m != null ? m.group(0)! : s;
  }

  static bool _isNoiseLine(String partNo, String desc) {
    final combined = '$partNo $desc'.toUpperCase();
    return combined.contains('MEMO') ||
        combined.contains('DATE') ||
        combined.contains('TOTAL') ||
        combined.contains('AMOUNT') ||
        combined.contains('ORDER /') ||
        combined.contains('PICKING LIST');
  }
}
