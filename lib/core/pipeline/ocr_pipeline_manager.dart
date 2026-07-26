import 'dart:io';

import '../database/app_database.dart';
import '../models/extracted_memo.dart';

import 'engine_01_acquisition.dart';
import 'engine_02_processing.dart';
import 'engine_02a_optimization.dart';
import 'engine_03_header.dart';
import 'engine_04_table_detection.dart';
import 'engine_05_grid.dart';
import 'engine_06_cell.dart';
import 'engine_06b_zone_ocr.dart';
import 'engine_07_row.dart';
import 'engine_08_database_match.dart';
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

    // ENGINE 06B (Zone OCR replaces Engine 06)
    final e06Result = await Engine06BZoneOcr.processZones(e02aResult.data!, e05Result.data!);
    if (!e06Result.isSuccess) throw Exception('Engine 06B Failed: ${e06Result.errors}');

    // ENGINE 07
    final e07Result = await Engine07RowBuilder.build(e06Result.data!);
    if (!e07Result.isSuccess) throw Exception('Engine 07 Failed: ${e07Result.errors}');

    // ENGINE 08 (Database Validation)
    final e08Result = await Engine08DatabaseMatch.validateAndCorrect(e07Result.data!);
    if (!e08Result.isSuccess) throw Exception('Engine 08 Failed: ${e08Result.errors}');

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

    return MemoOcrResult(
      header: header,
      items: finalItems,
      rawOcrDump: rawOcrDump,
      imagePath: originalImage.path,
    );
  }

  static String _safeCorrect(String s) => s.replaceAll('O', '0').replaceAll('Q', '0').replaceAll('I', '1');

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
