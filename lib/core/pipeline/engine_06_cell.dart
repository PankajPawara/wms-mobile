import 'models/pipeline_result.dart';
import 'models/pipeline_stage.dart';
import 'engine_05_grid.dart' show GridGeometryOutput;


class CellData {
  final String text;
  final int topY;
  final int bottomY;

  CellData({
    required this.text,
    required this.topY,
    required this.bottomY,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'topY': topY,
    'bottomY': bottomY,
  };
}

class CellAssignmentOutput {
  final GridGeometryOutput gridGeometry;
  // Map of column Key to list of cells in that column
  final Map<String, List<CellData>> columns;

  CellAssignmentOutput({
    required this.gridGeometry,
    required this.columns,
  });

  Map<String, dynamic> toJson() {
    return {
      'gridGeometry': gridGeometry.toJson(),
      'columns': columns.map((key, value) => MapEntry(key, value.map((c) => c.toJson()).toList())),
    };
  }
}

class Engine06CellAssignment {
  static Future<PipelineResult<CellAssignmentOutput>> assign(GridGeometryOutput input) async {
    final stopwatch = Stopwatch()..start();
    final errors = <String>[];

    try {
      final columns = <String, List<CellData>>{};
      for (final col in input.columns) {
        columns[col.key] = [];
      }

      // 1. Filter words to only those inside the table bounds (between topY and bottomY)
      final tableWords = input.tableGeometry.allWords.where((w) {
        return w.top >= input.tableGeometry.topY && w.bottom <= input.tableGeometry.bottomY;
      }).toList();

      // 2. Assign each word to a column based on its center X coordinate
      for (final w in tableWords) {
        // Skip completely empty words
        if (w.text.trim().isEmpty) continue;
        
        // Skip obvious vertical pipe separators
        if (w.text == '|' || w.text == 'I' || w.text == 'l' || w.text == '1' && (w.right - w.left) < 10) {
           // It's just a separator line artifact, ignore it
           // (Actually, '1' could be QTY 1, so we only ignore if it's super skinny, but let's just strip '|' for now)
           if (w.text == '|') continue;
        }

        int cx = (w.left + w.right) ~/ 2;
        
        String assignedColKey = input.columns.last.key; // default to last column if it overflows
        for (final col in input.columns) {
          if (cx >= col.leftX && cx <= col.rightX) {
            assignedColKey = col.key;
            break;
          }
        }

        columns[assignedColKey]!.add(CellData(
          text: w.text,
          topY: w.top,
          bottomY: w.bottom,
        ));
      }

      // 3. For the DESCRIPTION column, there might be multiple words on the same horizontal line.
      // We should group cells that are vertically aligned (same physical text line) within the same column.
      final consolidatedColumns = <String, List<CellData>>{};
      
      for (final entry in columns.entries) {
        final colKey = entry.key;
        final rawCells = entry.value;
        
        if (rawCells.isEmpty) {
          consolidatedColumns[colKey] = [];
          continue;
        }

        // Sort top-to-bottom
        rawCells.sort((a, b) => a.topY.compareTo(b.topY));
        
        final mergedCells = <CellData>[];
        List<CellData> currentRow = [rawCells.first];

        for (int i = 1; i < rawCells.length; i++) {
          final current = rawCells[i];
          final rowTopY = currentRow.first.topY;
          final rowBottomY = currentRow.last.bottomY; // using max bottom of row could be better, but simple average is fine
          final rowCenterY = (rowTopY + rowBottomY) ~/ 2;
          final currentCenterY = (current.topY + current.bottomY) ~/ 2;

          // If vertically aligned within 20 pixels, it's the same physical text line
          if ((currentCenterY - rowCenterY).abs() < 20) {
            currentRow.add(current);
          } else {
            // Join the words
            mergedCells.add(CellData(
              text: currentRow.map((c) => c.text).join(' '),
              topY: currentRow.first.topY,
              bottomY: currentRow.last.bottomY, // approximate
            ));
            currentRow = [current];
          }
        }
        
        if (currentRow.isNotEmpty) {
          mergedCells.add(CellData(
            text: currentRow.map((c) => c.text).join(' '),
            topY: currentRow.first.topY,
            bottomY: currentRow.last.bottomY,
          ));
        }

        consolidatedColumns[colKey] = mergedCells;
      }

      stopwatch.stop();

      return PipelineResult(
        data: CellAssignmentOutput(
          gridGeometry: input,
          columns: consolidatedColumns,
        ),
        timingMs: stopwatch.elapsedMilliseconds,
        confidence: 1.0,
        stage: PipelineStage.cell,
        errors: errors,
      );

    } catch (e) {
      stopwatch.stop();
      return PipelineResult.failure(
        stage: PipelineStage.cell,
        reason: e.toString(),
        timingMs: stopwatch.elapsedMilliseconds,
      );
    }
  }
}
