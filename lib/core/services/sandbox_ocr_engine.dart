import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'memo_ocr_engine.dart' show OcrWord;

class TableGeometry {
  final int topY;
  final int bottomY;
  final int srStartX;
  final int partNoStartX;
  final int descStartX;
  final int mrpStartX;
  final int qtyStartX;
  final int locStartX;
  final int packStartX;
  final int stockStartX;
  final int tableRightX;

  const TableGeometry({
    required this.topY,
    required this.bottomY,
    required this.srStartX,
    required this.partNoStartX,
    required this.descStartX,
    required this.mrpStartX,
    required this.qtyStartX,
    required this.locStartX,
    required this.packStartX,
    required this.stockStartX,
    required this.tableRightX,
  });

  Map<String, dynamic> toJson() => {
    'topY': topY,
    'bottomY': bottomY,
    'srStartX': srStartX,
    'partNoStartX': partNoStartX,
    'descStartX': descStartX,
    'mrpStartX': mrpStartX,
    'qtyStartX': qtyStartX,
    'locStartX': locStartX,
    'packStartX': packStartX,
    'stockStartX': stockStartX,
    'tableRightX': tableRightX,
  };
}

class HeaderExtractor {
  static Map<String, dynamic> extract(List<OcrWord> allWords, int tableTopY) {
    final headerWords = allWords.where((w) => w.bottom < tableTopY).toList();
    final headerText = headerWords.map((w) => w.text).join(' ');
    
    // Very simple spatial extraction fallback, similar to original but outputting JSON
    return {
      'customerName': _extractPattern(headerText, r'M/S\.,?\s*([A-Z\s]+?)(?:DATE|MEMO|AREA|$)'),
      'memoNo': _extractPattern(headerText, r'MEMO\s*NO\.?\s*:\s*(\d+)'),
      'memoDate': _extractPattern(headerText, r'DATE\s*:\s*([\d/]+)'),
      'area': _extractPattern(headerText, r'AREA\s*:\s*([A-Z\s]+)'),
      'phone': _extractPattern(headerText, r'(\d{10})'),
      'pageNo': _extractPattern(headerText, r'Page\s*(\d+)'),
    };
  }

  static String _extractPattern(String text, String pattern) {
    final match = RegExp(pattern, caseSensitive: false).firstMatch(text);
    return match?.group(1)?.trim() ?? '';
  }
}

class TableGeometryDetector {
  static TableGeometry? detect(List<OcrWord> allWords) {
    // Find the header anchor word ("DESCRIPTION" is best, "M.R.P" is backup)
    OcrWord? anchorWord;
    for (final w in allWords) {
      if (w.text.toUpperCase().contains('DESCRIPTION') || w.text.toUpperCase().contains('DESC')) {
        anchorWord = w;
        break;
      }
    }
    if (anchorWord == null) {
      for (final w in allWords) {
        if (w.text.toUpperCase().contains('QTY') || w.text.toUpperCase().contains('M.R.P')) {
          anchorWord = w;
          break;
        }
      }
    }
    if (anchorWord == null) return null;
    
    int headerCenterY = (anchorWord.top + anchorWord.bottom) ~/ 2;
    int headerBottom = anchorWord.bottom;
    
    // Header band is +/- 80 pixels from the anchor to account for skew
    final headerBand = allWords.where((w) {
      int cy = (w.top + w.bottom) ~/ 2;
      return (cy - headerCenterY).abs() <= 80;
    }).toList();
    
    int rightmostX = 1200;
    for (final word in allWords) {
      if (word.right > rightmostX) rightmostX = word.right;
    }
    
    // Default column boundaries based on typical layout ratios relative to total width
    int srX = 0;
    int partNoX = (rightmostX * 0.04).toInt();
    int descX = (rightmostX * 0.16).toInt();
    int mrpX = (rightmostX * 0.54).toInt();
    int qtyX = (rightmostX * 0.62).toInt();
    int locX = (rightmostX * 0.70).toInt();
    int packX = (rightmostX * 0.83).toInt();
    int stockX = (rightmostX * 0.89).toInt();
    
    // Find the exact X for keywords
    for (final w in headerBand) {
      final text = w.text.toUpperCase();
      if (text == 'SR' || text == 'S.R') srX = w.left - 10;
      if (text.contains('PART')) partNoX = w.left - 10;
      if (text.contains('DESC')) descX = w.left - 10;
      if (text.contains('MRP') || text.contains('M.R.P')) mrpX = w.left - 10;
      if (text == 'QTY') qtyX = w.left - 10;
      if (text.contains('LOC')) locX = w.left - 10;
      if (text.contains('PACK') || text.contains('PKT')) packX = w.left - 10;
      if (text.contains('STOCK') || text.contains('STK')) stockX = w.left - 10;
      if (w.bottom > headerBottom) headerBottom = w.bottom;
    }
    
    // Find '|' separators in the header band
    final separators = <int>[];
    for (final w in headerBand) {
      if (w.text == '|' || w.text == 'I' || w.text == 'l') {
        separators.add((w.left + w.right) ~/ 2);
      } else if (w.text.startsWith('|')) {
        separators.add(w.left);
      } else if (w.text.endsWith('|')) {
        separators.add(w.right);
      }
    }
    separators.sort();
    
    // Snap boundaries to nearest left separator
    int snapToSeparator(int keywordX) {
      int bestSep = -1;
      for (final sep in separators) {
        if (sep < keywordX + 40 && sep > keywordX - 250) {
          bestSep = sep;
        }
      }
      return bestSep != -1 ? bestSep : keywordX;
    }
    
    partNoX = snapToSeparator(partNoX);
    descX = snapToSeparator(descX);
    mrpX = snapToSeparator(mrpX);
    qtyX = snapToSeparator(qtyX);
    locX = snapToSeparator(locX);
    packX = snapToSeparator(packX);
    stockX = snapToSeparator(stockX);

    // Enforce strictly increasing bounds so high-res overlaps don't occur
    if (partNoX <= srX) partNoX = srX + 10;
    if (descX <= partNoX) descX = partNoX + 10;
    if (mrpX <= descX) mrpX = descX + 10;
    if (qtyX <= mrpX) qtyX = mrpX + 10;
    if (locX <= qtyX) locX = qtyX + 10;
    if (packX <= locX) packX = locX + 10;
    if (stockX <= packX) stockX = packX + 10;

    return TableGeometry(
      topY: headerBottom,
      bottomY: 999999, // To be refined by footer
      srStartX: srX,
      partNoStartX: partNoX,
      descStartX: descX,
      mrpStartX: mrpX,
      qtyStartX: qtyX,
      locStartX: locX,
      packStartX: packX,
      stockStartX: stockX,
      tableRightX: rightmostX,
    );
  }
}

