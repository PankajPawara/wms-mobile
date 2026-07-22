import 'models/pipeline_result.dart';
import 'models/pipeline_stage.dart';
import 'engine_06_cell.dart' show CellAssignmentOutput;

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
  final CellAssignmentOutput cellAssignment;
  final List<PartRow> rows;

  RowBuilderOutput({
    required this.cellAssignment,
    required this.rows,
  });

  Map<String, dynamic> toJson() {
    return {
      'cellAssignment': cellAssignment.toJson(),
      'rows': rows.map((r) => r.toJson()).toList(),
    };
  }
}

class Engine07RowBuilder {
  static Future<PipelineResult<RowBuilderOutput>> build(CellAssignmentOutput input) async {
    final stopwatch = Stopwatch()..start();
    final errors = <String>[];

    try {
      final columns = input.columns;
      final srCells = columns['SR'] ?? [];
      final partCells = columns['PART'] ?? [];

      // 1. Collect all potential row anchors (Y-coordinates) from SR and PART columns
      final rawAnchors = <int>[];
      for (final c in srCells) {
        rawAnchors.add((c.topY + c.bottomY) ~/ 2);
      }
      for (final c in partCells) {
        rawAnchors.add((c.topY + c.bottomY) ~/ 2);
      }

      // Sort anchors top to bottom
      rawAnchors.sort();

      // Merge anchors that are very close to each other (e.g. within 30 pixels)
      // This happens because SR and PART on the same line might have slightly different Y centers.
      final rowAnchors = <int>[];
      if (rawAnchors.isNotEmpty) {
        List<int> currentCluster = [rawAnchors.first];
        
        for (int i = 1; i < rawAnchors.length; i++) {
          final a = rawAnchors[i];
          final clusterAvg = currentCluster.reduce((a, b) => a + b) ~/ currentCluster.length;
          
          if ((a - clusterAvg).abs() < 30) {
            currentCluster.add(a);
          } else {
            rowAnchors.add(currentCluster.reduce((a, b) => a + b) ~/ currentCluster.length);
            currentCluster = [a];
          }
        }
        if (currentCluster.isNotEmpty) {
          rowAnchors.add(currentCluster.reduce((a, b) => a + b) ~/ currentCluster.length);
        }
      }

      // 2. Helper function to extract text from a column given an anchor Y
      String getCellTextForAnchor(String colKey, int anchorY) {
        final cells = columns[colKey] ?? [];
        final matches = cells.where((c) {
          // A cell belongs to this row if the anchor Y falls inside the cell's vertical bounds 
          // (with a generous +/- 20 pixel padding for slight tilt)
          return anchorY >= (c.topY - 20) && anchorY <= (c.bottomY + 20);
        }).toList();

        if (matches.isEmpty) return '';
        // If multiple cells match (e.g. multi-line description), join them
        return matches.map((c) => c.text).join(' ').trim();
      }

      // 3. Build the rows
      final rows = <PartRow>[];
      for (final anchorY in rowAnchors) {
        String sr = getCellTextForAnchor('SR', anchorY);
        String partNo = getCellTextForAnchor('PART', anchorY);
        String desc = getCellTextForAnchor('DESC', anchorY);
        String mrp = getCellTextForAnchor('MRP', anchorY);
        String qty = getCellTextForAnchor('QTY', anchorY);
        String loc = getCellTextForAnchor('LOC', anchorY);
        String pack = getCellTextForAnchor('PACK', anchorY);
        String stock = getCellTextForAnchor('STOCK', anchorY);

        // Basic cleanups: remove rogue pipe characters
        partNo = partNo.replaceAll('|', '').trim();
        desc = desc.replaceAll('|', '').trim();

        // Only add rows that look somewhat legitimate (have a Part No or Description)
        if (partNo.isNotEmpty || desc.isNotEmpty) {
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
      }

      stopwatch.stop();

      return PipelineResult(
        data: RowBuilderOutput(
          cellAssignment: input,
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
}
