import 'models/pipeline_result.dart';
import 'models/pipeline_stage.dart';
import 'engine_04_table_detection.dart' show TableGeometryOutput;
import 'models/ocr_word.dart';

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
            if (t == kw || t == '$kw.' || t.startsWith('$kw ')) return w;
          }
        }
        return null;
      }

      final srWord = findHeader(['SR', 'S.R']);
      final partWord = findHeader(['PART', 'PRT', '1ART', 'PARI']);
      final descWord = findHeader(['DESC', 'DES', 'DSCR', 'DESCRIPTION']);
      final mrpWord = findHeader(['M.R.P', 'MRP']);
      final qtyWord = findHeader(['QTY', 'QTV']);
      final locWord = findHeader(['LOC']);
      final packWord = findHeader(['PACK', 'PKT']);
      final stockWord = findHeader(['STOCK', 'STK']);

      // Calculate column boundaries.
      // A column starts slightly to the left of its header, and ends slightly to the left of the NEXT header.
      // We use absolute fallbacks based on typical image width if a header is missing.

      final w = input.imageWidth;
      
      final rawX = <String, int>{};
      
      if (!input.hasHeader) {
        // If no header was confidently found (e.g. continuation page), enforce strict fallback columns
        rawX['SR'] = (w * 0.02).toInt();
        rawX['PART'] = (w * 0.12).toInt();
        rawX['DESC'] = (w * 0.28).toInt();
        rawX['QTY'] = (w * 0.65).toInt();
        rawX['MRP'] = (w * 0.75).toInt();
        rawX['LOC'] = (w * 0.82).toInt();
        rawX['PACK'] = (w * 0.88).toInt();
        rawX['STOCK'] = (w * 0.94).toInt();
      } else {
        rawX['SR'] = srWord != null ? srWord.left : (w * 0.02).toInt();
        rawX['PART'] = partWord != null ? partWord.left : (rawX['SR']! + (w * 0.10).toInt());
        rawX['DESC'] = descWord != null ? descWord.left : (rawX['PART']! + (w * 0.16).toInt());
        
        // We MUST define these even if not found, otherwise DESC absorbs the right side of the page
        rawX['QTY'] = qtyWord != null ? qtyWord.left : (w * 0.65).toInt();
        rawX['MRP'] = mrpWord != null ? mrpWord.left : (w * 0.75).toInt();
        rawX['LOC'] = locWord != null ? locWord.left : (w * 0.82).toInt();
        rawX['PACK'] = packWord != null ? packWord.left : (w * 0.88).toInt();
        rawX['STOCK'] = stockWord != null ? stockWord.left : (w * 0.94).toInt();
      }

      final standardOrder = ['SR', 'PART', 'DESC', 'QTY', 'MRP', 'LOC', 'PACK', 'STOCK'];
      final activeKeys = standardOrder.where((k) => rawX.containsKey(k)).toList();
      
      // Ensure strictly ordered in case OCR jitter misplaced a bounding box
      for (int i = 1; i < activeKeys.length; i++) {
        final prevKey = activeKeys[i - 1];
        final currKey = activeKeys[i];
        if (rawX[currKey]! <= rawX[prevKey]!) {
          rawX[currKey] = rawX[prevKey]! + 50;
        }
      }

      // Create the column boundaries dynamically
      final columns = <ColumnDef>[];
      for (int i = 0; i < activeKeys.length; i++) {
        final key = activeKeys[i];
        final leftX = (i == 0) ? 0 : rawX[key]! - 5;
        final rightX = (i == activeKeys.length - 1) ? w : rawX[activeKeys[i + 1]]! - 5;
        columns.add(ColumnDef(key: key, leftX: leftX, rightX: rightX));
      }

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
