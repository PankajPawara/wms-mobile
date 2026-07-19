import 'dart:io';
import 'dart:math' as math;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../database/app_database.dart';
import '../models/extracted_memo.dart';
import 'candidate_generator.dart';

// =============================================================================
// DOCUMENT LAYOUT PARSER (MEMO OCR ENGINE)
// Coordinate-aware pipeline for extracting pickup list data from memo images.
// =============================================================================

/// A single OCR word with its position.
class OcrWord {
  final String text;
  final int left;
  final int top;
  final int right;
  final int bottom;

  const OcrWord({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  int get midX => (left + right) ~/ 2;
  int get midY => (top + bottom) ~/ 2;
  int get height => bottom - top;
}

/// A group of OcrWords on the same row (similar Y coordinate).
class OcrRow {
  final List<OcrWord> words;
  final int approximateY;

  const OcrRow({required this.words, required this.approximateY});

  /// Full text of the row, words joined by spaces.
  String get fullText => words.map((w) => w.text).join(' ');

  /// True if row appears to be a table header (contains known column headers).
  bool get isHeaderRow {
    final upper = fullText.toUpperCase();
    int matchCount = 0;
    if (upper.contains('PART')) matchCount++;
    if (upper.contains('DESC')) matchCount++;
    if (upper.contains('MRP')) matchCount++;
    if (upper.contains('QTY')) matchCount++;
    if (upper.contains('LOC')) matchCount++;
    if (upper.contains('PACK') || upper.contains('PKT')) matchCount++;
    if (upper.contains('STOCK') || upper.contains('STK')) matchCount++;
    return matchCount >= 2;
  }
}

/// X-boundaries for each column derived from the header row.
class ColumnLayout {
  final int srEnd;
  final int partNoEnd;
  final int descEnd;
  final int mrpEnd;
  final int qtyEnd;
  final int locationEnd;
  final int packEnd;

  const ColumnLayout({
    required this.srEnd,
    required this.partNoEnd,
    required this.descEnd,
    required this.mrpEnd,
    required this.qtyEnd,
    required this.locationEnd,
    required this.packEnd,
  });

  String columnFor(OcrWord word) {
    final x = word.midX;
    if (x < srEnd)       return 'sr';
    if (x < partNoEnd)   return 'partNo';
    if (x < descEnd)     return 'desc';
    if (x < mrpEnd)      return 'mrp';
    if (x < qtyEnd)      return 'qty';
    if (x < locationEnd) return 'location';
    if (x < packEnd)     return 'pack';
    return 'stock';
  }
}

// =============================================================================
// OCR CORRECTION (database-justified)
// =============================================================================

String _safeCorrect(String s) =>
    s.replaceAll('O', '0').replaceAll('Q', '0').replaceAll('I', '1');

String _applyOcrCorrection(String normalized) {
  String result = _safeCorrect(normalized);
  final dashIdx = result.indexOf('-');
  if (dashIdx > 0) {
    final prefix = result.substring(0, dashIdx);
    final suffix = result.substring(dashIdx);
    final strippedPrefix = prefix.replaceAll(RegExp(r'[SBZGLE]'), '');
    if (RegExp(r'^\d*$').hasMatch(strippedPrefix) &&
        prefix.length >= 4 &&
        prefix.length <= 6) {
      final correctedPrefix = prefix
          .replaceAll('S', '5')
          .replaceAll('B', '8')
          .replaceAll('Z', '2')
          .replaceAll('G', '6')
          .replaceAll('L', '1')
          .replaceAll('E', '3');
      result = correctedPrefix + suffix;
    }
  }
  return result;
}

String _normalizePartNo(String raw) {
  return raw
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[\.\s]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'[^A-Z0-9\-]'), '')
      .trim();
}

final _partNoPattern = RegExp(
  r'\b[A-Z0-9]{4,7}[.\s\-]*[A-Z0-9]{3}(?:[.\s\-]*[A-Z0-9]{2,7})?\b',
);

final _pricePattern = RegExp(r'\b(\d{2,6}(?:[\.,]\d{2})?)\b');

// =============================================================================
// DOCUMENT LAYOUT ENGINE
// =============================================================================

class MemoOcrEngine {
  MemoOcrEngine._();

  static const int _yThreshold = 28;

  static Future<({List<OcrWord> headerWords, List<OcrRow> tableRows, String rawDump})> runOcr(File imageFile) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognized = await textRecognizer.processImage(inputImage);

