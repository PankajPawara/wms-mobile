class BarcodeUtil {
  BarcodeUtil._();

  // Honda part number pattern: e.g. 22201-KON-DU2
  // Prefix: 4-6 chars, middle: 3 chars, suffix: 3-5 chars
  static final RegExp _hondaPartPattern =
      RegExp(r'\b[A-Z0-9]{4,6}-[A-Z0-9]{3}-[A-Z0-9]{3,5}\b');

  // General numeric barcode (EAN-13, EAN-8, UPC-A)
  static final RegExp _numericBarcode = RegExp(r'\b\d{8,14}\b');

  static bool isValidBarcode(String value) {
    return _numericBarcode.hasMatch(value) ||
        _hondaPartPattern.hasMatch(value);
  }

  static bool isHondaPartNo(String value) {
    final upper = value.toUpperCase().trim();
    // Normalize spaces/dots to hyphens before checking
    final normalized = upper.replaceAll(RegExp(r'[-.\s]+'), '-');
    return _hondaPartPattern.hasMatch(normalized);
  }

  /// Extract all Honda part numbers from OCR text and normalize them
  static List<String> extractPartNumbers(String text) {
    final upper = text.toUpperCase();
    // Search for flexible part numbers containing spaces, dots, or hyphens
    final flexiblePattern = RegExp(r'\b[A-Z0-9]{4,6}[-.\s]+[A-Z0-9]{3}[-.\s]+[A-Z0-9]{3,5}\b');
    return flexiblePattern
        .allMatches(upper)
        .map((m) => m.group(0)!.replaceAll(RegExp(r'[-.\s]+'), '-'))
        .toSet()
        .toList();
  }

  static String formatPartNo(String raw) {
    return raw.trim().toUpperCase().replaceAll(RegExp(r'[-.\s]+'), '-');
  }

  /// Extract customer name from order memo
  static String? extractCustomerName(String text) {
    final match = RegExp(r'M/S\.,?\s*([^\n\r]+)', caseSensitive: false).firstMatch(text);
    if (match != null) {
      var name = match.group(1)!.trim();
      // Remove trailing address tags or numbers to isolate company name
      name = name.replaceAll(RegExp(r'\s+(VANSADA|SURAT|KIM|RUSTAMPURA|KOSAMBA).*$', caseSensitive: false), '');
      return name;
    }
    return null;
  }

  /// Extract customer area/location from order memo
  static String? extractArea(String text) {
    final match = RegExp(r'AREA\s*:\s*([^\n\r]+)', caseSensitive: false).firstMatch(text);
    if (match != null) {
      return match.group(1)!.trim();
    }
    // Fallback: look for common cities/towns in the memo header
    final nameMatch = RegExp(r'M/S\.,?\s*[^\n\r]+\s+(VANSADA|RUSTAMPURA|SURAT|KIM|KOSAMBA)', caseSensitive: false).firstMatch(text);
    if (nameMatch != null) {
      return nameMatch.group(1)!.trim();
    }
    return null;
  }

  /// Extract Memo No. from order memo
  static String? extractMemoNumber(String text) {
    final match = RegExp(r'MEMO\s*NO\s*\.?\s*:\s*(\d+)', caseSensitive: false).firstMatch(text);
    if (match != null) {
      return match.group(1)!.trim();
    }
    return null;
  }

  /// Extract list of item maps containing part_no, unit_price, required_qty, description, location, and stock from OCR text
  static List<Map<String, dynamic>> parseOcrText(String text) {
    final List<Map<String, dynamic>> results = [];
    final lines = text.split('\n');

    final flexiblePattern = RegExp(r'\b[A-Z0-9]{4,6}[-.\s]+[A-Z0-9]{3}[-.\s]+[A-Z0-9]{3,5}\b');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // Helper to clean O->0, l/I->1 for numeric fields
      String _cleanNum(String s) => s.replaceAll(RegExp(r'[Oo]'), '0').replaceAll(RegExp(r'[Il]'), '1');

      // ─── CASE A: FAS Software Pipe Delimited Layout ────────────────────────
      if (line.contains('|')) {
        final List<String> cols = line.split('|').map((s) => s.trim()).toList();
        if (cols.length >= 3) {
          // Find the column containing the part number
          String? partNo;
          int partColIdx = -1;
          for (int c = 0; c < cols.length; c++) {
            final colVal = cols[c];
            final match = flexiblePattern.firstMatch(colVal.toUpperCase());
            if (match != null) {
              partNo = match.group(0)!.replaceAll(RegExp(r'[-.\s]+'), '-').toUpperCase();
              partColIdx = c;
              break;
            }
          }

          // If no part number found directly, look for first or second column after stripping leading serial numbers
          if (partNo == null) {
            for (int c = 0; c < cols.length && c < 2; c++) {
              final colVal = cols[c].replaceAll(RegExp(r'^[0-9|Il\s/]+'), ''); // Strip leading serial no / pipe errors
              final match = flexiblePattern.firstMatch(colVal.toUpperCase());
              if (match != null) {
                partNo = match.group(0)!.replaceAll(RegExp(r'[-.\s]+'), '-').toUpperCase();
                partColIdx = c;
                break;
              }
            }
          }

          if (partNo != null) {
            // Description: typically column after Part No (or cols[2] if standard layout)
            String description = '';
            if (partColIdx + 1 < cols.length) {
              description = cols[partColIdx + 1];
            } else if (cols.length > 2) {
              description = cols[2];
            }

            // MRP (Price): look for decimal format in remaining columns
            double price = 0.0;
            for (int c = 0; c < cols.length; c++) {
              if (c == partColIdx) continue;
              final colVal = _cleanNum(cols[c]);
              final decimalMatch = RegExp(r'\b\d+[\.,]\d{2}\b').firstMatch(colVal);
              if (decimalMatch != null) {
                price = double.tryParse(decimalMatch.group(0)!.replaceAll(',', '.')) ?? 0.0;
                break;
              }
            }

            // Standard order: [Sr, PartNo, Desc, MRP, Qty, Location, Pack, Stock]
            int qty = 1;
            String location = '';
            int stock = 0;

            if (cols.length >= 8) {
              qty = int.tryParse(_cleanNum(cols[4])) ?? 1;
              location = cols[5];
              stock = int.tryParse(_cleanNum(cols[7])) ?? 0;
            } else {
              // Guess columns if count is different
              for (int c = partColIdx + 2; c < cols.length; c++) {
                final val = cols[c];
                if (RegExp(r'^[A-Z0-9]+-[A-Z0-9]+(-[A-Z0-9]+)?$').hasMatch(val)) {
                  location = val;
                } else {
                  final numVal = int.tryParse(_cleanNum(val));
                  if (numVal != null) {
                    if (qty == 1 && numVal > 0 && numVal < 100) {
                      qty = numVal;
                    } else {
                      stock = numVal;
                    }
                  }
                }
              }
            }

            // Clean description and location
            description = description.replaceAll(RegExp(r'\s+'), ' ').trim();
            location = location.replaceAll(RegExp(r'\s+'), ' ').trim();

            results.add({
              'part_no': partNo,
              'description': description,
              'price': price,
              'quantity': qty,
              'location': location,
              'stock': stock,
            });
            continue; // Line processed
          }
        }
      }

      // ─── CASE B: Standard Fallback (No Pipes) ──────────────────────────────
      final partMatch = flexiblePattern.firstMatch(line.toUpperCase());
      if (partMatch != null) {
        final rawPartNo = partMatch.group(0)!;
        final normalizedPartNo = rawPartNo.replaceAll(RegExp(r'[-.\s]+'), '-').toUpperCase();

        final contextText = _cleanNum('$line ${i + 1 < lines.length ? lines[i + 1] : ""}');

        // Extract unit price
        double? price;
        final decimalMatches = RegExp(r'\b\d+[\.,]\d{2}\b').allMatches(contextText);
        if (decimalMatches.isNotEmpty) {
          final valStr = decimalMatches.first.group(0)!.replaceAll(',', '.');
          price = double.tryParse(valStr);
        } else {
          final priceMatch = RegExp(r'\b(\d{3,5})\b').firstMatch(contextText);
          if (priceMatch != null) {
            price = double.tryParse(priceMatch.group(1)!);
          }
        }

        // Extract qty
        int qty = 1;
        final cleanedLine = _cleanNum(line);
        final qtyMatch1 = RegExp(r'(?:QTY|QTY\.|QTY\s*:|PCS|PCS\.|x|\b)\s*(\d{1,2})\b', caseSensitive: false).firstMatch(cleanedLine);
        if (qtyMatch1 != null) {
          qty = int.tryParse(qtyMatch1.group(1)!) ?? 1;
        } else {
          final allInts = RegExp(r'\b(\d{1,2})\b').allMatches(cleanedLine);
          for (final match in allInts) {
            final val = int.tryParse(match.group(1)!) ?? 1;
            if (val > 0 && val < 50) {
              qty = val;
              break;
            }
          }
        }

        results.add({
          'part_no': normalizedPartNo,
          'description': '',
          'price': price ?? 0.0,
          'quantity': qty,
          'location': '',
          'stock': 0,
        });
      }
    }

    // Ultimate fallback if no parts extracted at all
    if (results.isEmpty) {
      final parts = extractPartNumbers(text);
      for (final part in parts) {
        results.add({
          'part_no': part,
          'description': '',
          'price': 0.0,
          'quantity': 1,
          'location': '',
          'stock': 0,
        });
      }
    }

    return results;
  }

  /// Fuzzy match an OCR scanned part number against a list of known valid part numbers
  /// (e.g., from the local database) allowing for common OCR confusions.
  static String? findBestMatch(String query, List<String> availableParts) {
    if (query.isEmpty || availableParts.isEmpty) return null;

    final upperQuery = query.toUpperCase();
    
    // Exact match first
    for (final part in availableParts) {
      if (part.toUpperCase() == upperQuery) {
        return part;
      }
    }
    
    // Normalize string to wildcard string by replacing common confused characters
    String normalizeFuzzy(String s) {
      // Confusions:
      // O, 0, Q -> 0
      // 2, Z -> 2
      // 1, I, l -> 1
      // 5, S -> 5
      // 8, B -> 8
      return s
          .replaceAll(RegExp(r'[OQ]'), '0')
          .replaceAll('Z', '2')
          .replaceAll(RegExp(r'[Il]'), '1')
          .replaceAll('S', '5')
          .replaceAll('B', '8');
    }

    final queryFuzzy = normalizeFuzzy(upperQuery);
    
    String? bestMatch;
    int matches = 0;
    
    for (final part in availableParts) {
      final partUpper = part.toUpperCase();
      if (partUpper.length == upperQuery.length) {
        if (normalizeFuzzy(partUpper) == queryFuzzy) {
          bestMatch = part;
          matches++;
        }
      }
    }
    
    // If exactly one fuzzy match was found, return it as confident correction
    if (matches == 1) {
      return bestMatch;
    }
    
    return null;
  }
}
