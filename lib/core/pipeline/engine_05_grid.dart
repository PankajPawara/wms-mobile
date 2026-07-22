import 'models/pipeline_result.dart';
import 'models/pipeline_stage.dart';
import 'engine_04_table_detection.dart' show TableGeometryOutput;
import '../services/memo_ocr_engine.dart' show OcrWord;

class ColumnDef {
  final String key;
  final int leftX;
  final int rightX;

  ColumnDef({
    required this.key,
    required this.leftX,
    required this.rightX,
  });

  Map<String, dynamic> toJson() => {
    'key': key,
    'leftX': leftX,
    'rightX': rightX,
  };
}

class GridGeometryOutput {
  final TableGeometryOutput tableGeometry;
  final List<ColumnDef> columns;

  GridGeometryOutput({
    required this.tableGeometry,
    required this.columns,
  });

  Map<String, dynamic> toJson() {
    return {
      'tableGeometry': tableGeometry.toJson(),
      'columns': columns.map((c) => c.toJson()).toList(),
    };
  }
}

class Engine05GridSystem {
  static Future<PipelineResult<GridGeometryOutput>> generate(TableGeometryOutput input) async {
    final stopwatch = Stopwatch()..start();
    final errors = <String>[];

    try {
      final headerWords = <OcrWord>[];
      // The header is just above the table topY (Engine 04 added +5 to the lowest pixel of the header)
      final headerSearchBottom = input.topY;
      final headerSearchTop = input.topY - 100;

      for (final w in input.allWords) {
        int cy = (w.top + w.bottom) ~/ 2;
        if (cy >= headerSearchTop && cy <= headerSearchBottom) {
          headerWords.add(w);
        }
      }

      // Helper to find a word's horizontal bounds
      OcrWord? findHeader(List<String> keywords) {
        for (final w in headerWords) {
          final t = w.text.toUpperCase();
          for (final kw in keywords) {
            if (t.contains(kw)) return w;
          }
        }
        return null;
      }

      final srWord = findHeader(['SR', 'S.R']);
      final partWord = findHeader(['PART']);
      final descWord = findHeader(['DESC']);
      final mrpWord = findHeader(['M.R.P', 'MRP']);
      final qtyWord = findHeader(['QTY']);
      final locWord = findHeader(['LOC']);
      final packWord = findHeader(['PACK']);
      final stockWord = findHeader(['STOCK']);

      // Calculate column boundaries.
      // A column starts slightly to the left of its header, and ends slightly to the left of the NEXT header.
      // We use absolute fallbacks based on typical image width if a header is missing.

      final w = input.imageWidth;
      
      int srX = srWord?.left ?? (w * 0.02).toInt();
      int partX = partWord?.left ?? (w * 0.08).toInt();
      int descX = descWord?.left ?? (w * 0.25).toInt();
      int mrpX = mrpWord?.left ?? (w * 0.58).toInt();
      int qtyX = qtyWord?.left ?? (w * 0.68).toInt();
      int locX = locWord?.left ?? (w * 0.74).toInt();
      int packX = packWord?.left ?? (w * 0.85).toInt();
      int stockX = stockWord?.left ?? (w * 0.92).toInt();

      // Ensure they are strictly ordered in case OCR jitter misplaced a bounding box
      if (partX <= srX) partX = srX + 50;
      if (descX <= partX) descX = partX + 150;
      if (mrpX <= descX) mrpX = descX + 300;
      if (qtyX <= mrpX) qtyX = mrpX + 50;
      if (locX <= qtyX) locX = qtyX + 50;
      if (packX <= locX) packX = locX + 50;
      if (stockX <= packX) stockX = packX + 50;

      // Create the column boundaries
      final columns = <ColumnDef>[
        ColumnDef(key: 'SR', leftX: 0, rightX: partX - 5),
        ColumnDef(key: 'PART', leftX: partX - 5, rightX: descX - 5),
        ColumnDef(key: 'DESC', leftX: descX - 5, rightX: mrpX - 5),
        ColumnDef(key: 'MRP', leftX: mrpX - 5, rightX: qtyX - 5),
        ColumnDef(key: 'QTY', leftX: qtyX - 5, rightX: locX - 5),
        ColumnDef(key: 'LOC', leftX: locX - 5, rightX: packX - 5),
        ColumnDef(key: 'PACK', leftX: packX - 5, rightX: stockX - 5),
        ColumnDef(key: 'STOCK', leftX: stockX - 5, rightX: w),
      ];

      stopwatch.stop();

      return PipelineResult(
        data: GridGeometryOutput(
          tableGeometry: input,
          columns: columns,
        ),
        timingMs: stopwatch.elapsedMilliseconds,
        confidence: 1.0,
        stage: PipelineStage.grid,
        errors: errors,
      );

    } catch (e) {
      stopwatch.stop();
      return PipelineResult.failure(
        stage: PipelineStage.grid,
        reason: e.toString(),
        timingMs: stopwatch.elapsedMilliseconds,
      );
    }
  }
}
