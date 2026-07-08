import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:math';
import 'barcode_util.dart';

class LocalOcrParser {
  /// Parses the RecognizedText using geometric row grouping to prevent mixed-column hallucinations.
  static List<Map<String, dynamic>> parseTable(RecognizedText recognizedText) {
    List<Map<String, dynamic>> items = [];

    // 1. Flatten all elements
    List<TextElement> allElements = [];
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        allElements.addAll(line.elements);
      }
    }

    if (allElements.isEmpty) return items;

    // 2. Sort by Y coordinate (top to bottom)
    allElements.sort((a, b) => a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy));

    // 3. Group into rows
    List<List<TextElement>> rows = [];
    List<TextElement> currentRow = [allElements.first];
    
    // Use a tolerance based on the height of the elements. 
    // Roughly half the height of a typical element.
    double rowTolerance = 15.0; 

    for (int i = 1; i < allElements.length; i++) {
      final element = allElements[i];
      final currentCenterY = currentRow.map((e) => e.boundingBox.center.dy).reduce((a, b) => a + b) / currentRow.length;
      
      if ((element.boundingBox.center.dy - currentCenterY).abs() <= rowTolerance) {
        currentRow.add(element);
      } else {
        rows.add(currentRow);
        currentRow = [element];
      }
    }
    if (currentRow.isNotEmpty) {
      rows.add(currentRow);
    }

    // 4. Sort each row horizontally and extract data
    for (var row in rows) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      
      int partIdx = -1;
      String extractedPartNo = '';
      
      // Find the Part Number
      for (int i = 0; i < row.length; i++) {
        final text = row[i].text.toUpperCase();
        // Allow for concatenated errors like "150350-K24-G00"
        final cleaned = BarcodeUtil.cleanExtractedPartNo(text);
        if (BarcodeUtil.isHondaPartNo(cleaned)) {
          partIdx = i;
          extractedPartNo = cleaned;
          break;
        }
      }

      if (partIdx != -1) {
        // We found a part number row!
        String description = '';
        double mrp = 0.0;
        int qty = 1;
        String location = '';
        
        int mrpIdx = -1;
        
        // Scan elements to the right of Part No for MRP (the first decimal number or large integer)
        for (int i = partIdx + 1; i < row.length; i++) {
          String text = row[i].text;
          // Clean common OCR errors in numbers
          text = text.replaceAll(RegExp(r'[Oo]'), '0').replaceAll(RegExp(r'[Il]'), '1').replaceAll(',', '.');
          
          final decimalMatch = RegExp(r'^\d+\.\d{2}$').firstMatch(text);
          if (decimalMatch != null || (int.tryParse(text) != null && int.parse(text) > 100)) {
             mrp = double.tryParse(text) ?? 0.0;
             mrpIdx = i;
             break;
          }
        }
        
        // Description is everything between Part No and MRP
        if (mrpIdx != -1 && mrpIdx > partIdx + 1) {
          description = row.sublist(partIdx + 1, mrpIdx).map((e) => e.text).join(' ');
        } else if (mrpIdx == -1 && row.length > partIdx + 1) {
          // No MRP found, description is just the next few elements
          description = row.sublist(partIdx + 1, min(partIdx + 4, row.length)).map((e) => e.text).join(' ');
        }
        
        // QTY is usually the element immediately following MRP
        int qtyIdx = -1;
        if (mrpIdx != -1 && mrpIdx + 1 < row.length) {
          String text = row[mrpIdx + 1].text.replaceAll(RegExp(r'[Oo]'), '0').replaceAll(RegExp(r'[Il]'), '1');
          final parsedQty = int.tryParse(text);
          if (parsedQty != null && parsedQty < 100) {
            qty = parsedQty;
            qtyIdx = mrpIdx + 1;
          }
        }
        
        // Location is usually the element following QTY
        int startLocSearchIdx = (qtyIdx != -1) ? qtyIdx + 1 : ((mrpIdx != -1) ? mrpIdx + 1 : partIdx + 1);
        for (int i = startLocSearchIdx; i < row.length; i++) {
          String text = row[i].text;
          // Location format e.g. 002N, 014G, 073J
          if (RegExp(r'^[A-Z0-9]{3,5}$', caseSensitive: false).hasMatch(text)) {
             location = text.toUpperCase();
             break;
          }
        }
        
        items.add({
          'part_no': extractedPartNo,
          'description': description,
          'mrp': mrp,
          'qty': qty,
          'location': location,
        });
      }
    }

    return items;
  }
}
