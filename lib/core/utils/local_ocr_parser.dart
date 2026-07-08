import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'barcode_util.dart';

/// Parses Honda pickup order memo OCR text.
///
/// Memo table column order (left to right):
///   Sr No | Part No | Description | MRP (ends in .00) | Qty | Location (3 digits + 1 letter)
///
/// ML Kit frequently:
///   - Reads `|` as `1`
///   - Confuses `L`/`I` with `1` and `O` with `0` in the 5-digit numeric prefix
///
/// Strategy:
///   1. Flatten ALL TextElements, sort by Y then X.
///   2. Group into rows using a Y-tolerance.
///   3. For each row, scan for a Honda part number (anchor).
///   4. From the part number position, scan RIGHT for:
///        - MRP: a number ending in `.00` (e.g. 62.00, 818.00)
///        - QTY: a small integer (1–99) immediately after MRP
///        - Location: exactly 4 chars matching `\d{3}[A-Z]`, possibly with
///          a spurious leading `1` (which was a `|`) → strip it.
///   5. Everything between part no and MRP → description.
class LocalOcrParser {
  static const double _rowTolerance = 14.0;

  /// Valid location pattern: exactly 3 digits then 1 uppercase letter, e.g. 003K, 023X, 069M
  static final RegExp _locPattern = RegExp(r'^\d{3}[A-Z]$', caseSensitive: false);

  /// MRP ends in .00 and is > 0
  static final RegExp _mrpPattern = RegExp(r'^(\d+)\.00$');

  // ─── Public API ────────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> parseTable(RecognizedText recognizedText) {
    final List<Map<String, dynamic>> items = [];

    // 1. Flatten all elements
    final List<TextElement> allElements = [];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        allElements.addAll(line.elements);
      }
    }
    if (allElements.isEmpty) return items;

    // 2. Sort by Y coordinate
    allElements.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    // 3. Group into rows by Y proximity
    final List<List<TextElement>> rows = _groupIntoRows(allElements);

    // 4. Extract from each row
    for (final row in rows) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      final item = _extractFromRow(row);
      if (item != null) items.add(item);
    }

    return items;
  }

  // ─── Private helpers ────────────────────────────────────────────────────────

  static List<List<TextElement>> _groupIntoRows(List<TextElement> sorted) {
    final rows = <List<TextElement>>[];
    var current = [sorted.first];

    for (int i = 1; i < sorted.length; i++) {
      final el = sorted[i];
      final rowCenter = current.map((e) => e.boundingBox.center.dy).reduce((a, b) => a + b) / current.length;
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

  static Map<String, dynamic>? _extractFromRow(List<TextElement> row) {
    // ── Step 1: Find the Honda part number ──────────────────────────────────
    int partIdx = -1;
    String partNo = '';

    for (int i = 0; i < row.length; i++) {
      final raw = row[i].text;
      // Remove OCR pipe artefacts and spaces before matching
      final cleaned = BarcodeUtil.cleanExtractedPartNo(raw);
      if (BarcodeUtil.isHondaPartNo(cleaned)) {
        partIdx = i;
        partNo = cleaned;
        break;
      }
    }

    if (partIdx == -1) return null;

    // ── Step 2: Collect all text tokens to the right of the part number ─────
    final List<String> tokens = row.sublist(partIdx + 1).map((e) => e.text.trim()).where((t) => t.isNotEmpty).toList();

    // ── Step 3: Scan tokens for MRP (a number ending in .00) ────────────────
    // Also normalise common OCR confusions on digit tokens
    int mrpTokenIdx = -1;
    double mrp = 0.0;

    for (int i = 0; i < tokens.length; i++) {
      final normalized = _normalizeDigitToken(tokens[i]);
      final m = _mrpPattern.firstMatch(normalized);
      if (m != null) {
        mrp = double.parse(normalized);
        mrpTokenIdx = i;
        break;
      }
    }

    // ── Step 4: Build description (tokens between part no and MRP) ──────────
    String description = '';
    if (mrpTokenIdx > 0) {
      // Collect tokens before MRP, strip leading OCR pipe artefacts (`1` that
      // are actually `|`, detected as token equal to "1" or "|")
      final descTokens = tokens.sublist(0, mrpTokenIdx).where((t) {
        // Drop tokens that look like OCR pipe artefacts
        return !RegExp(r'^\|?1?\|?$').hasMatch(t);
      }).toList();
      description = descTokens.join(' ').trim();
    }

    // ── Step 5: QTY – small integer token immediately after MRP ─────────────
    int qty = 1;
    int qtyTokenIdx = -1;
    if (mrpTokenIdx != -1 && mrpTokenIdx + 1 < tokens.length) {
      final rawQty = _normalizeDigitToken(tokens[mrpTokenIdx + 1]);
      final parsed = int.tryParse(rawQty);
      if (parsed != null && parsed >= 1 && parsed <= 99) {
        qty = parsed;
        qtyTokenIdx = mrpTokenIdx + 1;
      }
    }

    // ── Step 6: Location – exactly 4 chars: 3 digits + 1 letter ────────────
    String location = '';
    final int locSearchStart = (qtyTokenIdx != -1) ? qtyTokenIdx + 1 : (mrpTokenIdx != -1 ? mrpTokenIdx + 1 : 0);
    for (int i = locSearchStart; i < tokens.length; i++) {
      final candidate = _extractLocation(tokens[i]);
      if (candidate != null) {
        location = candidate;
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

  /// Normalise a token that should be purely numeric.
  /// Replaces `O`/`o` → `0`, `I`/`l`/`|` → `1`, commas → periods.
  static String _normalizeDigitToken(String t) {
    return t
        .replaceAll(RegExp(r'[Oo]'), '0')
        .replaceAll(RegExp(r'[IlL\|]'), '1')
        .replaceAll(',', '.');
  }

  /// Attempt to extract a valid 4-char location code (3 digits + 1 letter)
  /// from a raw OCR token.  The token may have a spurious leading `1` (which
  /// was a `|`) or a trailing `|`.
  static String? _extractLocation(String raw) {
    // Strip common noise characters
    String s = raw.replaceAll(RegExp(r'[\|\s]'), '').toUpperCase();

    // Direct hit
    if (_locPattern.hasMatch(s)) return s;

    // If 5 chars and starts with '1' → the `1` was a `|`, strip it
    if (s.length == 5 && s.startsWith('1')) {
      final candidate = s.substring(1);
      if (_locPattern.hasMatch(candidate)) return candidate;
    }

    // Regex scan inside a longer token
    final m = RegExp(r'(\d{3}[A-Z])', caseSensitive: false).firstMatch(s);
    if (m != null) return m.group(1)!.toUpperCase();

    return null;
  }
}
