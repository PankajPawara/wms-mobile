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
      // PIPES ALGORITHM: Use vertical separators (|) to define column boundaries
      final w = input.imageWidth;
      final pipes = <OcrWord>[];
      
      // 1. Find all vertical pipe-like characters in the table area
      for (final word in input.allWords) {
        if (word.top < input.topY || word.bottom > input.bottomY) continue;
        
        final text = word.text.trim();
        if (text == '|' || text == 'I' || text == 'l' || text == '1' || text == '!') {
          // Verify it is tall and narrow
          if ((word.bottom - word.top) > 1.2 * (word.right - word.left)) {
            pipes.add(word);
          }
        }
      }

      // 2. Cluster pipes by their X coordinates
      pipes.sort((a, b) => ((a.left + a.right) ~/ 2).compareTo((b.left + b.right) ~/ 2));
      
      final clusters = <List<OcrWord>>[];
      for (final p in pipes) {
        final cx = (p.left + p.right) ~/ 2;
        bool added = false;
        for (final c in clusters) {
          final avgX = c.map((w) => (w.left + w.right) ~/ 2).reduce((a, b) => a + b) ~/ c.length;
          // If within 40 pixels (about 2.5% of width), group them
          if ((cx - avgX).abs() < 40) {
            c.add(p);
            added = true;
            break;
          }
        }
        if (!added) {
          clusters.add([p]);
        }
      }

      // Keep clusters that have at least 3 pipes (forming a true column divider)
      clusters.removeWhere((c) => c.length < 3);

      // Get median X coordinate for each valid cluster
      final dividerXs = clusters.map((c) {
        final xs = c.map((w) => (w.left + w.right) ~/ 2).toList()..sort();
        return xs[xs.length ~/ 2];
      }).toList()..sort();

      // 3. Map detected dividers to expected columns using proportional fallbacks
      final expectedXs = {
        'SR_PART': w * 0.12,
        'PART_DESC': w * 0.28,
        'DESC_MRP': w * 0.65,
        'MRP_QTY': w * 0.75,
        'QTY_LOC': w * 0.82,
        'LOC_PACK': w * 0.88,
        'PACK_STOCK': w * 0.92,
      };

      final actualXs = <String, int>{};
      for (final entry in expectedXs.entries) {
        final expectedX = entry.value;
        int? closestX;
        double minDiff = w * 0.06; // Max tolerance 6% of page width
        
        for (final x in dividerXs) {
          final diff = (x - expectedX).abs();
          if (diff < minDiff) {
            minDiff = diff;
            closestX = x;
          }
        }
        
        actualXs[entry.key] = closestX ?? expectedX.toInt();
      }

      // 4. Construct Column Definitions
      final activeKeys = ['SR', 'PART', 'DESC', 'MRP', 'QTY', 'LOC', 'PACK', 'STOCK'];
      
      final rawX = <String, int>{
        'SR': 0,
        'PART': actualXs['SR_PART']!,
        'DESC': actualXs['PART_DESC']!,
        'MRP': actualXs['DESC_MRP']!,
        'QTY': actualXs['MRP_QTY']!,
        'LOC': actualXs['QTY_LOC']!,
        'PACK': actualXs['LOC_PACK']!,
        'STOCK': actualXs['PACK_STOCK']!,
      };

      final columns = <ColumnDef>[];
      for (int i = 0; i < activeKeys.length; i++) {
        final key = activeKeys[i];
        final leftX = rawX[key]!;
        final rightX = (i == activeKeys.length - 1) ? w : rawX[activeKeys[i + 1]]!;
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
