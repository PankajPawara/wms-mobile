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

  static ({Map<String, dynamic> dbPart, int startRaw, int endRaw})? findBestSubstringMatch(String rawText) {
    if (_parts == null || rawText.isEmpty) return null;
    
    List<int> rawIndices = [];
    String normalized = "";
    for (int i = 0; i < rawText.length; i++) {
      if (RegExp(r'[A-Z0-9]').hasMatch(rawText[i])) {
        normalized += rawText[i];
        rawIndices.add(i);
      }
    }

    if (normalized.length < 5) return null;
    
    Map<String, dynamic>? bestMatch;
    int bestDist = 999;
    int bestStart = 0;
    int bestEnd = 0;
    
    for (final p in _parts!) {
      final b = p['b'] as String;
      if (b.length < 5) continue;
      
      for (int start = 0; start < normalized.length; start++) {
        int minLen = b.length > 3 ? b.length - 3 : 1;
        int maxLen = normalized.length - start < b.length + 3 ? normalized.length - start : b.length + 3;
        
        for (int len = minLen; len <= maxLen; len++) {
          int end = start + len;
          int cost = _levenshtein(b, normalized.substring(start, end));
          int maxDist = b.length >= 10 ? 4 : 2;
          if (cost < bestDist && cost <= maxDist) {
            bestDist = cost;
            bestStart = start;
            bestEnd = end;
            bestMatch = p;
          }
        }
      }
    }
    
    if (bestMatch == null) return null;
    
    int actualRawStart = rawIndices[bestStart];
    int actualRawEnd = bestEnd > 0 ? rawIndices[bestEnd - 1] + 1 : 0;
    
    return (dbPart: bestMatch, startRaw: actualRawStart, endRaw: actualRawEnd);
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
        String correctedSr = row.sr;
        String correctedDesc = row.description;
        bool correctedFromDb = false;

        // Strip dashes and spaces to form a barcode for lookup
        final barcode = correctedPartNo.replaceAll(RegExp(r'[^A-Z0-9]'), '');
        Map<String, dynamic>? dbMatch;
        
        if (barcode.isNotEmpty) {
          // 1. Try exact match
          dbMatch = PartsDatabase.findByBarcode(barcode);
          
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
        }

        // 4. If still no match (or if partNo was completely empty due to grid layout issues),
        // try to find the barcode inside the combined text of the row.
        if (dbMatch == null) {
          final rawRowText = row.sr + " " + row.partNo + " " + row.description;
          final substringMatch = PartsDatabase.findBestSubstringMatch(rawRowText);
          
          if (substringMatch != null) {
             dbMatch = substringMatch.dbPart;
             // Trim part number out of SR and DESC
             correctedSr = rawRowText.substring(0, substringMatch.startRaw).replaceAll(RegExp(r'[^0-9]'), '').trim();
             correctedDesc = rawRowText.substring(substringMatch.endRaw).replaceAll(RegExp(r'^[-\s\|]+'), '').trim();
          }
        }

        // If we found a match, apply corrections
        if (dbMatch != null) {
          correctedPartNo = dbMatch['p'] as String; // The fully formatted part number with dashes
          if (correctedLocation.isEmpty) {
             correctedLocation = dbMatch['l'] as String;
          }
          correctedFromDb = true;
        }

        correctedRows.add(PartRow(
          sr: correctedSr,
          partNo: correctedPartNo,
          description: correctedDesc,
          mrp: row.mrp,
          qty: row.qty,
          location: correctedLocation,
          pack: row.pack,
          stock: row.stock,
          isDbVerified: correctedFromDb,
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
