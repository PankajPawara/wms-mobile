import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/extracted_memo.dart';

import 'engine_01_acquisition.dart';
import 'engine_02_processing.dart';
import 'engine_02a_optimization.dart';
import 'engine_03_header.dart';
import 'engine_04_table_detection.dart';
import 'engine_05_grid.dart';
import 'engine_06_cell.dart';
import 'engine_07_row.dart';
import 'engine_08_database_match.dart';
import 'engine_09_gemini_ocr.dart';
import '../services/candidate_generator.dart';
import '../data/validation_data.dart';
import 'dart:math' as math;
class OcrPipelineManager {
  static Future<MemoOcrResult> process(File originalImage, AppDatabase db) async {
    // ENGINE 01
    final acqOutput = AcquisitionOutput(
      originalImage: originalImage,
      widthPx: 0,
      heightPx: 0,
      fileSizeMB: originalImage.lengthSync() / (1024 * 1024),
      source: 'camera',
    );

    // ENGINE 02
    final e02Result = await Engine02Processing.processRaw(acqOutput);
    if (!e02Result.isSuccess) throw Exception('Engine 02 Failed: ${e02Result.errors}');

    // ENGINE 02A
    final e02aResult = await Engine02aOptimization.optimize(e02Result.data!);
    if (!e02aResult.isSuccess) throw Exception('Engine 02A Failed: ${e02aResult.errors}');

    // ENGINE 03
    final e03Result = await Engine03Header.extract(e02aResult.data!);
    if (!e03Result.isSuccess) throw Exception('Engine 03 Failed: ${e03Result.errors}');
    
    // ENGINE 04
    final e04Result = await Engine04TableDetection.detect(e02aResult.data!);
    if (!e04Result.isSuccess) throw Exception('Engine 04 Failed: ${e04Result.errors}');

    // ENGINE 05
    final e05Result = await Engine05GridSystem.generate(e04Result.data!);
    if (!e05Result.isSuccess) throw Exception('Engine 05 Failed: ${e05Result.errors}');

    // ENGINE 06: Map cells to Grid
    
    final e06Result = await Engine06CellAssignment.assign(e05Result.data!);
    if (!e06Result.isSuccess) throw Exception('Engine 06 Failed: ${e06Result.errors}');

    // ENGINE 07
    
    final e07Result = await Engine07RowBuilder.build(e06Result.data!);
    if (!e07Result.isSuccess) throw Exception('Engine 07 Failed: ${e07Result.errors}');

    // ENGINE 08 (Database Validation)
    
    final e08Result = await Engine08DatabaseMatch.validateAndCorrect(e07Result.data!);
    if (!e08Result.isSuccess) throw Exception('Engine 08 Failed: ${e08Result.errors}');

    // ENGINE 09 — GEMINI FALLBACK
    // If less than 50% of rows are DB-verified by ML Kit, the image quality
    // is too poor for on-device OCR. Route to Gemini for superior extraction.
    final e08Rows = e08Result.data!.rows;
    final verifiedCount = e08Rows.where((r) => r.isDbVerified).length;
    final totalCount = e08Rows.length;
    final matchRate = totalCount > 0 ? verifiedCount / totalCount : 0.0;

    if (kDebugMode) {
      debugPrint('[Pipeline] E08 match rate: ${(matchRate * 100).toStringAsFixed(0)}% ($verifiedCount/$totalCount verified)');
    }

    if (matchRate < 0.5) {
      debugPrint('[Pipeline] Match rate too low — triggering ENGINE 09 Gemini OCR fallback...');
      final e09Result = await Engine09GeminiOcr.extractFromImage(
        e02aResult.data!,
        e04Result.data!,
      );
      if (e09Result.isSuccess && e09Result.data!.rows.isNotEmpty) {
        // Run E08 again on Gemini's output to get DB-verified flags
        final e08GeminiResult = await Engine08DatabaseMatch.validateAndCorrect(e09Result.data!);
        if (e08GeminiResult.isSuccess) {
          if (kDebugMode) {
            final g08Rows = e08GeminiResult.data!.rows;
            final gVerified = g08Rows.where((r) => r.isDbVerified).length;
            debugPrint('[Pipeline] Gemini E08 match rate: ${(gVerified / g08Rows.length * 100).toStringAsFixed(0)}% ($gVerified/${g08Rows.length}).');
            debugPrint('\n=== OCR PIPELINE OUTPUT (E09 Gemini) ===\n');
            debugPrint(const JsonEncoder.withIndent('  ').convert({
              'source': 'gemini-2.5-flash',
              'E09': e09Result.data!.toJson(),
              'E08_Gemini': e08GeminiResult.data!.toJson(),
            }));
            debugPrint('\n=========================================\n');
          }
          // Re-assign rows from Gemini path
          e08Result.data!.rows
            ..clear()
            ..addAll(e08GeminiResult.data!.rows);
        }
      } else {
        debugPrint('[Pipeline] Gemini fallback also failed — using ML Kit results.');
      }
    } else {
      if (kDebugMode) {
        debugPrint('\n=== OCR PIPELINE OUTPUT (ML Kit) ===\n');
        debugPrint(const JsonEncoder.withIndent('  ').convert({
          'source': 'ml-kit',
          'E07': e07Result.data!.toJson(),
          'E08': e08Result.data!.toJson(),
        }));
        debugPrint('\n=====================================\n');
      }
    }

    // Map Engine 03 output to ExtractedMemoHeader
    final headerData = e03Result.data!.headerData;
    String customerName = headerData['customerName'] ?? '';
    String area = headerData['area'] ?? '';
    String? subArea;

    // Sub-Area Identification
    final normArea = area.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    String? matchedMainArea;
    
    // Find closest Main Area
    for (var mainArea in ValidationData.areaSchedules.keys) {
      final normMainArea = mainArea.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
      if (normArea.contains(normMainArea) || _levenshtein(normArea, normMainArea) <= 2) {
        matchedMainArea = mainArea;
        break;
      }
    }

    if (matchedMainArea != null) {
      final subAreas = ValidationData.areaSchedules[matchedMainArea]!;
      for (var sub in subAreas) {
        final subWords = sub.toUpperCase().split(RegExp(r'[^A-Z]')).where((w) => w.isNotEmpty).toList();
        final custWords = customerName.toUpperCase().split(RegExp(r'[^A-Z]')).where((w) => w.isNotEmpty).toList();
        
        for (int i = 0; i <= custWords.length - subWords.length; i++) {
          bool match = true;
          for (int j = 0; j < subWords.length; j++) {
             final maxDist = subWords[j].length >= 5 ? 2 : (subWords[j].length >= 3 ? 1 : 0);
             if (_levenshtein(custWords[i+j], subWords[j]) > maxDist) {
               match = false;
               break;
             }
          }
          if (match) {
            subArea = sub;
            // Correct the sub-area spelling in the customer name if it was misspelled
            for (int j = 0; j < subWords.length; j++) {
               custWords[i+j] = subWords[j];
            }
            customerName = custWords.join(' ');
            break;
          }
        }
        if (subArea != null) break;
      }
    }

    final header = ExtractedMemoHeader(
      customerName: customerName,
      area: area,
      memoNumber: headerData['memoNo'] ?? '',
      subArea: subArea,
    );

    // Map Engine 07 output to ExtractedMemoItems and Validate with DB
    final candidateGenerator = CandidateGenerator(db);
    await candidateGenerator.init();
    
    final List<ExtractedMemoItem> finalItems = [];
    String rawOcrDump = '--- Header Raw Text ---\n${e03Result.data!.rawWords.map((w) => w.text).join(' ')}\n\n';
    
    for (var r in e08Result.data!.rows) {
      if (r.partNo.trim().isEmpty) continue;
      
      final mrp = double.tryParse(r.mrp.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
      final qty = int.tryParse(r.qty.replaceAll(RegExp(r'\D'), '')) ?? 1;
      final pack = int.tryParse(r.pack.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final stock = int.tryParse(r.stock.replaceAll(RegExp(r'\D'), '')) ?? 0;

      // Part Code OCR Correction
      String correctedPartNo = r.partNo.toUpperCase();
      for (var code in ValidationData.validModelCodes) {
         final mistakeO = code.replaceAll('0', 'O');
         final mistakeI = code.replaceAll('1', 'I');
         final mistakeBoth = mistakeO.replaceAll('1', 'I');

         if (mistakeBoth != code && correctedPartNo.contains(mistakeBoth)) {
            correctedPartNo = correctedPartNo.replaceAll(mistakeBoth, code);
         } else {
           if (mistakeO != code && correctedPartNo.contains(mistakeO)) {
              correctedPartNo = correctedPartNo.replaceAll(mistakeO, code);
           }
           if (mistakeI != code && correctedPartNo.contains(mistakeI)) {
              correctedPartNo = correctedPartNo.replaceAll(mistakeI, code);
           }
         }
      }

      final prefixWords = correctedPartNo.split(' ').where((s) => s.isNotEmpty).toList();
      if (prefixWords.isEmpty) continue;
      
      final item = await candidateGenerator.findBestMatchFromPhrase(
        phraseWords: prefixWords,
        ocrDescription: r.description.trim(),
        mrp: mrp,
        qty: qty,
        location: r.location.trim(),
        pack: pack,
        stock: stock,
      );
      
      finalItems.add(item);
      rawOcrDump += 'Row -> SR: ${r.sr} | RAW PREFIX: ${r.partNo} | MRP: ${r.mrp} | QTY: ${r.qty} | LOC: ${r.location}\n';
    }

    if (finalItems.isEmpty) {
      throw Exception('NO_HEADER_DETECTED: No valid rows were found.');
    }

    final result = MemoOcrResult(
      header: header,
      items: finalItems,
      rawOcrDump: rawOcrDump,
      imagePath: originalImage.path,
    );
    
    if (kDebugMode) {
      debugPrint('\n=== OCR PIPELINE OUTPUT ===\n');
      debugPrint(const JsonEncoder.withIndent('  ').convert({
        'E07': e07Result.data!.toJson(),
      }));
      debugPrint('\n===========================\n');
    }

    return result;
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
        v1[j + 1] = math.min(math.min(v1[j] + 1, v0[j + 1] + 1), v0[j] + cost);
      }
      for (int j = 0; j <= b.length; j++) v0[j] = v1[j];
    }
    return v0[b.length];
  }
}
