import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiFallbackService {
  static Future<Map<String, dynamic>> correctOcrData(
    String rawOcrDump, 
    Map<String, String> extractedHeader, 
    List<dynamic> extractedItems
  ) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY not found in .env');
    }

    final model = GenerativeModel(
      model: 'gemini-1.5-flash', // Using flash for maximum speed
      apiKey: apiKey,
    );

    final prompt = '''
You are an expert OCR corrector for Honda auto parts pickup memos. 
I have extracted text from a memo using ML Kit. The text has Y-coordinates to help you understand the physical layout (e.g., items on the same row have similar Y coordinates).
My geometry-based parser attempted to extract the data, but some items might be missing, or part numbers might be corrupted (e.g., 1 instead of L, 0 instead of O).

Here is the RAW OCR DUMP (with Y coordinates):
$rawOcrDump

Here is what my local parser managed to extract:
Header: ${jsonEncode(extractedHeader)}
Items: ${jsonEncode(extractedItems)}

TASK:
1. Review the RAW OCR DUMP. Find the correct Customer Name, Area (city), and Memo No from the top of the document.
2. Find all table rows. A row contains: SR No, Part No, Description, MRP, Qty, Location, Pack, Stock. (Location format is usually 3 digits + 1 letter like "103T" or "BOX-001").
3. Fix any corrupted part numbers. Honda part numbers look like "150350-K24-G00" or "131120-K83-D01".
4. Output a single strict JSON object containing the corrected data. Do NOT include markdown blocks like ```json. Just raw JSON.

FORMAT:
{
  "header": {
    "customer": "M/S., MAHAVIR AUTO GARAGE",
    "area": "BILIMORA",
    "memo_no": "9513"
  },
  "items": [
    {
      "part_no": "150350-K24-G00",
      "description": "...",
      "mrp": "...",
      "qty": 1,
      "location": "103T"
    }
  ]
}
''';

    try {
      final response = await model.generateContent([Content.text(prompt)]);
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
