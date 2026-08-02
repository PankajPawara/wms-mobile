import 'models/pipeline_result.dart';
import 'models/pipeline_stage.dart';
import 'models/ocr_word.dart';
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

class _ProjectedWord {
  final OcrWord word;
  final double baseY;

  _ProjectedWord(this.word, this.baseY);
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
  // Strict version for the combined right-side string.
  static final _locRegex = RegExp(r'\b([0-9]{3}[A-Z])\b');

  // Fuzzy version: 3 digits + any alphanum — catches OCR letter substitutions
  // e.g. "073J" misread as "0733", "007U" misread as "0071".
  static final _locFuzzyRegex = RegExp(r'\b([0-9]{3}[A-Z0-9])\b');

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
      // STEP 2 — Project all words to Base Y (X = 0) and Cluster
      // -----------------------------------------------------------------------
      final tableWords = input.gridGeometry.tableGeometry.allWords.where((w) {
        return w.top >= input.gridGeometry.tableGeometry.topY && w.bottom <= input.gridGeometry.tableGeometry.bottomY;
      }).toList();

      final allProjected = <_ProjectedWord>[];
      for (final w in tableWords) {
        // Skip obvious vertical pipes
        if (w.text == '|' || w.text == 'I' || w.text == 'l' || w.text == '1' || w.text == '!') {
          if ((w.bottom - w.top) > 1.2 * (w.right - w.left)) {
            continue;
          }
        }
        final cx = (w.left + w.right) / 2.0;
        final baseY = w.top - (cx * globalSlope);
        allProjected.add(_ProjectedWord(w, baseY));
      }

      // Sort all words globally by their flattened baseY
      allProjected.sort((a, b) => a.baseY.compareTo(b.baseY));

      // 1D Clustering
      final rowClusters = <List<_ProjectedWord>>[];
      List<_ProjectedWord> currentCluster = [];
      
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
      // STEP 3 — Assemble Rows using Strict Semantic Rules
      // -----------------------------------------------------------------------
      final rows = <PartRow>[];

      for (final cluster in rowClusters) {
        // Sort words in the cluster left-to-right
        cluster.sort((a, b) => a.word.left.compareTo(b.word.left));

        // Combine into full text
        String fullText = cluster.map((cw) => cw.word.text).join(' ');

        // Fix common OCR fragmentation (e.g. "51110 - KWP - 900" -> "51110-KWP-900")
        fullText = fullText.replaceAll(RegExp(r'\s*-\s*'), '-');
        // Clean up stray pipes
        fullText = fullText.replaceAll(RegExp(r'[|!]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

        if (fullText.isEmpty) continue;
        if (_isNoiseLine(fullText, '')) continue;

        String sr = '';
        String partNo = '';
        String desc = '';
        String mrp = '';
        String qty = '';
        String loc = '';
        String pack = '';
        String stock = '';

        // 1. Try to find the Part Number (Strict anchor)
        final partMatch = _hondaPartRegex.firstMatch(fullText);

        if (partMatch != null) {
          partNo = partMatch.group(1)!;
          
          final partIndex = partMatch.start;
          final partEndIndex = partMatch.end;
          
          sr = fullText.substring(0, partIndex).replaceAll(RegExp(r'[^0-9]'), '').trim();
          
          final afterPart = fullText.substring(partEndIndex).trim();
          
          // 2. Find MRP in the text after Part Number
          final mrpMatch = RegExp(r'\d[\d,]*\.\d{2}').firstMatch(afterPart);
          
          if (mrpMatch != null) {
            mrp = mrpMatch.group(0)!;
            final mrpIndex = mrpMatch.start;
            final mrpEndIndex = mrpMatch.end;
            
            desc = afterPart.substring(0, mrpIndex).trim();
            final afterMrp = afterPart.substring(mrpEndIndex).trim();
            
            // 3. Find LOC in the text after MRP
            final locMatch = _locRegex.firstMatch(afterMrp) ?? _locFuzzyRegex.firstMatch(afterMrp);
            
            if (locMatch != null) {
              loc = locMatch.group(1)!;
              final locIndex = locMatch.start;
              final locEndIndex = locMatch.end;
              
              qty = afterMrp.substring(0, locIndex).replaceAll(RegExp(r'[^0-9]'), '').trim();
              
              final afterLoc = afterMrp.substring(locEndIndex).trim();
              final stockTokens = afterLoc.split(' ').where((t) => RegExp(r'\d').hasMatch(t)).toList();
              
              if (stockTokens.isNotEmpty) {
                if (stockTokens.length >= 2) {
                  pack = stockTokens[0].replaceAll(RegExp(r'[^0-9]'), '');
                  stock = stockTokens[1].replaceAll(RegExp(r'[^0-9]'), '');
                } else {
                  stock = stockTokens[0].replaceAll(RegExp(r'[^0-9]'), '');
                }
              }
            } else {
              // No LOC, just check for QTY
              final qtyMatch = RegExp(r'\b([1-9]\d?)\b').firstMatch(afterMrp);
              if (qtyMatch != null) {
                qty = qtyMatch.group(1)!;
              }
            }
          } else {
            // No MRP, everything after part is description
            desc = afterPart;
          }
        } else {
          // No Strict Part Number. Check if there's an MRP, which implies it's a sub-row or description row
          final mrpMatch = RegExp(r'\d[\d,]*\.\d{2}').firstMatch(fullText);
          if (mrpMatch != null) {
             mrp = mrpMatch.group(0)!;
             desc = fullText.substring(0, mrpMatch.start).trim();
             // Just ignore QTY/LOC for sub-rows unless we need them
          } else {
             // Treat the entire row as description (e.g. multi-line desc)
             desc = fullText;
          }
        }

        // Clean description
        desc = _cleanDescription(desc);

        if (partNo.isEmpty && desc.isEmpty && mrp.isEmpty) continue;

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
  // Clean description: remove leading/trailing pipes, star-wrapped words,
  // and other OCR artefacts that bleed in from adjacent columns.
  // ---------------------------------------------------------------------------
  static String _cleanDescription(String raw) {
    return raw
        .replaceAll(RegExp(r'^[|*\s]+'), '')   // leading pipes, stars, spaces
        .replaceAll(RegExp(r'[|*\s]+$'), '')   // trailing pipes, stars, spaces
        .replaceAll(RegExp(r'\*[^*]*\*'), '')  // *SHINE B* style star-wrapped tokens
        .replaceAll(RegExp(r'\s+'), ' ')        // collapse multiple spaces
        .trim();
  }

  static bool _isNoiseLine(String partNo, String desc) {
    final combined = '$partNo $desc'.toUpperCase();
    return combined.contains('PICKING LIST') ||
        combined.contains('NET AMOUNT') ||
        combined.contains('TOTAL') ||
        combined.contains('MEMO NO');
  }
}
