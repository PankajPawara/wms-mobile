import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'barcode_util.dart';

/// Parses Honda pickup order memo OCR text.
///
/// Memo table column order (left → right):
///   Sr No | Part No | Description | MRP (e.g. 62.00) | Qty | Location
///
/// Location formats:
///   • `\d{3}[A-Z]`  → e.g. 003K, 069M
///   • `BOX-\d{3}`   → e.g. BOX-001
///
/// ML Kit OCR frequently:
///   • Reads `|` as `1` or ignores it entirely
///   • Splits `62.00` into two tokens `62` and `.00` or `62` and `00`
///   • Reads `O` as `0` in alphabetic segments, `L`/`I` as `1` in numeric ones
///   • Groups multi-word descriptions differently across angles/images
///
/// Strategy — two-pass:
///   1. Element-level row grouping (geometric, using bounding boxes)
///   2. Line-level fallback using ML Kit's own TextLine grouping
///
class LocalOcrParser {
  static const double _rowTolerance = 16.0;

  // ── Honda model codes for middle-segment validation ──────────────────────
  // Source: physical reference chart on warehouse wall
  // These are the 3-char middle segments seen in part numbers
  static const Set<String> _knownModelCodes = {
    // Activa family
    'KPL', 'KWP', 'KOP', 'KOL', 'K24', 'K32',
    // Dio / Aviator
    'KVT', 'KRP', 'KZK', 'KOY',
    // Eterno / Navi / Grazia / XBlade
    'KRB', 'K74', 'K86', 'K1J', 'KOE',
    // CBR
    'KPP', 'KYJ',
    // Shine family
    'KTE', 'KOV', 'K67', 'KON', 'K3C',
    // Unicorn / Dazzler
    'KSP', 'K38', 'K1K', 'K14', 'KYY',
    // CD / Livo
    'K63', 'K1E', 'K55', 'K1C',
    // Hornet / Stunner / Twister / Dream
    'K43', 'K1L', 'KWF', 'KWS', 'K23', 'K21',
    // Memo-specific codes seen in test data
    'GCC',
  };

  /// Returns true if the given string is a known Honda vehicle model code
  /// (middle segment of a part number, e.g. KTE, GCC).
  static bool isKnownModelCode(String segment) =>
      _knownModelCodes.contains(segment.toUpperCase());

  // ── Location patterns ────────────────────────────────────────────────────
  static final RegExp _slotPattern = RegExp(r'^\d{3}[A-Z]$', caseSensitive: false);
  static final RegExp _boxPattern  = RegExp(r'^BOX-\d{3}$',  caseSensitive: false);

  // ── MRP: a decimal number, typically ending in .00 ───────────────────────
  // Flexible: accept X.00, X.50, X.XX — basically any "looks like a price"
  static final RegExp _mrpDecimal  = RegExp(r'^(\d{1,6})[.,](\d{2})$');
  // Sometimes ML Kit splits "62.00" into token "62" and token ".00" or "00"
  static final RegExp _mrpDotOnly  = RegExp(r'^\.\d{2}$');
  static final RegExp _mrpCentsOnly = RegExp(r'^\d{2}$'); // e.g. "00" after "62"

  // ─── Public API ────────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> parseTable(RecognizedText recognizedText) {
    final List<Map<String, dynamic>> items = [];

    // Pass 1: element-level geometric row grouping
    final elementItems = _parseByElements(recognizedText);
    items.addAll(elementItems);

    // Pass 2: line-level fallback — catch rows that element pass missed
    // (e.g. when a whole row is in one TextLine / TextBlock)
    final foundPartNos = items.map((i) => i['part_no'] as String).toSet();
    final lineItems = _parseByLines(recognizedText, foundPartNos);
    items.addAll(lineItems);

