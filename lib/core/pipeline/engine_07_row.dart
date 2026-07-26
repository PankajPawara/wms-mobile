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
  static Future<PipelineResult<RowBuilderOutput>> build(CellAssignmentOutput input) async {
    final stopwatch = Stopwatch()..start();
    final errors = <String>[];

    try {
      // 1. Collect all cells across all columns to find unique row Y-clusters
      final allCells = <CellData>[];
      for (final colCells in input.columns.values) {
        allCells.addAll(colCells);
      }
      
      allCells.sort((a, b) => a.topY.compareTo(b.topY));
      
      final rowClusters = <List<CellData>>[];
      if (allCells.isNotEmpty) {
        List<CellData> currentRow = [allCells.first];
        for (int i = 1; i < allCells.length; i++) {
          final c = allCells[i];
          // Anchor the row to the top of its first cell to prevent rolling average drift
          final anchorTopY = currentRow.first.topY;
          
          if ((c.topY - anchorTopY).abs() < 20) {
            currentRow.add(c);
          } else {
            rowClusters.add(currentRow);
            currentRow = [c];
          }
        }
        if (currentRow.isNotEmpty) {
          rowClusters.add(currentRow);
        }
      }

      final rows = <PartRow>[];
      
      for (final cluster in rowClusters) {
        final minTopY = cluster.map((c) => c.topY).reduce((a, b) => a < b ? a : b) - 10;
        final maxBottomY = cluster.map((c) => c.bottomY).reduce((a, b) => a > b ? a : b) + 10;
        
        String getTextForCol(String key) {
           final cellsInCol = input.columns[key] ?? [];
           final match = cellsInCol.where((c) => 
               c.topY >= minTopY && c.bottomY <= maxBottomY ||
               ((c.topY + c.bottomY)/2 >= minTopY && (c.topY + c.bottomY)/2 <= maxBottomY)
           ).toList();
           
           if (match.isEmpty) return '';
           match.sort((a, b) => a.topY.compareTo(b.topY));
           return match.map((c) => c.text).join(' ').trim();
        }
        
        String sr = getTextForCol('SR');
        String partNo = getTextForCol('PART');
        String desc = getTextForCol('DESC');
        String mrp = getTextForCol('MRP');
        String qty = getTextForCol('QTY');
        String loc = getTextForCol('LOC');
        String pack = getTextForCol('PACK');
        String stock = getTextForCol('STOCK');
        
        // Strip artifacts like |
        partNo = partNo.replaceAll('|', '').trim();
        mrp = mrp.replaceAll('|', '').replaceAll('I', '').replaceAll('l', '').trim();
        qty = qty.replaceAll('|', '').replaceAll('I', '').replaceAll('L', '').trim();
        loc = loc.replaceAll('|', '').trim();
        pack = pack.replaceAll('|', '').replaceAll('I', '').trim();
        
        bool isNoise = partNo.toUpperCase().contains('MEMO') || 
                       partNo.toUpperCase().contains('DATE') || 
                       partNo.toUpperCase().contains('TOTAL') ||
                       partNo.toUpperCase().contains('AMOUNT');
                       
        if (partNo.isEmpty && desc.isEmpty && mrp.isEmpty) continue;
        
        if (!isNoise) {
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
}