class CellMatrixBuilder {
  static List<Map<String, dynamic>> buildMatrix(List<OcrWord> allWords, TableGeometry geom) {
    // Filter words to only those below the header row
    final tableWords = allWords.where((w) => w.top >= geom.topY && w.bottom <= geom.bottomY).toList();
    
    // Group by Y
    tableWords.sort((a, b) => a.top.compareTo(b.top));
    
    final rows = <List<OcrWord>>[];
    List<OcrWord> currentRow = [];
    int? currentAnchorY;
    
    for (final word in tableWords) {
      if (currentAnchorY == null) {
        currentAnchorY = word.top;
        currentRow.add(word);
      } else {
        if ((word.top - currentAnchorY).abs() <= 35) { // Increased threshold to 35 for skewed images
          currentRow.add(word);
        } else {
          rows.add(currentRow);
          currentRow = [word];
          currentAnchorY = word.top;
        }
      }
    }
    if (currentRow.isNotEmpty) rows.add(currentRow);
    
    // Now we have physical rows. For each row, assign words to columns
    final matrix = <Map<String, dynamic>>[];
    
    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      
      final srWords = r.where((w) {
        final cx = (w.left + w.right) / 2;
        return cx >= geom.srStartX && cx < geom.partNoStartX;
      }).toList();
      final partWords = r.where((w) {
        final cx = (w.left + w.right) / 2;
        return cx >= geom.partNoStartX && cx < geom.descStartX;
      }).toList();
      final descWords = r.where((w) {
        final cx = (w.left + w.right) / 2;
        return cx >= geom.descStartX && cx < geom.mrpStartX;
      }).toList();
      final mrpWords = r.where((w) {
        final cx = (w.left + w.right) / 2;
        return cx >= geom.mrpStartX && cx < geom.qtyStartX;
      }).toList();
      final qtyWords = r.where((w) {
        final cx = (w.left + w.right) / 2;
        return cx >= geom.qtyStartX && cx < geom.locStartX;
      }).toList();
      final locWords = r.where((w) {
        final cx = (w.left + w.right) / 2;
        return cx >= geom.locStartX && cx < geom.packStartX;
      }).toList();
      final packWords = r.where((w) {
        final cx = (w.left + w.right) / 2;
        return cx >= geom.packStartX && cx < geom.stockStartX;
      }).toList();
      final stockWords = r.where((w) {
        final cx = (w.left + w.right) / 2;
        return cx >= geom.stockStartX && cx <= geom.tableRightX + 50;
      }).toList();
      
      matrix.add({
        'row': i + 1,
        'cells': {
          'sr': srWords.map((w) => {'text': w.text, 'left': w.left, 'top': w.top, 'right': w.right, 'bottom': w.bottom}).toList(),
          'partNo': partWords.map((w) => {'text': w.text, 'left': w.left, 'top': w.top, 'right': w.right, 'bottom': w.bottom}).toList(),
          'description': descWords.map((w) => {'text': w.text, 'left': w.left, 'top': w.top, 'right': w.right, 'bottom': w.bottom}).toList(),
          'mrp': mrpWords.map((w) => {'text': w.text, 'left': w.left, 'top': w.top, 'right': w.right, 'bottom': w.bottom}).toList(),
          'qty': qtyWords.map((w) => {'text': w.text, 'left': w.left, 'top': w.top, 'right': w.right, 'bottom': w.bottom}).toList(),
          'location': locWords.map((w) => {'text': w.text, 'left': w.left, 'top': w.top, 'right': w.right, 'bottom': w.bottom}).toList(),
          'pack': packWords.map((w) => {'text': w.text, 'left': w.left, 'top': w.top, 'right': w.right, 'bottom': w.bottom}).toList(),
          'stock': stockWords.map((w) => {'text': w.text, 'left': w.left, 'top': w.top, 'right': w.right, 'bottom': w.bottom}).toList(),
        }
      });
    }
    
