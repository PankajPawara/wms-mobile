import 'models/pipeline_result.dart';
import 'models/pipeline_stage.dart';
import 'models/ocr_word.dart';
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
  static Future<PipelineResult<RowBuilderOutput>> build(TableGeometryOutput input) async {
    final stopwatch = Stopwatch()..start();
    final errors = <String>[];

    try {
      // Filter words strictly inside the table bounds
      final tableWords = input.allWords.where((w) {
        return w.top >= input.topY && w.bottom <= input.bottomY;
      }).toList();

      // 1. Cluster words into horizontal lines by Y-coordinate
      tableWords.sort((a, b) => a.top.compareTo(b.top));
      
      final lines = <List<OcrWord>>[];
      if (tableWords.isNotEmpty) {
        List<OcrWord> currentLine = [tableWords.first];
        for (int i = 1; i < tableWords.length; i++) {
          final w = tableWords[i];
          final lineAvgY = currentLine.map((e) => (e.top + e.bottom) / 2).reduce((a, b) => a + b) / currentLine.length;
          final wordAvgY = (w.top + w.bottom) / 2;
          
          if ((wordAvgY - lineAvgY).abs() < 15) { // 15px threshold for same line
            currentLine.add(w);
          } else {
            lines.add(currentLine);
            currentLine = [w];
          }
        }
        if (currentLine.isNotEmpty) {
          lines.add(currentLine);
        }
      }

      final rows = <PartRow>[];
      
      // MRP is a whole number ending in .00 but OCR might return .0, .OO, etc. with attached noise.
      final mrpRegex = RegExp(r'^[\d,]+[\.,][0O\d]{1,2}[A-Za-z]?$');
      
      // Location uses patterns like 001A, 206D, BOX-001, etc.
      final locRegex = RegExp(r'^([O0-9]{3}[A-Z]|BOX-?\d{3})[A-Za-z\.]?$', caseSensitive: false);
      
      final qtyRegex = RegExp(r'^[O0-9]{1,4}[A-Za-z]?$', caseSensitive: false);

      for (final line in lines) {
        // Sort words strictly left-to-right
        line.sort((a, b) => a.left.compareTo(b.left));
        
        String fullLine = line.map((w) => w.text).join(' ');
        
        final locRegex = RegExp(r'\b([O0-9]{3}[A-Za-z]|BOX\s*-?\s*\d{3})[A-Za-z\.]?\s*$', caseSensitive: false);
        final qtyRegex = RegExp(r'\s+([O0-9]{1,4}[A-Za-z]?)\s*$');
        final mrpRegex = RegExp(r'\s+([\d,]+[\.,][0O\d]{1,2}[A-Za-z]?)\s*$');
        final srRegex = RegExp(r'^\s*([0-9]{1,3})\s+');

        String loc = '';
        String qty = '';
        String mrp = '';
        String sr = '';

        // Extract Loc
        final locMatch = locRegex.firstMatch(fullLine);
        if (locMatch != null) {
          loc = locMatch.group(1)!;
          fullLine = fullLine.substring(0, locMatch.start);
        }

        // Extract QTY
        final qtyMatch = qtyRegex.firstMatch(fullLine);
        if (qtyMatch != null) {
          qty = qtyMatch.group(1)!;
          fullLine = fullLine.substring(0, qtyMatch.start);
        }

        // Extract MRP
        final mrpMatch = mrpRegex.firstMatch(fullLine);
        if (mrpMatch != null) {
          mrp = mrpMatch.group(1)!;
          fullLine = fullLine.substring(0, mrpMatch.start);
        }
        
        // Extract SR
        final srMatch = srRegex.firstMatch(fullLine);
        if (srMatch != null) {
          sr = srMatch.group(1)!;
          fullLine = fullLine.substring(srMatch.end);
        }

        String partNo = fullLine.trim();
        
        bool hasValidMrp = mrp.isNotEmpty;
        bool hasValidLoc = loc.isNotEmpty;
        
        // A valid part number usually contains a sequence of digits (e.g. 5 digits) or alphanumeric with hyphens.
        bool looksLikePartNo = RegExp(r'\d{4,}').hasMatch(partNo) || RegExp(r'[A-Z0-9]+-[A-Z0-9]+').hasMatch(partNo);
        
        // Reject noise lines (e.g., headers, dates) that don't have MRP, LOC, and don't look like a part number.
        // Also reject if it's explicitly a known noise word.
        bool isNoise = partNo.toUpperCase().contains('MEMO') || 
                       partNo.toUpperCase().contains('DATE') || 
                       partNo.toUpperCase().contains('TOTAL') ||
                       partNo.toUpperCase().contains('AMOUNT');

        if (!isNoise && (hasValidMrp || hasValidLoc || looksLikePartNo)) {
          rows.add(PartRow(
            sr: sr,
            partNo: partNo,
            description: '',
            mrp: mrp,
            qty: qty,
            location: loc,
            pack: '',
            stock: '',
          ));
        }
      }

      stopwatch.stop();
      return PipelineResult(
        data: RowBuilderOutput(
          tableGeometry: input,
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
