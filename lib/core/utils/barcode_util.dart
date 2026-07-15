class BarcodeUtil {
  BarcodeUtil._();

  static String cleanExtractedPartNo(String input) {
    // Strip pipes, spaces, normalise to uppercase
    String cleaned = input.replaceAll(RegExp(r'[\s|]'), '').toUpperCase();
    final firstDashIdx = cleaned.indexOf('-');
    if (firstDashIdx > -1) {
      String beforeDash = cleaned.substring(0, firstDashIdx);
      final afterDash = cleaned.substring(firstDashIdx);
      
      // Replace all characters that are visually confused for digits in the 5-digit prefix
      beforeDash = beforeDash
          .replaceAll('L', '1')
          .replaceAll('I', '1')
          .replaceAll('O', '0')
          .replaceAll('S', '5');
      
      // Prefix must be exactly 5 digits — strip any excess from the front
      if (beforeDash.length > 5) {
        beforeDash = beforeDash.substring(beforeDash.length - 5);
      }
      cleaned = beforeDash + afterDash;
    }
    return cleaned;
  }

  /// Sanitise an OCR-extracted warehouse location code.
  ///
  /// Accepted formats:
  ///   1. `\d{3}[A-Z]`   — 3 digits + 1 letter, e.g. 003K, 069M
  ///   2. `BOX-\d{3}`    — shelf-box location, e.g. BOX-001, BOX-042
  ///
  /// Common OCR errors handled:
  ///   • Leading `1` before a `\d{3}[A-Z]` token → was a `|` column separator, strip it.
  ///   • `B0X` (zero) → `BOX` when trying to match format 2.
  static String cleanLocation(String raw) {
    final s = raw.replaceAll(RegExp(r'[|\s]'), '').toUpperCase();

    // ── Format 1: 3 digits + 1 letter ───────────────────────────────────────
    final slotPattern = RegExp(r'^\d{3}[A-Z]$');
    if (slotPattern.hasMatch(s)) return s;

    // Spurious leading `1` (OCR read `|` as `1`) before a valid slot code
    if (s.length == 5 && s.startsWith('1')) {
      final candidate = s.substring(1);
      if (slotPattern.hasMatch(candidate)) return candidate;
    }

    // ── Format 2: BOX-NNN ────────────────────────────────────────────────────
    // Normalise common OCR confusion: `B0X` (zero) → `BOX`
    final boxNorm = s.replaceAll(RegExp(r'B0X'), 'BOX');
    final boxPattern = RegExp(r'^BOX-\d{3}$');
    if (boxPattern.hasMatch(boxNorm)) return boxNorm;

    // ── Scan inside a longer mixed token ────────────────────────────────────
    // Check BOX-NNN first (longer pattern, more specific)
    final boxMatch = RegExp(r'(BOX-\d{3})', caseSensitive: false).firstMatch(s);
    if (boxMatch != null) return boxMatch.group(1)!.toUpperCase();

    // Then try slot pattern
    final slotMatch = RegExp(r'(\d{3}[A-Z])').firstMatch(s);
    if (slotMatch != null) return slotMatch.group(1)!;

    // Return empty string if nothing valid found
    return '';
  }

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
    if (_hondaPartPattern.hasMatch(normalized)) return true;

    // Also accept 10-15 length alphanumeric strings with NO hyphens/spaces (e.g. 12200K1LD00)
    // Honda parts almost always start with 5 digits.
    final unhyphenatedPattern = RegExp(r'^\d{5}[A-Z0-9]{5,10}$');
    if (unhyphenatedPattern.hasMatch(upper.replaceAll(RegExp(r'[^A-Z0-9]'), ''))) return true;

    return false;
  }

  /// Extract all Honda part numbers from OCR text and normalize them
  static List<String> extractPartNumbers(String text) {
    final upper = text.toUpperCase();
    // Search for flexible part numbers containing spaces, dots, or hyphens
    final flexiblePattern = RegExp(r'\b[A-Z0-9]{4,6}[-.\s]+[A-Z0-9]{3}[-.\s]+[A-Z0-9]{3,5}\b');
    final matches = flexiblePattern
        .allMatches(upper)
        .map((m) => m.group(0)!.replaceAll(RegExp(r'[-.\s]+'), '-'))
        .toList();
        
    // Also extract unhyphenated parts
    final unhyphenatedPattern = RegExp(r'\b\d{5}[A-Z0-9]{5,10}\b');
    matches.addAll(
      unhyphenatedPattern.allMatches(upper).map((m) => m.group(0)!)
    );
        
    return matches.toSet().toList();
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

  /// Extract red label part details from OCR text
  static Map<String, dynamic> parseRedLabelOcrText(String text) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    String? partNo;
    int? qty;
    double? mrp;
    String? productName;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final upperLine = line.toUpperCase();

      // 1. Part No
      final cleaned = cleanExtractedPartNo(line.replaceAll(RegExp(r'[^A-Za-z0-9]'), ''));
      if (cleaned.length >= 7 && cleaned.length <= 15 && partNo == null) {
        if (isHondaPartNo(cleaned)) {
          partNo = line; // Preserve original formatting for display if needed
        }
      }

      // 2. Quantity
      if (qty == null && (upperLine.contains("QTY") || upperLine.contains("QUANTITY") || upperLine.contains("NUMBER(S)"))) {
        final match = RegExp(r'\d+').firstMatch(line);
        if (match != null) {
          qty = int.tryParse(match.group(0)!);
        }
      }

      // 3. MRP (Per piece)
      if (mrp == null && (upperLine.contains("PER NUMBER") || upperLine.contains("PER PIECE") || upperLine.contains("PER UNIT") || upperLine.contains("EACH") || upperLine.contains("MRP"))) {
        // Remove spaces and commas
        final cleanLine = line.replaceAll(RegExp(r'[,\s]'), '');
        final decimalMatch = RegExp(r'\d+\.\d{2}').firstMatch(cleanLine);
        
        if (decimalMatch != null) {
           mrp = double.tryParse(decimalMatch.group(0)!);
        } else {
           final match = RegExp(r'\d+').firstMatch(cleanLine);
           if (match != null) {
              mrp = double.tryParse(match.group(0)!);
           }
        }
      }

      // 4. Product Name
      if (productName == null) {
        if (upperLine.contains("PRODUCT")) {
          final parts = line.split(RegExp(r':'));
          if (parts.length > 1 && parts[1].trim().isNotEmpty) {
            productName = parts[1].trim();
          } else if (i + 1 < lines.length) {
            for (int j = i + 1; j < lines.length; j++) {
              final nextLine = lines[j].trim();
              if (nextLine.isEmpty) continue;
              
              final upperNextLine = nextLine.toUpperCase();
              
              if (upperNextLine.contains("PER NUMBER") || 
                  upperNextLine.contains("PER PIECE") ||
                  upperNextLine.contains("PER UNIT") ||
                  upperNextLine.contains("MRP") ||
                  upperNextLine.contains("MANUFACTURED") ||
                  isHondaPartNo(cleanExtractedPartNo(nextLine.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')))) {
                continue;
              }
              if (nextLine == upperNextLine && nextLine.contains(RegExp(r'[A-Z]'))) {
                 productName = nextLine;
                 break;
              }
            }
          }
        }
      }
    }

    return {
      'part_no': partNo != null ? cleanExtractedPartNo(partNo) : '',
      'raw_part_no': partNo ?? '',
      'qty': qty ?? 0,
      'mrp': mrp ?? 0.0,
      'description': productName ?? '',
    };
  }

  /// Normalize string to wildcard string by replacing common confused characters
  static String _normalizeFuzzy(String s) {
    // Confusions:
    // O, 0, Q -> 0
    // 2, Z -> 2
    // 1, I, l, L -> 1
    // 5, S -> 5
    // 8, B -> 8
    // Ignore dashes and spaces
    return s
        .replaceAll(RegExp(r'[-.\s]'), '')
        .replaceAll(RegExp(r'[OQ]'), '0')
        .replaceAll('Z', '2')
        .replaceAll(RegExp(r'[IlL]'), '1')
        .replaceAll('S', '5')
        .replaceAll('B', '8');
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
    
    final queryFuzzy = _normalizeFuzzy(upperQuery);
    
    String? bestMatch;
    int matches = 0;
    
    for (final part in availableParts) {
      final partUpper = part.toUpperCase();
      if (_normalizeFuzzy(partUpper) == queryFuzzy) {
        bestMatch = part;
        matches++;
      }
    }
    
    // If exactly one fuzzy match was found, return it as confident correction
    if (matches == 1) {
      return bestMatch;
    }
    
    return null;
  }

  /// Advanced fuzzy match that utilizes the OCR location to confidently correct part numbers
  /// that might have ambiguous fuzzy matches or extreme OCR mangling (e.g., G->6, D->0).
  static String? findBestMatchWithLocation(
    String queryPartNo, 
    String queryLocation, 
    Map<String, String> dbPartLocations
  ) {
    if (queryPartNo.isEmpty || dbPartLocations.isEmpty) return null;

    final upperQueryPart = queryPartNo.toUpperCase();
    final upperQueryLoc = queryLocation.toUpperCase();
    
    // 1. Exact match on part number
    if (dbPartLocations.containsKey(upperQueryPart)) {
      return upperQueryPart;
    }
    
    final queryFuzzy = _normalizeFuzzy(upperQueryPart);
    
    String? bestMatch;
    int matches = 0;
    
    // 2. Standard Fuzzy Match (O->0, L->1, etc.)
    for (final entry in dbPartLocations.entries) {
      final partUpper = entry.key.toUpperCase();
      if (_normalizeFuzzy(partUpper) == queryFuzzy) {
        bestMatch = entry.key;
        matches++;
      }
    }
    
    if (matches == 1) {
      return bestMatch;
    }

    // 3. If multiple fuzzy matches, tie-break using location
    if (matches > 1 && upperQueryLoc.isNotEmpty) {
      for (final entry in dbPartLocations.entries) {
        final partUpper = entry.key.toUpperCase();
        final locUpper = entry.value.toUpperCase();
        
        if (_normalizeFuzzy(partUpper) == queryFuzzy && locUpper == upperQueryLoc) {
           return entry.key; // Strongest match
        }
      }
    }

    // 4. Extreme Fuzzy Match constrained by Location
    // If we have a location, we can afford a much looser fuzzy match against ONLY the parts at that location
    if (matches == 0 && upperQueryLoc.isNotEmpty) {
      final partsAtLoc = dbPartLocations.entries
          .where((e) => e.value.toUpperCase() == upperQueryLoc)
          .toList();
          
      // Even looser normalization: G <-> 6, D <-> 0, U <-> V
      String normalizeExtreme(String s) {
        return _normalizeFuzzy(s)
            .replaceAll('G', '6')
            .replaceAll('D', '0')
            .replaceAll('U', 'V');
      }
      
      final extremeQuery = normalizeExtreme(upperQueryPart);
      String? locBestMatch;
      int locMatches = 0;
      
      for (final entry in partsAtLoc) {
         if (normalizeExtreme(entry.key.toUpperCase()) == extremeQuery) {
            locBestMatch = entry.key;
            locMatches++;
         }
      }
      
      // If exactly one part at this location looks like the OCR part, take it
      if (locMatches == 1) return locBestMatch;
    }

    return null;
  }
}