      final allWords = <OcrWord>[];
      final dumpBuffer = StringBuffer();

      int maxImageX = 0;
      int maxImageY = 0;
      double sumDx = 0;
      double sumDy = 0;

      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          if (line.elements.length > 1) {
            final first = line.elements.first.boundingBox;
            final last = line.elements.last.boundingBox;
            if (first != null && last != null) {
              sumDx += (last.center.dx - first.center.dx);
              sumDy += (last.center.dy - first.center.dy);
            }
          }
          for (final element in line.elements) {
            final bb = element.boundingBox;
            if (bb == null) continue;
            if (bb.right > maxImageX) maxImageX = bb.right.toInt();
            if (bb.bottom > maxImageY) maxImageY = bb.bottom.toInt();
          }
        }
      }

      int coarseRotation = 0;
      if (sumDx.abs() > sumDy.abs()) {
        coarseRotation = sumDx > 0 ? 0 : 180;
      } else if (sumDy.abs() > sumDx.abs()) {
        coarseRotation = sumDy > 0 ? 90 : 270;
      }

      double sumAngle = 0;
      int angleCount = 0;

      // Second pass to find fine skew angle AFTER assuming coarse rotation
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          if (line.elements.length > 1) {
            final first = line.elements.first.boundingBox;
            final last = line.elements.last.boundingBox;
            if (first != null && last != null) {
              double fx = first.center.dx; double fy = first.center.dy;
              double lx = last.center.dx; double ly = last.center.dy;
              double temp;
              // Simulate coarse rotation
              if (coarseRotation == 180) {
                fx = maxImageX - fx; fy = maxImageY - fy;
                lx = maxImageX - lx; ly = maxImageY - ly;
              } else if (coarseRotation == 90) {
                temp = fx; fx = fy; fy = maxImageX - temp;
                temp = lx; lx = ly; ly = maxImageX - temp;
              } else if (coarseRotation == 270) {
                temp = fx; fx = maxImageY - fy; fy = temp;
                temp = lx; lx = maxImageY - ly; ly = temp;
              }
              
              double dx = lx - fx;
              double dy = ly - fy;
              
              // Only consider roughly horizontal lines for skew
              if (dx.abs() > dy.abs()) {
                sumAngle += math.atan2(dy, dx);
                angleCount++;
              }
            }
          }
        }
      }

      double skewAngle = angleCount > 0 ? sumAngle / angleCount : 0;
      
      // Calculate new center for skew rotation
      double rotatedImageWidth = (coarseRotation == 90 || coarseRotation == 270) ? maxImageY.toDouble() : maxImageX.toDouble();
      double rotatedImageHeight = (coarseRotation == 90 || coarseRotation == 270) ? maxImageX.toDouble() : maxImageY.toDouble();
      double cx = rotatedImageWidth / 2;
      double cy = rotatedImageHeight / 2;

      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            final bb = element.boundingBox;
            if (bb == null) continue;

            int left = bb.left.toInt();
            int top = bb.top.toInt();
            int right = bb.right.toInt();
            int bottom = bb.bottom.toInt();
            int newLeft, newTop, newRight, newBottom;

            // 1. Coarse rotation
            if (coarseRotation == 0) {
              newLeft = left; newTop = top; newRight = right; newBottom = bottom;
            } else if (coarseRotation == 180) {
              newLeft = maxImageX - right;
              newRight = maxImageX - left;
              newTop = maxImageY - bottom;
              newBottom = maxImageY - top;
            } else if (coarseRotation == 90) {
              newLeft = top;
              newRight = bottom;
              newTop = maxImageX - right;
              newBottom = maxImageX - left;
            } else { // 270
              newLeft = maxImageY - bottom;
              newRight = maxImageY - top;
              newTop = left;
              newBottom = right;
            }

            // 2. Fine skew rotation
            double rotateX(double x, double y) =>
                cx + (x - cx) * math.cos(-skewAngle) - (y - cy) * math.sin(-skewAngle);
            double rotateY(double x, double y) =>
                cy + (x - cx) * math.sin(-skewAngle) + (y - cy) * math.cos(-skewAngle);

            int finalLeft = rotateX(newLeft.toDouble(), newTop.toDouble()).toInt();
            int finalRight = rotateX(newRight.toDouble(), newBottom.toDouble()).toInt();
            int finalTop = rotateY(newLeft.toDouble(), newTop.toDouble()).toInt();
            int finalBottom = rotateY(newRight.toDouble(), newBottom.toDouble()).toInt();

            if (finalLeft > finalRight) {
              final t = finalLeft; finalLeft = finalRight; finalRight = t;
            }
            if (finalTop > finalBottom) {
              final t = finalTop; finalTop = finalBottom; finalBottom = t;
            }

            allWords.add(OcrWord(
              text: element.text,
              left: finalLeft,
              top: finalTop,
              right: finalRight,
              bottom: finalBottom,
            ));
            dumpBuffer.write('[x=$finalLeft, y=$finalTop] ${element.text} ');
          }
          dumpBuffer.writeln();
        }
      }

      allWords.sort((a, b) => a.midY.compareTo(b.midY));

      final rows = <OcrRow>[];
      var currentWords = <OcrWord>[];
      int? anchorY;

      for (final word in allWords) {
        if (anchorY == null || (word.midY - anchorY).abs() <= _yThreshold) {
          currentWords.add(word);
          if (anchorY == null) anchorY = word.midY;
        } else {
          if (currentWords.isNotEmpty) {
            currentWords.sort((a, b) => a.midX - b.midX);
            rows.add(OcrRow(
              words: List.unmodifiable(currentWords),
              approximateY: anchorY!,
            ));
          }
          currentWords = [word];
          anchorY = word.midY;
        }
      }
      if (currentWords.isNotEmpty) {
        currentWords.sort((a, b) => a.midX - b.midX);
        rows.add(OcrRow(
          words: List.unmodifiable(currentWords),
          approximateY: anchorY!,
        ));
      }

      // Split into header region (above table) and table region (below)
      OcrRow? headerRow;
      for (final row in rows) {
        if (row.isHeaderRow) {
          headerRow = row;
          break;
        }
      }

      if (headerRow == null) {
        throw Exception('NO_HEADER_DETECTED');
      }

      final headerRegionWords = allWords.where((w) => w.midY < headerRow!.approximateY - 20).toList();
      final tableRows = rows.where((r) => r.approximateY >= headerRow!.approximateY - 10).toList();

      return (headerWords: headerRegionWords, tableRows: tableRows, rawDump: dumpBuffer.toString());
    } finally {
      await textRecognizer.close();
    }
  }

  static ColumnLayout detectColumns(OcrRow headerRow) {
    int? srX, partNoX, descX, mrpX, qtyX, locX, packX, stockX;
    
    for (final word in headerRow.words) {
      final upper = word.text.toUpperCase();
      if (upper.contains('SR') || upper.contains('S.R')) srX = word.midX;
      if (upper.contains('PART')) partNoX = word.midX;
      if (upper.contains('DESC')) descX = word.midX;
      if (upper.contains('MRP'))  mrpX = word.midX;
      if (upper.contains('QTY'))  qtyX = word.midX;
      if (upper.contains('LOC'))  locX = word.midX;
      if (upper.contains('PACK') || upper.contains('PKT')) packX = word.midX;
      if (upper.contains('STOCK') || upper.contains('STK')) stockX = word.midX;
    }

    // Dynamic Interpolation for missing headers
    partNoX ??= (descX != null ? descX ~/ 2 : 280);
    descX ??= (mrpX != null ? mrpX - 140 : 560);
    mrpX ??= (qtyX != null ? qtyX - 60 : 700);
    qtyX ??= (mrpX + 60);
    locX ??= (qtyX + 90);
    packX ??= (locX + 70);
    stockX ??= (packX + 70);
    srX ??= partNoX ~/ 2;

    int midpoint(int a, int b) => (a + b) ~/ 2;

    final layout = ColumnLayout(
      srEnd: midpoint(srX, partNoX),
      partNoEnd: midpoint(partNoX, descX),
      descEnd: midpoint(descX, mrpX),
      mrpEnd: midpoint(mrpX, qtyX),
      qtyEnd: midpoint(qtyX, locX),
      locationEnd: midpoint(locX, packX),
      packEnd: midpoint(packX, stockX),
    );
    print('DETECTED COLUMNS: srX=$srX, partNoX=$partNoX, descX=$descX, mrpX=$mrpX, qtyX=$qtyX, locX=$locX');
    print('LAYOUT BOUNDS: srEnd=${layout.srEnd}, partNoEnd=${layout.partNoEnd}, descEnd=${layout.descEnd}');
    return layout;
  }

  static Future<ExtractedMemoItem?> extractItemFromRow(
    OcrRow row,
    ColumnLayout cols,
    CandidateGenerator candidateGenerator,
  ) async {
    final colTexts = <String, List<String>>{
      'sr': [],
      'partNo': [],
      'desc': [],
      'mrp': [],
      'qty': [],
      'location': [],
      'pack': [],
      'stock': [],
    };
    for (final word in row.words) {
      colTexts[cols.columnFor(word)]!.add(word.text);
    }

    // Join partNo without spaces to fix split segments, and uppercase it to match regex
    final rawPartNoText = colTexts['partNo']!.join('').trim().toUpperCase();
    print('ROW COLS: SR=${colTexts['sr']} | PN=${colTexts['partNo']} | DESC=${colTexts['desc']} | MRP=${colTexts['mrp']}');
    if (rawPartNoText.isEmpty) return null;

    final partNoMatch = _partNoPattern.firstMatch(rawPartNoText);
    if (partNoMatch == null) return null;

    final rawPartNo = partNoMatch != null
        ? partNoMatch.group(0)!.replaceAll(RegExp(r'[\.\s]+'), '-').toUpperCase()
        : rawPartNoText;

    String descText = colTexts['desc']!.join(' ').trim();
    String mrpText = colTexts['mrp']!.join('').trim();
    String locationText = colTexts['location']!.join('').trim().toUpperCase();

    double mrp = 0.0;
    final priceMatch = _pricePattern.firstMatch(
        mrpText.replaceAll(RegExp(r'[Oo]'), '0').replaceAll(RegExp(r'[Il]'), '1'));
    if (priceMatch != null) {
      mrp = double.tryParse(priceMatch.group(1)!.replaceAll(',', '.')) ?? 0.0;
    }

    final cleanNum = (String s) =>
        s.replaceAll(RegExp(r'[Oo]'), '0').replaceAll(RegExp(r'[^0-9]'), '');

    String extractFirstNumber(List<String> words) {
      for (final w in words) {
        final cleaned = cleanNum(w);
        if (cleaned.isNotEmpty) return cleaned;
      }
      return '';
    }

    String qtyText = extractFirstNumber(colTexts['qty']!);
    String packText = extractFirstNumber(colTexts['pack']!);
    String stockText = extractFirstNumber(colTexts['stock']!);

    // Handle case where ML Kit merges QTY and LOCATION into one word like "2|050F" -> falls in Location column
    if (qtyText.isEmpty && locationText.isNotEmpty) {
      final parts = locationText.split(RegExp(r'[|I\\]+'));
      if (parts.length >= 2) {
        qtyText = parts[0];
        locationText = parts[1];
      } else {
        final match = RegExp(r'^(\d+)(\d{2,3}[A-Z])$').firstMatch(locationText);
        if (match != null) {
          qtyText = match.group(1)!;
          locationText = match.group(2)!;
        }
      }
    }
    
    // Handle case where MRP and QTY merge
    if (mrpText.isNotEmpty && qtyText.isEmpty) {
      final parts = mrpText.split(RegExp(r'[|I\\]+'));
      if (parts.length >= 2 && parts.last.length <= 2) {
        qtyText = parts.last;
      }
    }

    final qty = int.tryParse(cleanNum(qtyText)) ?? 1;
    final pack = int.tryParse(cleanNum(packText)) ?? 0;
    final stock = int.tryParse(cleanNum(stockText)) ?? 0;
    
    // Location Parser
    final locMatch = RegExp(r'\d{2,3}[A-Z]').firstMatch(locationText);
    String loc = locMatch != null ? locMatch.group(0)! : locationText;
    loc = loc.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (loc.length > 4) loc = loc.substring(0, 4);

    return await candidateGenerator.findBestMatch(
      rawPartNo: rawPartNo,
      description: descText,
      mrp: mrp,
      qty: qty,
      location: loc,
      pack: pack,
      stock: stock,
    );
  }

  // ───────────────────────────────────────────────────────────────
  // SPATIAL HEADER PARSING
  // ───────────────────────────────────────────────────────────────

  static ExtractedMemoHeader extractHeaderSpatial(List<OcrWord> headerWords) {
    if (headerWords.isEmpty) {
      return ExtractedMemoHeader(
        customerName: 'OCR Generated Order',
        area: 'Warehouse Floor',
        memoNumber: 'MEMO-OCR-${DateTime.now().millisecondsSinceEpoch}',
        memoDate: null,
      );
    }
    
    // Find approximate center of the image X
    int minX = 99999;
    int maxX = 0;
    for (final w in headerWords) {
      if (w.midX < minX) minX = w.midX;
      if (w.midX > maxX) maxX = w.midX;
    }
    final centerX = (minX + maxX) ~/ 2;

    final leftSideWords = headerWords.where((w) => w.midX < centerX).toList();
    final rightSideWords = headerWords.where((w) => w.midX >= centerX).toList();

    leftSideWords.sort((a, b) => a.midY.compareTo(b.midY));
    rightSideWords.sort((a, b) => a.midY.compareTo(b.midY));

    String leftText = leftSideWords.map((w) => w.text).join(' ');
    String rightText = rightSideWords.map((w) => w.text).join(' ');

    String customerName = 'OCR Generated Order';
    final custMatch = RegExp(r'M/S\.?\s*,?\s*([^\n\r0-9]+)', caseSensitive: false).firstMatch(leftText);
    if (custMatch != null) {
      customerName = custMatch.group(1)!.trim();
      customerName = customerName.replaceAll(RegExp(r'\s+(VANSADA|SURAT|KIM|RUSTAMPURA|KOSAMBA|BILIMORA|NAVSARI|BHARUCH).*$', caseSensitive: false), '');
    }

    String area = 'Warehouse Floor';
    final areaMatch = RegExp(r'AREA\s*:\s*([A-Za-z\s]+)', caseSensitive: false).firstMatch(rightText);
    if (areaMatch != null) {
      area = areaMatch.group(1)!.trim();
    } else {
      final cityMatch = RegExp(r'(VANSADA|RUSTAMPURA|SURAT|KIM|KOSAMBA|BILIMORA|NAVSARI|BHARUCH)', caseSensitive: false).firstMatch(leftText);
      if (cityMatch != null) area = cityMatch.group(1)!.trim().toUpperCase();
    }

    String memoNumber = 'MEMO-OCR-${DateTime.now().millisecondsSinceEpoch}';
    final memoMatch = RegExp(r'MEMO\s*NO\.?\s*:?\s*(\d+)', caseSensitive: false).firstMatch(rightText);
    if (memoMatch != null) memoNumber = memoMatch.group(1)!.trim();

    String? memoDate;
    final dateMatch = RegExp(r'\b(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})\b').firstMatch(rightText);
    if (dateMatch != null) {
      try {
        final day = int.parse(dateMatch.group(1)!);
        final month = int.parse(dateMatch.group(2)!);
        var year = int.parse(dateMatch.group(3)!);
        if (year < 100) year += 2000;
        memoDate = DateTime(year, month, day).toIso8601String();
      } catch (_) {}
    }

    return ExtractedMemoHeader(
      customerName: customerName.isNotEmpty ? customerName : 'OCR Generated Order',
      area: area,
      memoNumber: memoNumber,
      memoDate: memoDate,
    );
  }

  // ───────────────────────────────────────────────────────────────
  // FULL PIPELINE RUNNER
  // ───────────────────────────────────────────────────────────────

  static Future<MemoOcrResult> process(File imageFile, AppDatabase db) async {
    final candidateGenerator = CandidateGenerator(db);
    await candidateGenerator.init();

    final (:headerWords, :tableRows, :rawDump) = await runOcr(imageFile);
    
    // We already threw NO_HEADER_DETECTED if there is no header row.
    final headerRow = tableRows.firstWhere((r) => r.isHeaderRow);
    
    final cols = detectColumns(headerRow);
    final header = extractHeaderSpatial(headerWords);

    final items = <ExtractedMemoItem>[];

    print('TOTAL ROWS EXTRACTED: ${tableRows.length}');
    print('HEADER ROW TEXT: ${headerRow.words.map((w) => w.text).join(' ')}');
    for (final row in tableRows) {
      if (row.words.isEmpty) continue;

      try {
        final item = await extractItemFromRow(row, cols, candidateGenerator);
        if (item != null) items.add(item);
      } catch (e, stack) {
        print('[MemoOcrEngine] Row extraction error: $e\n$stack');
      }
    }

    final seen = <String>{};
    final deduped = items.where((i) => seen.add(i.correctedPartNo)).toList();

    return MemoOcrResult(
      header: header,
      items: deduped,
      rawOcrDump: rawDump,
      imagePath: imageFile.path,
    );
  }
}
