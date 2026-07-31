/// Parser for Honda Parts & Accessories red labels.
///
/// Label format:
///   33610KSP860          Quantity: 1 Number(s)
///   Product : STAY COMP, FR WINKER
///   Manufactured in : MAY 2026
///   MRP : Rs.133.00 incl. of all taxes
///   SMS 2R8MB3I0QZRV to +91...
///
/// Scan strategy:
///   1. QR code scan  -> part number (primary, fast, no OCR needed)
///   2. ML Kit OCR    -> remaining fields from surrounding text
library;

/// Parsed data from a Honda red label.
class RedLabelData {
  /// Raw barcode string as scanned from QR (no dashes), e.g. "33610KSP860".
  final String partNoRaw;

  /// Normalized part number with dashes, e.g. "33610-KSP-860".
  final String partNoNorm;

  /// Product description from the label, e.g. "STAY COMP, FR WINKER".
  final String description;

  /// Manufacturing month string, e.g. "MAY".
  final String mfgMonth;

  /// Manufacturing year string, e.g. "2026".
  final String mfgYear;

  /// MRP value (numeric only), e.g. 133.00.
  final double mrp;

  /// Quantity printed on label.
  final int qty;

  const RedLabelData({
    required this.partNoRaw,
    required this.partNoNorm,
    required this.description,
    required this.mfgMonth,
    required this.mfgYear,
    required this.mrp,
    required this.qty,
  });

  bool get isValid => partNoRaw.isNotEmpty && mrp > 0;

  Map<String, dynamic> toJson() => {
    'partNoRaw':   partNoRaw,
    'partNoNorm':  partNoNorm,
    'description': description,
    'mfgMonth':    mfgMonth,
    'mfgYear':     mfgYear,
    'mrp':         mrp,
    'qty':         qty,
  };

  @override
  String toString() =>
      'RedLabelData(part=$partNoNorm, desc=$description, mfg=$mfgMonth $mfgYear, mrp=$mrp, qty=$qty)';
}

class RedLabelParser {
  // ---------------------------------------------------------------------------
  // Normalize a raw Honda part number barcode to dash format.
  //   "33610KSP860"   -> "33610-KSP-860"
  //   "64304K0PD00ZZ" -> "64304-K0P-D00ZZ"
  // This is the canonical form used as the primary key in PartsMaster.
  // ---------------------------------------------------------------------------
  static String normalizePart(String raw) {
    final s = raw.replaceAll('-', '').trim().toUpperCase();
    if (s.length < 8) return s;
    final prefix = s.substring(0, 5);
    final mid    = s.substring(5, 8);
    final suffix = s.substring(8);
    return '$prefix-$mid-$suffix';
  }

  // ---------------------------------------------------------------------------
  // Parse the full OCR text of a Honda red label.
  //
  // When the QR code is already scanned (primary path), pass the decoded
  // QR string as [qrPartNo]. The OCR text is still needed for the other fields.
  //
  // When only OCR is available (fallback), pass [qrPartNo] as empty string
  // and the parser will attempt to extract the part number from the text.
  // ---------------------------------------------------------------------------
  static RedLabelData parse(String ocrText, {String qrPartNo = ''}) {
    final text = ocrText.replaceAll('\n', ' ').replaceAll('\r', ' ');

    // ---- Part Number --------------------------------------------------------
    String partNoRaw = qrPartNo.trim();
    if (partNoRaw.isEmpty) {
      // Fallback: first token that looks like a Honda part number (8-14 alphanumeric)
      final partMatch = RegExp(r'\b([A-Z0-9]{8,14})\b').firstMatch(text.toUpperCase());
      partNoRaw = partMatch?.group(1) ?? '';
    }
    final partNoNorm = normalizePart(partNoRaw);

    // ---- Quantity -----------------------------------------------------------
    // "Quantity: 1 Number(s)"  or  "Qty: 10"
    int qty = 1;
    final qtyMatch = RegExp(
      r'Quantity\s*[:\-]?\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (qtyMatch != null) {
      qty = int.tryParse(qtyMatch.group(1)!) ?? 1;
    }

    // ---- Description --------------------------------------------------------
    // "Product : STAY COMP, FR WINKER"
    String description = '';
    final descMatch = RegExp(
      r'Product\s*[:\-]\s*([A-Z,\.\s/\-]+?)(?=Manufactured|MRP|$)',
      caseSensitive: false,
    ).firstMatch(text);
    if (descMatch != null) {
      description = descMatch.group(1)!.trim();
    }

    // ---- Manufacturing Date -------------------------------------------------
    // "Manufactured in : MAY 2026"
    String mfgMonth = '';
    String mfgYear  = '';
    final mfgMatch = RegExp(
      r'Manufactured\s+in\s*[:\-]\s*([A-Z]+)\s+(\d{4})',
      caseSensitive: false,
    ).firstMatch(text);
    if (mfgMatch != null) {
      mfgMonth = mfgMatch.group(1)!.toUpperCase();
      mfgYear  = mfgMatch.group(2)!;
    }

    // ---- MRP ----------------------------------------------------------------
    // "MRP : Rs.133.00 incl."  or  "MRP : ₹133.00"
    double mrp = 0.0;
    final mrpMatch = RegExp(
      r'MRP\s*[:\-]\s*(?:Rs\.?|₹|INR)?\s*([\d,]+\.?\d*)',
      caseSensitive: false,
    ).firstMatch(text);
    if (mrpMatch != null) {
      mrp = double.tryParse(mrpMatch.group(1)!.replaceAll(',', '')) ?? 0.0;
    }

    return RedLabelData(
      partNoRaw:   partNoRaw,
      partNoNorm:  partNoNorm,
      description: description,
      mfgMonth:    mfgMonth,
      mfgYear:     mfgYear,
      mrp:         mrp,
      qty:         qty,
    );
  }
}
