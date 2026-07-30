import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'engine_02a_optimization.dart';
import 'engine_07_row.dart' show PartRow, RowBuilderOutput;
import 'engine_04_table_detection.dart' show TableGeometryOutput;
import 'models/pipeline_result.dart';
import 'models/pipeline_stage.dart';

class Engine09GeminiOcr {
  static const _storage = FlutterSecureStorage();

  // Strict JSON prompt for table extraction from Honda order/picking list memos.
  static const _prompt = '''
You are an expert OCR engine for Honda auto-parts warehouse picking-list memos.
The image is a printed dot-matrix ORDER/PICKING LIST document.

Your task is to extract ALL data rows from the table in this document.

The table has these columns in order from left to right:
  SR | PART No. | DESCRIPTION | M.R.P. | QTY | LOCATION | PACK | STOCK

Rules:
1. Read EVERY row in the table carefully, including the first and last rows.
2. The pipe character "|" in the document is just a column separator — ignore it.
3. Part numbers are in the format: DDDDD-XXX-XXX (5 digits, hyphen, 2–5 alphanumeric, hyphen, 2–5 alphanumeric).
4. MRP values end in ".00" or similar decimal — extract them with the decimal.
5. LOCATION codes are exactly 3 digits followed by a capital letter (e.g. "007U", "018G", "029G").
6. QTY and PACK are small integers (1–20 typically).
7. STOCK can be larger integers.
8. Do NOT hallucinate rows. Only extract rows that visually exist in the image.
9. Return ONLY raw JSON — no markdown fences, no explanation.

Output format (JSON array):
[
  {
    "sr": "1",
    "partNo": "14680-K0N-D01",
    "description": "ROLLER COMP CAM CHAIN GUIDE",
    "mrp": "72.00",
    "qty": "1",
    "location": "007U",
    "pack": "1",
    "stock": "132"
  }
]
''';

  static Future<PipelineResult<RowBuilderOutput>> extractFromImage(
    OptimizationOutput optimizedImageOutput,
    TableGeometryOutput tableGeometry,
  ) async {
    final stopwatch = Stopwatch()..start();
    final errors = <String>[];

    try {
      // 1. Resolve API key (secure storage first, fallback to .env)
      String? apiKey = await _storage.read(key: 'gemini_api_key');
      if (apiKey == null || apiKey.isEmpty) {
        apiKey = dotenv.env['GEMINI_API_KEY'];
      }
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('GEMINI_API_KEY not found. Add it to your .env file or Settings screen.');
      }

      // 2. Load optimized image bytes
      final imageFile = optimizedImageOutput.optimizedImage;
      if (!await imageFile.exists()) {
        throw Exception('Optimized image file not found at: ${imageFile.path}');
      }
      final imageBytes = await imageFile.readAsBytes();

      if (kDebugMode) {
        debugPrint('[E09-Gemini] Sending image to Gemini API (${(imageBytes.length / 1024).toStringAsFixed(1)} KB)...');
      }

      // 3. Build Gemini model and call API
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.0, // Zero temperature for deterministic extraction
          responseMimeType: 'application/json',
        ),
      );

      final content = Content.multi([
        TextPart(_prompt),
        DataPart('image/jpeg', imageBytes),
      ]);

      final response = await model.generateContent([content]);
      final rawText = response.text ?? '';

      if (kDebugMode) {
        debugPrint('[E09-Gemini] Raw response (${rawText.length} chars): ${rawText.substring(0, rawText.length.clamp(0, 300))}...');
      }

      // 4. Parse JSON response
      String cleanJson = rawText.trim();
      // Strip any accidental markdown fences
      if (cleanJson.startsWith('```json')) cleanJson = cleanJson.substring(7);
      if (cleanJson.startsWith('```')) cleanJson = cleanJson.substring(3);
      if (cleanJson.endsWith('```')) cleanJson = cleanJson.substring(0, cleanJson.length - 3);
      cleanJson = cleanJson.trim();

      final List<dynamic> rawRows = jsonDecode(cleanJson);

      // 5. Map to PartRow objects
      final rows = <PartRow>[];
      for (final r in rawRows) {
        final map = r as Map<String, dynamic>;
        final partNo = (map['partNo'] ?? '').toString().trim().toUpperCase();
        final desc = (map['description'] ?? '').toString().trim();
        final mrp = (map['mrp'] ?? '').toString().trim();
        final qty = (map['qty'] ?? '').toString().trim();
        final location = (map['location'] ?? '').toString().trim();
        
        // Skip obviously empty rows
        if (partNo.isEmpty && desc.isEmpty && mrp.isEmpty) continue;

        rows.add(PartRow(
          sr: (map['sr'] ?? '').toString().trim(),
          partNo: partNo,
          description: desc,
          mrp: mrp,
          qty: qty,
          location: location,
          pack: (map['pack'] ?? '').toString().trim(),
          stock: (map['stock'] ?? '').toString().trim(),
          isDbVerified: false,
        ));
      }

      if (kDebugMode) {
        debugPrint('[E09-Gemini] Extracted ${rows.length} rows successfully.');
      }

      stopwatch.stop();
      return PipelineResult(
        data: RowBuilderOutput(
          tableGeometry: tableGeometry,
          rows: rows,
        ),
        timingMs: stopwatch.elapsedMilliseconds,
        confidence: 0.95,
        stage: PipelineStage.rowBuilder,
        errors: errors,
      );
    } catch (e) {
      stopwatch.stop();
      if (kDebugMode) debugPrint('[E09-Gemini] Error: $e');
      return PipelineResult.failure(
        stage: PipelineStage.rowBuilder,
        reason: 'Gemini OCR failed: $e',
        timingMs: stopwatch.elapsedMilliseconds,
      );
    }
  }
}