    return matrix;
  }
}

class ColumnExtractors {
  static Map<String, dynamic> extractRowValues(Map<String, dynamic> rowMatrix) {
    final cells = rowMatrix['cells'] as Map<String, dynamic>;
    
    return {
      'row': rowMatrix['row'],
      'sr': _extractSr(cells['sr']!),
      'partNo': _extractPartNo(cells['partNo']!),
      'description': _extractDescription(cells['description']!),
      'mrp': _extractMrp(cells['mrp']!),
      'qty': _extractQty(cells['qty']!),
      'location': _extractLocation(cells['location']!),
      'pack': _extractPack(cells['pack']!),
      'stock': _extractStock(cells['stock']!),
    };
  }

  static int? _extractSr(List<dynamic> words) {
    if (words.isEmpty) return null;
    final text = words.map((w) => w['text']).join('').replaceAll(RegExp(r'\D'), '');
    return int.tryParse(text);
  }

  static String _extractPartNo(List<dynamic> words) {
    if (words.isEmpty) return '';
    // Concatenate all tokens
    String raw = words.map((w) => w['text']).join('');
    raw = raw.replaceAll(RegExp(r'\s+'), '');
    // Strip ALL pipe and backslash characters (column separators misread)
    raw = raw.replaceAll(RegExp(r'[|\\]'), '');
    // Reject if only non-part-number content
    if (raw.replaceAll(RegExp(r'[^A-Za-z0-9\-]'), '').isEmpty) return '';
    return raw;
  }

  static String _extractDescription(List<dynamic> words) {
    if (words.isEmpty) return '';
    String raw = words.map((w) => w['text']).join(' ');
    // Strip pipe characters which are column delimiters
    raw = raw.replaceAll(RegExp(r'[|\\]'), '');
    // Clean up multiple spaces that might have resulted from stripping
    raw = raw.replaceAll(RegExp(r'\s+'), ' ');
    return raw.trim();
  }

  static double? _extractMrp(List<dynamic> words) {
    if (words.isEmpty) return null;
    // Join all tokens, remove all non-numeric except decimal point
    // Also handle the case where '|' is read as '1' at the end (e.g., '427.001' → '427.00')
    String raw = words.map((w) => w['text']).join('');
    // Strip trailing pipe characters before cleaning
    raw = raw.replaceAll(RegExp(r'[|\\]+$'), '');
    raw = raw.replaceAll(RegExp(r'[^\d.]'), '');
    // If ends with multiple decimals (e.g. '427.001' → trim trailing non-standard digits)
    // Check: valid MRP format is digits.digits (max 2 decimal places)
    final match = RegExp(r'^(\d+\.\d{1,2})').firstMatch(raw);
    if (match != null) return double.tryParse(match.group(1)!);
    return double.tryParse(raw);
  }

  static int? _extractQty(List<dynamic> words) {
    if (words.isEmpty) return null;
    final raw = words.map((w) => w['text']).join('').replaceAll(RegExp(r'\D'), '');
    return int.tryParse(raw);
  }

