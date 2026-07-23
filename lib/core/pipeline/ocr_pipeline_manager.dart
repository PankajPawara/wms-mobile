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
import 'engine_07_row.dart';
import '../services/candidate_generator.dart';

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
    
    // ENGINE 06
    final e06Result = await Engine06CellAssignment.assign(e05Result.data!);
    if (!e06Result.isSuccess) throw Exception('Engine 06 Failed: ${e06Result.errors}');

    // ENGINE 07
    final e07Result = await Engine07RowBuilder.build(e06Result.data!);
    if (!e07Result.isSuccess) throw Exception('Engine 07 Failed: ${e07Result.errors}');

    // Map Engine 03 output to ExtractedMemoHeader
    final headerData = e03Result.data!.headerData;
    final header = ExtractedMemoHeader(
      customerName: headerData['customerName'] ?? '',
      area: headerData['area'] ?? '',
      memoNumber: headerData['memoNo'] ?? '',
    );

    // Map Engine 07 output to ExtractedMemoItems and Validate with DB
    final candidateGenerator = CandidateGenerator(db);
    await candidateGenerator.init();
    
    final List<ExtractedMemoItem> finalItems = [];
    String rawOcrDump = '--- Header Raw Text ---\n${e03Result.data!.rawWords.map((w) => w.text).join(' ')}\n\n';
    
    for (var r in e07Result.data!.rows) {
      if (r.partNo.trim().isEmpty) continue;
      
      final mrp = double.tryParse(r.mrp.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
      final qty = int.tryParse(r.qty.replaceAll(RegExp(r'\D'), '')) ?? 1;
      final pack = int.tryParse(r.pack.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final stock = int.tryParse(r.stock.replaceAll(RegExp(r'\D'), '')) ?? 0;

      // Handle cases where multiple part numbers get clustered into a single row
      // (often happens on rotated images or extremely dense receipts)
      final parts = r.partNo.split(' ').map((s) => s.trim()).where((s) => s.length >= 3).toList();
      
      if (parts.isEmpty) continue;

      for (final p in parts) {
        final item = await candidateGenerator.findBestMatch(
          rawPartNo: p,
          description: r.description.trim(),
          mrp: mrp,
          qty: qty,
          location: r.location.trim(),
          pack: pack,
          stock: stock,
        );
        
        // If it's a valid match (or we just keep it as unmatched for the user to see), add it.
        finalItems.add(item);
        rawOcrDump += 'Row -> SR: ${r.sr} | PART: $p | DESC: ${r.description} | MRP: ${r.mrp} | QTY: ${r.qty} | LOC: ${r.location}\n';
      }
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
}
