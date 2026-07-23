import 'dart:io';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GeminiFallbackService {
  static const _storage = FlutterSecureStorage();

  static Future<Map<String, dynamic>> correctOcrData(
    String rawOcrDump, 
    Map<String, String> extractedHeader, 
    List<dynamic> extractedItems, {
    File? imageFile,
  }) async {
    String? apiKey = await _storage.read(key: 'gemini_api_key');
    if (apiKey == null || apiKey.isEmpty) {
      apiKey = dotenv.env['GEMINI_API_KEY'];
    }
    
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY not found in Secure Storage or .env');
    }

    final model = GenerativeModel(
      model: 'gemini-2.5-flash', // Using flash for maximum speed
      apiKey: apiKey,
    );

    final String prompt = '''
You are reviewing OCR output.

Inputs:
1. Original processed memo image
2. Extracted JSON:
{
  "header": ${jsonEncode(extractedHeader)},
  "items": ${jsonEncode(extractedItems)}
}
3. Validation report:
$rawOcrDump

Rules:
- Never rewrite correct values.
- Only modify fields that clearly conflict with the image.
- Preserve the JSON schema exactly.
- If uncertain, keep the original value and mark it as low confidence.
- Return only the corrected JSON.
''';

    final List<Part> parts = [TextPart(prompt)];
    if (imageFile != null) {
      final bytes = await imageFile.readAsBytes();
      parts.add(DataPart('image/jpeg', bytes));
    }

    try {
      final response = await model.generateContent([
        Content.multi(parts)
      ]);
      final text = response.text ?? '{}';
      
      // Clean up potential markdown formatting from Gemini
      String cleanJson = text.trim();
      if (cleanJson.startsWith('```json')) {
        cleanJson = cleanJson.substring(7);
      }
      if (cleanJson.startsWith('```')) {
        cleanJson = cleanJson.substring(3);
      }
      if (cleanJson.endsWith('```')) {
        cleanJson = cleanJson.substring(0, cleanJson.length - 3);
      }
      
      final Map<String, dynamic> result = jsonDecode(cleanJson.trim());
      return result;
    } catch (e) {
      throw Exception('Gemini fallback failed: $e');
    }
  }
}
