class BarcodeUtil {
  BarcodeUtil._();

  // Honda part number pattern: e.g. 22201-KON-DU2
  static final RegExp _hondaPartPattern =
      RegExp(r'\b[A-Z0-9]{4,10}-[A-Z0-9]{2,10}-[A-Z0-9]{2,10}\b');

  // General numeric barcode (EAN-13, EAN-8, UPC-A)
  static final RegExp _numericBarcode = RegExp(r'\b\d{8,14}\b');

  static bool isValidBarcode(String value) {
    return _numericBarcode.hasMatch(value) ||
        _hondaPartPattern.hasMatch(value);
  }

  static bool isHondaPartNo(String value) {
    return _hondaPartPattern.hasMatch(value.toUpperCase());
  }

  /// Extract all Honda part numbers from OCR text
  static List<String> extractPartNumbers(String text) {
    final upper = text.toUpperCase();
    return _hondaPartPattern
        .allMatches(upper)
        .map((m) => m.group(0)!)
        .toSet()
        .toList();
  }

  static String formatPartNo(String raw) {
    return raw.trim().toUpperCase();
  }
}
