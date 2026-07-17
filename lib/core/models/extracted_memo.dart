/// Strongly-typed models for the memo OCR pipeline.
/// Replaces the raw Map<String, dynamic> approach throughout the OCR feature.

/// Confidence level for a DB-validated part number.
enum MatchConfidence {
  exact,       // 100% — exact DB match
  normalized,  // 95%  — match after stripping dashes/spaces
  fuzzy,       // 85%  — match after OCR character correction
  gemini,      // varies — validated by Gemini (still DB-confirmed after)
  unmatched,   // 0%   — no DB record found at all
}

extension MatchConfidenceExt on MatchConfidence {
  int get score => switch (this) {
    MatchConfidence.exact      => 100,
    MatchConfidence.normalized => 95,
    MatchConfidence.fuzzy      => 85,
    MatchConfidence.gemini     => 80,
    MatchConfidence.unmatched  => 0,
  };

  String get label => switch (this) {
    MatchConfidence.exact      => 'DB Exact',
    MatchConfidence.normalized => 'DB Normalized',
    MatchConfidence.fuzzy      => 'DB Fuzzy',
    MatchConfidence.gemini     => 'Gemini Verified',
    MatchConfidence.unmatched  => 'Unmatched',
  };

  bool get needsGemini => this == MatchConfidence.unmatched;
}

/// One row from the memo table after full pipeline processing.
class ExtractedMemoItem {
  /// Raw OCR text exactly as ML Kit returned it.
  final String rawOcrPartNo;

  /// Part number after normalization + OCR correction.
  final String correctedPartNo;

  /// Whether [correctedPartNo] != [rawOcrPartNo].
  bool get wasCorrected => rawOcrPartNo != correctedPartNo;

  final MatchConfidence confidence;
  final String description;
  final double mrp;
  final int qty;
  final String location;
  final int pack;
  final int stock;

  const ExtractedMemoItem({
    required this.rawOcrPartNo,
    required this.correctedPartNo,
    required this.confidence,
    required this.description,
    required this.mrp,
    required this.qty,
    required this.location,
    required this.pack,
    required this.stock,
  });

  ExtractedMemoItem copyWith({
    String? rawOcrPartNo,
    String? correctedPartNo,
    MatchConfidence? confidence,
    String? description,
    double? mrp,
    int? qty,
    String? location,
    int? pack,
    int? stock,
  }) {
    return ExtractedMemoItem(
      rawOcrPartNo:   rawOcrPartNo   ?? this.rawOcrPartNo,
      correctedPartNo: correctedPartNo ?? this.correctedPartNo,
      confidence:     confidence     ?? this.confidence,
      description:    description    ?? this.description,
      mrp:            mrp            ?? this.mrp,
      qty:            qty            ?? this.qty,
      location:       location       ?? this.location,
      pack:           pack           ?? this.pack,
      stock:          stock          ?? this.stock,
    );
  }

  /// Convert to the Map format expected by OrderRepository.createLocalOrder()
  Map<String, dynamic> toOrderItemMap() => {
    'part_no':      correctedPartNo,
    'description':  description,
    'location':     location,
    'required_qty': qty,
    'unit_price':   mrp,
  };
}

/// Extracted header fields from the top of the memo.
class ExtractedMemoHeader {
  final String customerName;
  final String area;
  final String memoNumber;
  final String? memoDate; // ISO-8601 date string or null if not found

  const ExtractedMemoHeader({
    required this.customerName,
    required this.area,
    required this.memoNumber,
    this.memoDate,
  });

  ExtractedMemoHeader copyWith({
    String? customerName,
    String? area,
    String? memoNumber,
    String? memoDate,
  }) {
    return ExtractedMemoHeader(
      customerName: customerName ?? this.customerName,
      area:         area         ?? this.area,
      memoNumber:   memoNumber   ?? this.memoNumber,
      memoDate:     memoDate     ?? this.memoDate,
    );
  }
}

/// Full result of the memo OCR pipeline.
class MemoOcrResult {
  final ExtractedMemoHeader header;
  final List<ExtractedMemoItem> items;
  final String rawOcrDump; // Full ML Kit text output for debug panel
  final String? imagePath;

  const MemoOcrResult({
    required this.header,
    required this.items,
    required this.rawOcrDump,
    this.imagePath,
  });

  int get verifiedCount =>
      items.where((i) => i.confidence != MatchConfidence.unmatched).length;
  int get unmatchedCount =>
      items.where((i) => i.confidence == MatchConfidence.unmatched).length;
  bool get needsGemini => unmatchedCount > 0;
}
