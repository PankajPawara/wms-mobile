import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'barcode_util.dart';

/// Parses Honda pickup order memo OCR text.
///
/// ─── Actual memo column layout (from raw OCR debug analysis) ───────────────
///   SR No  │ Part No        │ Description          │ MRP│QTY  │ Location │ Pack│Stock
///   x≈200  │ x≈390–930      │ x≈1034–2100          │ x≈2540–3060│ x≈3140–3400│ x≈3680+
///
/// ─── Root causes fixed ─────────────────────────────────────────────────────
///   1. MRP trailing `|` — "62.00|" → strip `|`, then match ✓
///   2. MRP split across elements — "243." + "00|" → join, strip "|" → "243.00" ✓
///   3. Y tolerance too tight (16px) — some rows differ by 20–40px → use 42px
///   4. Part no split — "150350-K24" + "-GO0" → direct concat → "150350-K24-GO0" ✓
///   5. Part no consumes multiple tokens → track how many tokens used, skip them in rest
///   6. Standalone `|` tokens from column separators → treated as empty, filtered out
class LocalOcrParser {

  // Y-tolerance for grouping elements into the same visual row.
  // Row height ≈ 80px → 42px is safe (>½ row spacing but <1 row height).
  static const double _rowTolerance = 42.0;

  // ── Location patterns ───────────────────────────────────────────────────
  static final RegExp _slotPattern = RegExp(r'^\d{3}[A-Z]$', caseSensitive: false);
  static final RegExp _boxPattern  = RegExp(r'^BOX-\d{3}$',  caseSensitive: false);

  // ── MRP: number with 2 decimal places ───────────────────────────────────
  static final RegExp _mrpFull  = RegExp(r'^(\d{1,6})[.,](\d{2})$');
  static final RegExp _mrpLeft  = RegExp(r'^(\d{1,6})[.,]$');   // "243."
  static final RegExp _mrpRight = RegExp(r'^(\d{2})$');         // "00"

  // ── Honda model codes (from reference chart) ────────────────────────────
  static const Set<String> _knownModelCodes = {
    'KPL', 'KWP', 'KOP', 'KOL', 'K24', 'K32', 'KVT', 'KRP', 'KZK', 'KOY',
    'KRB', 'K74', 'K86', 'K1J', 'KOE', 'KPP', 'KYJ',
    'KTE', 'KOV', 'K67', 'KON', 'K3C', 'KSP', 'K38', 'K1K', 'K14', 'KYY',
    'K63', 'K1E', 'K55', 'K1C', 'K43', 'K1L', 'KWF', 'KWS', 'K23', 'K21',
    'GCC',
  };

  /// Returns true if the given string is a known Honda vehicle model code.
  static bool isKnownModelCode(String segment) =>
      _knownModelCodes.contains(segment.toUpperCase());

  // ─── Public API ─────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> parseTable(RecognizedText recognizedText) {
    final items = <Map<String, dynamic>>[];

