void main() {
  final lines = [
    '35010-W1-B02 SWITCH 120.00 2 BOX-001',
    '14566-086-030 CAM CHAIN 55.00 1 001A',
    '35010-W1-B02 SWITCH 120.0O 2 BOX - 001',
    '08234-2MA-0SM OIL 1L 205.00 10 206D',
    '2541.01 gs2.0 227.00Y 294. 223.08N 52.00 32,00 2',
    '12251-KWF-900(H)1 GASKET 15.00 001B', // missing qty
    '12251-KWF-900 GASKET 15.00', // missing qty and loc
  ];

  final locRegex = RegExp(r'\b([O0-9]{3}[A-Za-z]|BOX\s*-?\s*\d{3})[A-Za-z\.]?\s*$', caseSensitive: false);
  final qtyRegex = RegExp(r'\s+([O0-9]{1,4}[A-Za-z]?)\s*$');
  final mrpRegex = RegExp(r'\s+([\d,]+[\.,][0O\d]{1,2}[A-Za-z]?)\s*$');

  for (String line in lines) {
    String original = line;
    String loc = '';
    String qty = '';
    String mrp = '';

    // Extract Loc
    final locMatch = locRegex.firstMatch(line);
    if (locMatch != null) {
      loc = locMatch.group(1)!;
      line = line.substring(0, locMatch.start);
    }

    // Extract QTY
    final qtyMatch = qtyRegex.firstMatch(line);
    if (qtyMatch != null) {
      qty = qtyMatch.group(1)!;
      line = line.substring(0, qtyMatch.start);
    }

    // Extract MRP
    final mrpMatch = mrpRegex.firstMatch(line);
    if (mrpMatch != null) {
      mrp = mrpMatch.group(1)!;
      line = line.substring(0, mrpMatch.start);
    }
    
    // Extract SR
    final srRegex = RegExp(r'^\s*([0-9]{1,3})\s+');
    String sr = '';
    final srMatch = srRegex.firstMatch(line);
    if (srMatch != null) {
      sr = srMatch.group(1)!;
      line = line.substring(srMatch.end);
    }

    print('Original: $original');
    print('Remaining (Part+Desc): $line');
    print('SR: $sr');
    print('LOC: $loc');
    print('QTY: $qty');
    print('MRP: $mrp');
    print('---');
  }
}
