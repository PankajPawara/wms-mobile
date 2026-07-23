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
      
      final mrpRegex = RegExp(r'^[\d,]+[\.,]\d{2}[A-Za-z]?$');
      final locRegex = RegExp(r'^([O0-9]{3}[A-Z]|BOX-?\d{3})$', caseSensitive: false);
      final qtyRegex = RegExp(r'^[O0-9]{1,4}$', caseSensitive: false);

      for (final line in lines) {
        // Sort words strictly left-to-right
        line.sort((a, b) => a.left.compareTo(b.left));
        
        String mrp = '';
        String loc = '';
        String qty = '';
        
        int mrpIndex = -1;
        int locIndex = -1;
        int qtyIndex = -1;
        
        // Scan right-to-left for Location
        for (int i = line.length - 1; i >= 0; i--) {
          final text = line[i].text.replaceAll(' ', '').toUpperCase();
          if (locRegex.hasMatch(text)) {
            loc = text;
            locIndex = i;
            break;
          }
        }
        
        // Scan left-to-right for MRP (take the first match, avoiding AMOUNT on the far right)
        // Skip index 0 as it's definitely Part No.
        int mrpSearchEnd = locIndex != -1 ? locIndex : line.length;
        for (int i = 1; i < mrpSearchEnd; i++) {
          final text = line[i].text.replaceAll(' ', '').toUpperCase();
          if (mrpRegex.hasMatch(text)) {
            mrp = text;
            mrpIndex = i;
            break;
          }
        }
        
        // Find QTY between MRP and LOC
        if (mrpIndex != -1) {
           for (int i = mrpIndex + 1; i < mrpSearchEnd; i++) {
             final text = line[i].text.replaceAll(' ', '').toUpperCase();
             if (qtyRegex.hasMatch(text) && text != '0' && text != 'O') {
               qty = text;
               qtyIndex = i;
               break;
             }
           }
        }
        
        // The prefix words are everything before MRP (or before LOC if no MRP)
        int splitIndex = mrpIndex != -1 ? mrpIndex : (locIndex != -1 ? locIndex : line.length);
        final prefixWords = line.sublist(0, splitIndex).map((w) => w.text).toList();
        
        if (prefixWords.isEmpty) continue;
        
        String sr = '';
        
        // SR is usually the first number if it's isolated and small
        if (RegExp(r'^\d{1,3}$').hasMatch(prefixWords[0])) {
          sr = prefixWords[0];
          prefixWords.removeAt(0);
        }
        
        // We will put all remaining words into partNo, and let CandidateGenerator figure it out.
        String partNo = prefixWords.join(' ');
        
        if (partNo.isNotEmpty) {
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