  static String _extractLocation(List<dynamic> words) {
    if (words.isEmpty) return '';
    String raw = words.map((w) => w['text']).join('');
    // Strip all pipe characters (column separators leaking into location)
    raw = raw.replaceAll(RegExp(r'[|\\]'), '');
    // Strip leading lowercase 'i' which is a common misread of '|'
    raw = raw.replaceAll(RegExp(r'^i(?=[A-Z0-9])'), '');
    // Strip leading standalone '1' that is actually the PACK column separator
    // Pattern: starts with '1' followed by location format (3-4 uppercase letters/digits)
    // e.g. '1032Q' where the actual location is '032Q'
    // Only strip if the '1' is followed by exactly a 3-digit+letter or digit+letter pattern
    raw = raw.replaceAll(RegExp(r'^1(?=\d{3}[A-Z])'), '');
    // Clean trailing dots or commas
    raw = raw.replaceAll(RegExp(r'[.,]+$'), '');
    return raw.trim();
  }

  static int? _extractPack(List<dynamic> words) {
    if (words.isEmpty) return null;
    final raw = words.map((w) => w['text']).join('').replaceAll(RegExp(r'\D'), '');
    return int.tryParse(raw);
  }

  static int? _extractStock(List<dynamic> words) {
    if (words.isEmpty) return null;
    final raw = words.map((w) => w['text']).join('').replaceAll(RegExp(r'\D'), '');
    return int.tryParse(raw);
  }
}

class SandboxOcrResult {
  final List<OcrWord> allWords;
  final TableGeometry? geometry;
  final Map<String, dynamic>? headerJson;
  final Map<String, dynamic>? tableMatrixJson;
  final Map<String, dynamic>? pickupJson;

  const SandboxOcrResult({
    required this.allWords,
    this.geometry,
    this.headerJson,
    this.tableMatrixJson,
    this.pickupJson,
  });
}

class SandboxOcrEngine {
  static Future<SandboxOcrResult> processImage(File imageFile) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognized = await textRecognizer.processImage(inputImage);

      final allWords = <OcrWord>[];
      