    // 1. Flatten all TextElements from all blocks/lines
    final List<TextElement> allElements = [];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        allElements.addAll(line.elements);
      }
    }
    if (allElements.isEmpty) return items;

    // 2. Sort all elements top-to-bottom
    allElements.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    // 3. Group elements into visual rows using Y-tolerance
    final rows = _groupIntoRows(allElements);

    // 4. For each row, sort left-to-right and extract data
    final foundPartNos = <String>{};
    for (final row in rows) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      final item = _extractFromTokens(row);
      if (item != null && foundPartNos.add(item['part_no'] as String)) {
        items.add(item);
      }
    }

    return items;
  }

  // ─── Row grouping ────────────────────────────────────────────────────────

  static List<List<TextElement>> _groupIntoRows(List<TextElement> sorted) {
    final rows = <List<TextElement>>[];
    var current = [sorted.first];

    for (int i = 1; i < sorted.length; i++) {
      final el = sorted[i];
      // Use running average Y of current row as the reference
      final rowY = current.map((e) => e.boundingBox.center.dy).reduce((a, b) => a + b) / current.length;
      if ((el.boundingBox.center.dy - rowY).abs() <= _rowTolerance) {
        current.add(el);
      } else {
        rows.add(current);
        current = [el];
      }
    }
    if (current.isNotEmpty) rows.add(current);
    return rows;
  }

  // ─── Core token extraction ───────────────────────────────────────────────

  /// Extract part no, description, MRP, qty, location from a left-sorted token list.
  static Map<String, dynamic>? _extractFromTokens(List<TextElement> row) {
    // Sanitise: strip leading/trailing `|` from every token, drop blank ones
    final tokens = row.where((e) {
      final text = e.text.replaceAll(RegExp(r'^[|\s]+|[|\s]+$'), '').trim();
      return text.isNotEmpty;
    }).toList();

    if (tokens.isEmpty) return null;

    // ── Step 1: Find Honda part number ───────────────────────────────────
    int partIdx = -1;
    int partLen = 1;   // how many tokens consumed by the part no
    String partNo = '';

    for (int i = 0; i < tokens.length; i++) {
      final t0 = tokens[i].text.replaceAll(RegExp(r'^[|\s]+|[|\s]+$'), '').trim();
      if (_tryPartNo(t0) case final p?) {
        partIdx = i; partLen = 1; partNo = p; break;
      }
      if (i + 1 < tokens.length) {
        final t1 = tokens[i+1].text.replaceAll(RegExp(r'^[|\s]+|[|\s]+$'), '').trim();
        if (_tryPartNo(t0 + t1) case final p?) {
          partIdx = i; partLen = 2; partNo = p; break;
        }
      }
      if (i + 2 < tokens.length) {
        final t1 = tokens[i+1].text.replaceAll(RegExp(r'^[|\s]+|[|\s]+$'), '').trim();
        final t2 = tokens[i+2].text.replaceAll(RegExp(r'^[|\s]+|[|\s]+$'), '').trim();
        if (_tryPartNo(t0 + t1 + t2) case final p?) {
          partIdx = i; partLen = 3; partNo = p; break;
        }
      }
    }

    if (partIdx == -1) return null;

    // ── Step 2: Work with tokens to the right of part number ─────────────
    final rest = tokens.sublist(partIdx + partLen);

    // ── Step 3: Find MRP ─────────────────────────────────────────────────
    int mrpIdx = -1;    // index in `rest`
    int mrpEnd = -1;    // last index consumed (for split decimals)
    double mrp = 0.0;
    double mrpCandidate = 0.0; // tentative integer MRP

    for (int i = 0; i < rest.length; i++) {
      final t = rest[i].text.replaceAll(RegExp(r'^[|\s]+|[|\s]+$'), '').trim();

      final dm = _mrpFull.firstMatch(t);
      if (dm != null) {
        final val = double.tryParse('${dm.group(1)}.${dm.group(2)}') ?? 0.0;
        if (val > 5) { mrp = val; mrpIdx = i; mrpEnd = i; break; }
      }

      if (_mrpLeft.hasMatch(t) && i + 1 < rest.length) {
        final nextT = rest[i + 1].text.replaceAll(RegExp(r'^[|\s]+|[|\s]+$'), '').trim();
        if (_mrpRight.hasMatch(nextT)) {
          final combined = t.replaceAll(',', '.') + nextT;
          final val = double.tryParse(combined) ?? 0.0;
          if (val > 5) { mrp = val; mrpIdx = i; mrpEnd = i + 1; break; }
        }
      }

      final intVal = int.tryParse(t);
      if (intVal != null && intVal > 10 && intVal < 100000 && i > 0 && mrpCandidate == 0.0) {
        mrpCandidate = intVal.toDouble();
        mrpIdx = i; mrpEnd = i;
      }
    }

    if (mrp == 0.0 && mrpCandidate > 0) mrp = mrpCandidate;

    // ── Step 4: Description = tokens between part no and MRP ─────────────
    String description = '';
    if (mrpIdx > 0) {
      final descTokens = rest.sublist(0, mrpIdx).map((e) => e.text.replaceAll(RegExp(r'^[|\s]+|[|\s]+$'), '').trim());
      description = descTokens.join(' ').trim();
    } else if (mrpIdx == -1 && rest.isNotEmpty) {
      final descTokens = rest
          .map((e) => e.text.replaceAll(RegExp(r'^[|\s]+|[|\s]+$'), '').trim())
          .where((t) => _extractLocation(t) == null)
          .take(5);
      description = descTokens.join(' ').trim();
    }

    // ── Step 5: QTY — small integer immediately after MRP ────────────────
    final afterMrp = mrpEnd >= 0 ? rest.sublist(mrpEnd + 1) : <TextElement>[];
    int qty = 1;
    int qtyIdx = -1;
    
    // MRP token X-coordinate and width to measure relative distance
    final double mrpRightX = mrpEnd >= 0 ? rest[mrpEnd].boundingBox.right : 0.0;
    final double mrpWidth = mrpEnd >= 0 ? rest[mrpEnd].boundingBox.width : 0.0;
    // Max gap allowed between MRP and Qty (scale-independent)
    final double maxQtyGap = mrpWidth > 0 ? mrpWidth * 3.0 : 800.0;

    for (int i = 0; i < afterMrp.length; i++) {
      final el = afterMrp[i];
      final t = el.text.replaceAll(RegExp(r'^[|\s]+|[|\s]+$'), '').trim();
      
      // If the distance from MRP to this token is excessively large, 
      // it means the QTY column was completely empty and this token is likely Pack/Stock.
      // So we skip it as a candidate for Qty.
      if (mrpRightX > 0 && (el.boundingBox.left - mrpRightX) > maxQtyGap) {
         continue; 
      }

      final normalized = _normNum(t);
      final parsed = int.tryParse(normalized);
      if (parsed != null && parsed >= 1 && parsed <= 99) {
        if (_extractLocation(t) == null) {
          qty = parsed;
          qtyIdx = i;
          break;
        }
      }
    }

    // ── Step 6: Location — scan after QTY (or after MRP if no QTY) ───────
    final afterQty = qtyIdx >= 0 ? afterMrp.sublist(qtyIdx + 1) : afterMrp;
    String location = '';

    for (final el in afterQty) {
      final tok = el.text.replaceAll(RegExp(r'^[|\s]+|[|\s]+$'), '').trim();
      final loc = _extractLocation(tok);
      if (loc != null) { location = loc; break; }
    }

    if (location.isEmpty) {
      for (int i = 0; i < afterQty.length - 1; i++) {
        final t1 = afterQty[i].text.replaceAll(RegExp(r'^[|\s]+|[|\s]+$'), '').trim();
        final t2 = afterQty[i+1].text.replaceAll(RegExp(r'^[|\s]+|[|\s]+$'), '').trim();
        final loc = _extractLocation(t1 + t2);
        if (loc != null) { location = loc; break; }
      }
    }

    return {
      'part_no': partNo,
      'description': description,
      'mrp': mrp,
      'qty': qty,
      'location': location,
    };
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// Try to extract a valid Honda part number from a raw string.
  /// Returns the cleaned part no, or null if not a valid Honda part no.
  static String? _tryPartNo(String raw) {
    final cleaned = BarcodeUtil.cleanExtractedPartNo(raw);
    return BarcodeUtil.isHondaPartNo(cleaned) ? cleaned : null;
  }

  /// Normalise a numeric token: O→0, I/l/L→1, comma→period.
  static String _normNum(String t) => t
      .replaceAll(RegExp(r'[Oo]'), '0')
      .replaceAll(RegExp(r'[IlL]'), '1')
      .replaceAll(',', '.');

  /// Try to extract a valid location code from a token.
  /// Accepted: `\d{3}[A-Z]` (e.g. 003K) or `BOX-\d{3}` (e.g. BOX-001).
  static String? _extractLocation(String raw) {
    final s = raw.replaceAll(RegExp(r'[|\s]'), '').toUpperCase();
    final sNorm = s.replaceAll('B0X', 'BOX');

    // BOX-NNN (check first — longer, more specific)
    if (_boxPattern.hasMatch(sNorm)) return sNorm;
    final boxM = RegExp(r'(BOX-\d{3})', caseSensitive: false).firstMatch(sNorm);
    if (boxM != null) return boxM.group(1)!.toUpperCase();

    // \d{3}[A-Z] slot code
    if (_slotPattern.hasMatch(s)) return s;

    // Leading `1` was OCR reading of `|` (e.g. "1003T" → "003T")
    if (s.length == 5 && s.startsWith('1')) {
      final candidate = s.substring(1);
      if (_slotPattern.hasMatch(candidate)) return candidate;
    }

    // Scan inside a longer token (e.g. "11073J" → "073J", "51311X" → "311X")
    final slotM = RegExp(r'(\d{3}[A-Z])', caseSensitive: false).firstMatch(s);
    if (slotM != null) return slotM.group(1)!.toUpperCase();

    return null;
  }
}