    return items;
  }

  // ─── Pass 1: element-level (geometric) ─────────────────────────────────────

  static List<Map<String, dynamic>> _parseByElements(RecognizedText recognizedText) {
    final List<Map<String, dynamic>> items = [];

    // Flatten all elements
    final List<TextElement> allElements = [];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        allElements.addAll(line.elements);
      }
    }
    if (allElements.isEmpty) return items;

    allElements.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    // Group into rows by Y proximity
    final rows = _groupIntoRows(allElements);

    for (final row in rows) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      final item = _extractFromTokens(row.map((e) => e.text).toList());
      if (item != null) items.add(item);
    }

    return items;
  }

  // ─── Pass 2: line-level fallback ───────────────────────────────────────────

  static List<Map<String, dynamic>> _parseByLines(
      RecognizedText recognizedText, Set<String> alreadyFound) {
    final List<Map<String, dynamic>> items = [];

    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        // Split the line text into whitespace-separated tokens
        final tokens = line.text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
        final item = _extractFromTokens(tokens);
        if (item != null && !alreadyFound.contains(item['part_no'])) {
          items.add(item);
          alreadyFound.add(item['part_no'] as String);
        }
      }
    }

    return items;
  }

  // ─── Core extraction from a token list ─────────────────────────────────────

  static Map<String, dynamic>? _extractFromTokens(List<String> tokens) {
    // ── Step 1: Find Honda part number ───────────────────────────────────────
    int partIdx = -1;
    String partNo = '';

    for (int i = 0; i < tokens.length; i++) {
      final raw = tokens[i];
      final cleaned = BarcodeUtil.cleanExtractedPartNo(raw);
      if (BarcodeUtil.isHondaPartNo(cleaned)) {
        partIdx = i;
        partNo = cleaned;
        break;
      }
      // Also try combining adjacent tokens (e.g. "12391" + "GCC-000")
      if (i + 1 < tokens.length) {
        final combined = BarcodeUtil.cleanExtractedPartNo('${raw}-${tokens[i + 1]}');
        if (BarcodeUtil.isHondaPartNo(combined)) {
          partIdx = i;
          partNo = combined;
          break;
        }
      }
    }

    if (partIdx == -1) return null;

    // ── Step 2: collect remaining tokens after part number ────────────────────
    final rest = tokens.sublist(partIdx + 1);

    // ── Step 3: scan for MRP ─────────────────────────────────────────────────
    int mrpIdx = -1;
    double mrp = 0.0;

    for (int i = 0; i < rest.length; i++) {
      final normalized = _normNum(rest[i]);

      // Case A: full decimal e.g. "62.00" or "62,00"
      final dm = _mrpDecimal.firstMatch(normalized);
      if (dm != null) {
        final val = double.tryParse('${dm.group(1)}.${dm.group(2)}') ?? 0.0;
        if (val > 5) { // MRP is always > 5 rupees
          mrp = val;
          mrpIdx = i;
          break;
        }
      }

      // Case B: ML Kit split "62" + ".00" — integer followed by ".XX" token
      if (int.tryParse(normalized) != null && int.parse(normalized) > 5) {
        // peek ahead: is next token ".00" or just "00"?
        if (i + 1 < rest.length) {
          final next = _normNum(rest[i + 1]);
          if (_mrpDotOnly.hasMatch(next) || _mrpCentsOnly.hasMatch(next)) {
            final cents = next.replaceAll('.', '');
            mrp = double.tryParse('$normalized.$cents') ?? double.parse(normalized).toDouble();
            mrpIdx = i + 1; // consume both tokens
            break;
          }
        }
        // Case C: standalone integer price (no decimal shown) if value reasonable
        final intVal = int.parse(normalized);
        if (intVal > 10 && intVal < 100000) {
          // Only accept as MRP if it's clearly not a Sr.No (not at start) and
          // not a small qty-range number
          if (i > 0 && intVal > 50) {
            mrp = intVal.toDouble();
            mrpIdx = i;
            // Don't break — prefer a decimal match later if found
          }
        }
      }
    }

    // ── Step 4: Description = tokens between part no and MRP ─────────────────
    String description = '';
    if (mrpIdx > 0) {
      final descTokens = rest.sublist(0, mrpIdx)
          .where((t) => !RegExp(r'^[1|]+$').hasMatch(t)) // skip lone pipe artefacts
          .toList();
      description = descTokens.join(' ').trim();
    } else if (rest.isNotEmpty) {
      // No MRP found — take first few tokens as description
      final descTokens = rest
          .where((t) => !RegExp(r'^[1|]+$').hasMatch(t))
          .take(4)
          .toList();
      description = descTokens.join(' ').trim();
    }

    // ── Step 5: QTY — first small integer token after MRP ────────────────────
    int qty = 1;
    int qtyIdx = -1;
    final afterMrp = mrpIdx >= 0 ? rest.sublist(mrpIdx + 1) : <String>[];

    for (int i = 0; i < afterMrp.length; i++) {
      final normalized = _normNum(afterMrp[i]);
      final parsed = int.tryParse(normalized);
      if (parsed != null && parsed >= 1 && parsed <= 99) {
        // Make sure this isn't the start of a location code like "003K"
        if (!_slotPattern.hasMatch(afterMrp[i]) && !_boxPattern.hasMatch(afterMrp[i])) {
          qty = parsed;
          qtyIdx = i;
          break;
        }
      }
    }

    // ── Step 6: Location — scan for valid location pattern ───────────────────
    String location = '';
    final afterQty = qtyIdx >= 0 ? afterMrp.sublist(qtyIdx + 1) : afterMrp;

    for (final tok in afterQty) {
      final loc = _extractLocation(tok);
      if (loc != null) {
        location = loc;
        break;
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

  // ─── Helpers ───────────────────────────────────────────────────────────────

  static List<List<TextElement>> _groupIntoRows(List<TextElement> sorted) {
    final rows = <List<TextElement>>[];
    var current = [sorted.first];

    for (int i = 1; i < sorted.length; i++) {
      final el = sorted[i];
      final rowCenter = current
          .map((e) => e.boundingBox.center.dy)
          .reduce((a, b) => a + b) /
          current.length;
      if ((el.boundingBox.center.dy - rowCenter).abs() <= _rowTolerance) {
        current.add(el);
      } else {
        rows.add(current);
        current = [el];
      }
    }
    if (current.isNotEmpty) rows.add(current);
    return rows;
  }

  /// Normalise a token that is expected to be numeric.
  static String _normNum(String t) => t
      .replaceAll(RegExp(r'[Oo]'), '0')
      .replaceAll(RegExp(r'[IlL]'), '1')
      .replaceAll(',', '.');

  /// Try to extract a valid location code from a token.
  static String? _extractLocation(String raw) {
    final s = raw.replaceAll(RegExp(r'[|\s]'), '').toUpperCase();
    final sNorm = s.replaceAll('B0X', 'BOX');

    // BOX-NNN (more specific, check first)
    if (_boxPattern.hasMatch(sNorm)) return sNorm;
    final boxM = RegExp(r'(BOX-\d{3})', caseSensitive: false).firstMatch(sNorm);
    if (boxM != null) return boxM.group(1)!.toUpperCase();

    // \d{3}[A-Z] slot code
    if (_slotPattern.hasMatch(s)) return s;
    // Spurious leading `1` (OCR read `|` as `1`)
    if (s.length == 5 && s.startsWith('1')) {
      final candidate = s.substring(1);
      if (_slotPattern.hasMatch(candidate)) return candidate;
    }
    // Scan inside longer token
    final slotM = RegExp(r'(\d{3}[A-Z])', caseSensitive: false).firstMatch(s);
    if (slotM != null) return slotM.group(1)!.toUpperCase();

    return null;
  }
}