      int maxImageX = 0;
      int maxImageY = 0;
      double sumDx = 0;
      double sumDy = 0;

      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          if (line.elements.length > 1) {
            final first = line.elements.first.boundingBox;
            final last = line.elements.last.boundingBox;
            sumDx += (last.center.dx - first.center.dx);
            sumDy += (last.center.dy - first.center.dy);
          }
          for (final element in line.elements) {
            final bb = element.boundingBox;
            if (bb.right > maxImageX) maxImageX = bb.right.toInt();
            if (bb.bottom > maxImageY) maxImageY = bb.bottom.toInt();
          }
        }
      }

      int coarseRotation = 0;
      if (sumDx.abs() > sumDy.abs()) {
        coarseRotation = sumDx > 0 ? 0 : 180;
      } else if (sumDy.abs() > sumDx.abs()) {
        coarseRotation = sumDy > 0 ? 90 : 270;
      }

      double sumAngle = 0;
      int angleCount = 0;

      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          if (line.elements.length > 1) {
            final first = line.elements.first.boundingBox;
            final last = line.elements.last.boundingBox;
            
            double fx = first.center.dx; double fy = first.center.dy;
            double lx = last.center.dx; double ly = last.center.dy;
            double temp;
            if (coarseRotation == 180) {
              fx = maxImageX - fx; fy = maxImageY - fy;
              lx = maxImageX - lx; ly = maxImageY - ly;
            } else if (coarseRotation == 90) {
              temp = fx; fx = fy; fy = maxImageX - temp;
              temp = lx; lx = ly; ly = maxImageX - temp;
            } else if (coarseRotation == 270) {
              temp = fx; fx = maxImageY - fy; fy = temp;
              temp = lx; lx = maxImageY - ly; ly = temp;
            }
            
            double dx = lx - fx;
            double dy = ly - fy;
            if (dx.abs() > dy.abs()) {
              sumAngle += math.atan2(dy, dx);
              angleCount++;
            }
          }
        }
      }

      double skewAngle = angleCount > 0 ? sumAngle / angleCount : 0;
      
      double rotatedImageWidth = (coarseRotation == 90 || coarseRotation == 270) ? maxImageY.toDouble() : maxImageX.toDouble();
      double rotatedImageHeight = (coarseRotation == 90 || coarseRotation == 270) ? maxImageX.toDouble() : maxImageY.toDouble();
      double cx = rotatedImageWidth / 2;
      double cy = rotatedImageHeight / 2;

      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            final text = element.text;
            if (text.trim().isEmpty) continue;
            
            final bb = element.boundingBox;
            int left = bb.left.toInt();
            int top = bb.top.toInt();
            int right = bb.right.toInt();
            int bottom = bb.bottom.toInt();
            int newLeft, newTop, newRight, newBottom;

            if (coarseRotation == 0) {
              newLeft = left; newTop = top; newRight = right; newBottom = bottom;
            } else if (coarseRotation == 180) {
              newLeft = maxImageX - right; newRight = maxImageX - left;
              newTop = maxImageY - bottom; newBottom = maxImageY - top;
            } else if (coarseRotation == 90) {
              newLeft = top; newRight = bottom;
              newTop = maxImageX - right; newBottom = maxImageX - left;
            } else { 
              newLeft = maxImageY - bottom; newRight = maxImageY - top;
              newTop = left; newBottom = right;
            }

            double rotateX(double x, double y) => cx + (x - cx) * math.cos(-skewAngle) - (y - cy) * math.sin(-skewAngle);
            double rotateY(double x, double y) => cy + (x - cx) * math.sin(-skewAngle) + (y - cy) * math.cos(-skewAngle);

            int finalLeft = rotateX(newLeft.toDouble(), newTop.toDouble()).toInt();
            int finalRight = rotateX(newRight.toDouble(), newBottom.toDouble()).toInt();
            int finalTop = rotateY(newLeft.toDouble(), newTop.toDouble()).toInt();
            int finalBottom = rotateY(newRight.toDouble(), newBottom.toDouble()).toInt();

            if (finalLeft > finalRight) { final t = finalLeft; finalLeft = finalRight; finalRight = t; }
            if (finalTop > finalBottom) { final t = finalTop; finalTop = finalBottom; finalBottom = t; }
            
            allWords.add(OcrWord(
              text: text,
              left: finalLeft,
              top: finalTop,
              right: finalRight,
              bottom: finalBottom,
            ));
          }
        }
      }
      
      final geometry = TableGeometryDetector.detect(allWords);
      
      Map<String, dynamic>? headerJson;
      List<Map<String, dynamic>>? matrix;
      Map<String, dynamic>? pickupJson;
      
      if (geometry != null) {
        headerJson = HeaderExtractor.extract(allWords, geometry.topY);
        matrix = CellMatrixBuilder.buildMatrix(allWords, geometry);
        
        final extractedRows = matrix.map((rowMatrix) => ColumnExtractors.extractRowValues(rowMatrix)).toList();
        
        // Remove empty rows (where all essential fields are null/empty)
        final validRows = extractedRows.where((row) {
          return row['partNo'].toString().isNotEmpty || row['description'].toString().isNotEmpty;
        }).toList();
        
        pickupJson = {
          'header': headerJson,
          'items': validRows,
        };
      }
      
      return SandboxOcrResult(
        allWords: allWords,
        geometry: geometry,
        headerJson: headerJson,
        tableMatrixJson: matrix != null ? {'rows': matrix} : null,
        pickupJson: pickupJson,
      );
    } finally {
      textRecognizer.close();
    }
  }
}

class SandboxGeminiVerifier {
  static Future<Map<String, dynamic>> verify(Map<String, dynamic> pickupJson, File imageFile) async {
    const storage = FlutterSecureStorage();
    String? apiKey = await storage.read(key: 'gemini_api_key');
    if (apiKey == null || apiKey.isEmpty) {
      apiKey = dotenv.env['GEMINI_API_KEY'];
    }
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY not configured.');
    }

    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
    );
    
    final prompt = '''
You are a VALIDATOR for Honda auto-parts pickup memos. 
Your job is to compare the LOCAL JSON with the IMAGE and return ONLY corrections.
Do not invent new items. If the local JSON missed an item, add it.

LOCAL JSON:
${jsonEncode(pickupJson)}

OUTPUT FORMAT:
{
  "verified_items": [
    {
      "row": 1,
      "partNo": "correct part number",
      "qty": 5,
      "mrp": 0,
      "location": "location",
      "pack": 1,
      "stock": 0
    }
  ],
  "added_items": []
}
Return ONLY valid JSON.
''';

    final bytes = await imageFile.readAsBytes();
    final parts = [TextPart(prompt), DataPart('image/jpeg', bytes)];
    
    final response = await model.generateContent([Content.multi(parts)]);
    String text = response.text ?? '{}';
    
    if (text.startsWith('```json')) text = text.substring(7);
    if (text.startsWith('```')) text = text.substring(3);
    if (text.endsWith('```')) text = text.substring(0, text.length - 3);
    
    return jsonDecode(text.trim()) as Map<String, dynamic>;
  }
}
