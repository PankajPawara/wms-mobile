import 'dart:convert';
import 'package:flutter/services.dart';
import 'engine_07_row.dart' show PartRow, RowBuilderOutput;
import 'models/pipeline_result.dart';
import 'models/pipeline_stage.dart';

class PartsDatabase {
  static List<Map<String, dynamic>>? _parts;

  static Future<void> init() async {
    if (_parts != null) return;
    try {
      final jsonString = await rootBundle.loadString('assets/data/parts_db.json');
      final List<dynamic> decoded = jsonDecode(jsonString);
      _parts = decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      print('Error loading parts_db.json: $e');
      _parts = [];
    }
  }

  // Exact match by barcode (part number without dashes)
  static Map<String, dynamic>? findByBarcode(String barcode) {
    if (_parts == null) return null;
    final normalized = barcode.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    try {
      return _parts!.firstWhere((p) => p['b'] == normalized);
    } catch (e) {
      return null;
    }
  }

  // Fuzzy match (allow up to 2 character differences)
  static Map<String, dynamic>? fuzzyMatch(String rawPart) {
    if (_parts == null) return null;
    final normalized = rawPart.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (normalized.length < 5) return null;

    Map<String, dynamic>? bestMatch;
    int bestDist = 999;

    for (final p in _parts!) {
      final b = p['b'] as String;
      if ((b.length - normalized.length).abs() > 2) continue; // skip if lengths differ too much

      final dist = _levenshtein(normalized, b);
      if (dist < bestDist && dist <= 2) {
        bestDist = dist;
        bestMatch = p;
      }
    }
    return bestMatch;
  }

  static int _levenshtein(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    List<int> v0 = List<int>.filled(b.length + 1, 0);
    List<int> v1 = List<int>.filled(b.length + 1, 0);
    for (int i = 0; i <= b.length; i++) v0[i] = i;
    for (int i = 0; i < a.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < b.length; j++) {
        int cost = (a[i] == b[j]) ? 0 : 1;
        v1[j + 1] = cost == 0 ? v0[j] : (v1[j] < v0[j + 1] ? (v1[j] < v0[j] ? v1[j] : v0[j]) : (v0[j + 1] < v0[j] ? v0[j + 1] : v0[j])) + 1;
      }
      for (int j = 0; j <= b.length; j++) v0[j] = v1[j];
    }
    return v0[b.length];
  }
}

class Engine08DatabaseMatch {
  static Future<PipelineResult<RowBuilderOutput>> validateAndCorrect(RowBuilderOutput input) async {
    final stopwatch = Stopwatch()..start();
    final errors = <String>[];

    try {
      await PartsDatabase.init();

      final correctedRows = <PartRow>[];

      for (final row in input.rows) {
        String correctedPartNo = row.partNo;
        String correctedLocation = row.location;
        bool correctedFromDb = false;

        // Strip dashes and spaces to form a barcode for lookup
        final barcode = correctedPartNo.replaceAll(RegExp(r'[^A-Z0-9]'), '');
        
        if (barcode.isNotEmpty) {
          // 1. Try exact match
          var dbMatch = PartsDatabase.findByBarcode(barcode);
          
          // 2. Try common OCR mistake replacement if no exact match
          if (dbMatch == null) {
             final fixO = barcode.replaceAll('O', '0');
             dbMatch = PartsDatabase.findByBarcode(fixO);
             if (dbMatch == null) {
                final fixI = barcode.replaceAll('I', '1');
                dbMatch = PartsDatabase.findByBarcode(fixI);
                if (dbMatch == null) {
                   final fixBoth = fixO.replaceAll('I', '1');
                   dbMatch = PartsDatabase.findByBarcode(fixBoth);
                }
             }
          }

          // 3. Try fuzzy match (Levenshtein distance <= 2)
          if (dbMatch == null) {
            dbMatch = PartsDatabase.fuzzyMatch(barcode);
          }

          // If we found a match, apply corrections
          if (dbMatch != null) {
            correctedPartNo = dbMatch['p'] as String; // The fully formatted part number with dashes
            // If OCR missed the location completely, or we want to trust the DB more:
            // For now, if OCR has a location, we keep it, but if empty, we fill it.
            // Or we can overwrite OCR location with DB location since DB is ground truth.
            if (correctedLocation.isEmpty) {
               correctedLocation = dbMatch['l'] as String;
            }
            correctedFromDb = true;
          }
        }

        // If partNo is still empty but we have description, we can't easily look up partNo without a full parts catalog text search.
        // We'll keep it as is.
        correctedRows.add(PartRow(
          sr: row.sr,
          partNo: correctedPartNo,
          description: row.description,
          mrp: row.mrp,
          qty: row.qty,
          location: correctedLocation,
          pack: row.pack,
          stock: row.stock,
        ));
      }

      stopwatch.stop();
      return PipelineResult(
        data: RowBuilderOutput(
          tableGeometry: input.tableGeometry,
          rows: correctedRows,
        ),
        timingMs: stopwatch.elapsedMilliseconds,
        confidence: 1.0,
        stage: PipelineStage.rowBuilder, // Using rowBuilder stage type as we're extending its output
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
