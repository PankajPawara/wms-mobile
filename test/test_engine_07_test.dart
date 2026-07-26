import 'package:flutter_test/flutter_test.dart';
import 'package:wms_mobile/core/pipeline/engine_07_row.dart';
import 'package:wms_mobile/core/pipeline/engine_06_cell.dart';
import 'package:wms_mobile/core/pipeline/engine_05_grid.dart';
import 'package:wms_mobile/core/pipeline/engine_04_table_detection.dart';

void main() {
  test('Engine07 - Full real E06 data from device (JAY KHODIYAR memo)', () async {
    // This is the exact E06 data from the device log for memo 11720
    // Expected output (from actual image):
    // SR1: 61102-KTE-910 | STAY FR.FENDER  | 77.00  | 5  | 001L | 1 | 166
    // SR2: 35150-KTE-600 | SW ASSY START   | 86.00  | 20 | 021G | 1 | 74
    // SR3: 02380-KTE-P11 | KIT CHAIN SPROCKET - SHINE | 860.00 | 6 | 035X | 6 | 772
    // SR4: 02380-KTE-P12 | KIT CHAIN SPROCKET CB SHINE WITHOUT | 860.00 | 6 | 072R | 6 | 4
    // SR5: 35010-KWP-H10 | KEY SET ACT 5G DIGITAL GRAZIA 2018  | 1295.00 | 5 | 219A | 1 | 0
    // SR6: 61300-KOP-D00 | STAY COMP FR FENDER | 192.00 | 5 | 311A | 1 | 895

    final columns = <String, List<CellData>>{
      'SR': [
        CellData(text: '2', topY: 350, bottomY: 367),
        CellData(text: '3', topY: 383, bottomY: 399),
        CellData(text: '6', topY: 481, bottomY: 499),
      ],
      'PART': [
        CellData(text: '1STAY',               topY: 336, bottomY: 355),
        CellData(text: '|35150-KTE-600 |SW',  topY: 353, bottomY: 385),
        CellData(text: '|02380-KTE-P11 1KIT', topY: 385, bottomY: 416),
        CellData(text: 'I02380-KTE-P12 |KIT', topY: 417, bottomY: 447),
        CellData(text: '135010-KWP-H10 KEY',  topY: 450, bottomY: 479),
        CellData(text: '|61300-KOP-DO0 STAY', topY: 483, bottomY: 509),
      ],
      'DESC': [
        CellData(text: 'FR.FENDER',                       topY: 338, bottomY: 357),
        CellData(text: 'ASSY START',                      topY: 368, bottomY: 386),
        CellData(text: 'CHAIN SPROCKET SHINE',            topY: 397, bottomY: 425),
        CellData(text: 'CHAIN SPROCKET CB SHINE WITHOUT', topY: 428, bottomY: 459),
        CellData(text: 'SET ACT 5G DIGITAL GRAZIA 2018',  topY: 458, bottomY: 492),
        CellData(text: 'COMP FR FENDER',                  topY: 491, bottomY: 512),
      ],
      'MRP': [
        CellData(text: '77.00|',  topY: 352, bottomY: 371),
        CellData(text: '86.001',  topY: 381, bottomY: 401),
        CellData(text: '860.001', topY: 411, bottomY: 433),
        CellData(text: '860.00',  topY: 441, bottomY: 462),
        CellData(text: '1295.00', topY: 470, bottomY: 492),
        CellData(text: '192.d0',  topY: 500, bottomY: 520),
      ],
      'QTY': [
        // QTY col absorbs location codes due to E05 boundary issue
        CellData(text: '5 001L',   topY: 350, bottomY: 372),
        CellData(text: '20 021G',  topY: 385, bottomY: 402),
        CellData(text: '035X 6',   topY: 414, bottomY: 432),
        CellData(text: '072R 6',   topY: 443, bottomY: 461),
        CellData(text: 'I 219A',   topY: 474, bottomY: 497),
        CellData(text: '5 I 311A', topY: 506, bottomY: 525),
      ],
      'LOC': [], // empty because E05 boundary absorbs LOC into QTY
      'PACK': [
        CellData(text: '1',   topY: 356, bottomY: 372),
        CellData(text: '1',   topY: 387, bottomY: 405),
        CellData(text: '6 I', topY: 418, bottomY: 437),
        CellData(text: '6 !', topY: 449, bottomY: 467),
        CellData(text: '1',   topY: 479, bottomY: 496),
      ],
      'STOCK': [
        CellData(text: '166', topY: 355, bottomY: 372),
        CellData(text: '74',  topY: 387, bottomY: 404),
        CellData(text: '772', topY: 419, bottomY: 436),
        CellData(text: '4',   topY: 451, bottomY: 466),
        CellData(text: '895', topY: 511, bottomY: 528),
      ],
    };

    final input = CellAssignmentOutput(
      gridGeometry: GridGeometryOutput(
        tableGeometry: TableGeometryOutput(
          topY: 330, bottomY: 797,
          leftX: 28, rightX: 1459,
          imageWidth: 1500, imageHeight: 1100,
          hasHeader: true, allWords: [],
        ),
        columns: [],
      ),
      columns: columns,
    );

    final result = await Engine07RowBuilder.build(input);
    expect(result.isSuccess, true, reason: result.errors.join('\n'));

    final rows = result.data!.rows;
    print('\n=== ENGINE 07 OUTPUT ===');
    print('Total rows: ${rows.length}');
    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      print('---');
      print('SR   : ${r.sr}');
      print('PART : ${r.partNo}');
      print('DESC : ${r.description}');
      print('MRP  : ${r.mrp}');
      print('QTY  : ${r.qty}');
      print('LOC  : ${r.location}');
      print('PACK : ${r.pack}');
      print('STOCK: ${r.stock}');
    }

    // ---- Assertions based on actual image data ----
    expect(rows.length, 6, reason: 'Should have exactly 6 rows');

    // Row 1 (SR=1 anchor from MRP 77.00)
    // NOTE: "61102-KTE-910" is missing from E06 raw data (OCR failure for row 1)
    // "STAY" leaked from DESC into PART → recovered by Engine07
    expect(rows[0].description, contains('STAY'));
    expect(rows[0].description, contains('FR.FENDER'));
    expect(rows[0].mrp, '77.00');
    expect(rows[0].qty, '5');
    expect(rows[0].location, '001L');
    expect(rows[0].pack, '1');
    expect(rows[0].stock, '166');

    // Row 2
    expect(rows[1].partNo, '35150-KTE-600');
    expect(rows[1].description, contains('SW'));
    expect(rows[1].description, contains('ASSY START'));
    expect(rows[1].mrp, '86.00');
    expect(rows[1].qty, '20');
    expect(rows[1].location, '021G');
    expect(rows[1].pack, '1');
    expect(rows[1].stock, '74');

    // Row 3
    expect(rows[2].partNo, '02380-KTE-P11');
    expect(rows[2].mrp, '860.00');
    expect(rows[2].qty, '6');
    expect(rows[2].location, '035X');
    expect(rows[2].pack, '6');

    // Row 4
    expect(rows[3].partNo, '02380-KTE-P12');
    expect(rows[3].mrp, '860.00');
    expect(rows[3].qty, '6');
    expect(rows[3].location, '072R');
    expect(rows[3].pack, '6');

    // Row 5
    expect(rows[4].partNo, '35010-KWP-H10');
    expect(rows[4].description, contains('KEY'));
    expect(rows[4].description, contains('SET ACT 5G DIGITAL GRAZIA 2018'));
    expect(rows[4].mrp, '1295.00');
    // NOTE: QTY='' and STOCK='' for row 5 are OCR misses —
    // the E06 QTY cell for row 5 only captured "I 219A" (pipe+location),
    // the actual "5" was never read by OCR.
    expect(rows[4].location, '219A');
    expect(rows[4].pack, '1');

    // Row 6
    expect(rows[5].partNo, '61300-KOP-DO0');
    expect(rows[5].description, contains('STAY'));
    expect(rows[5].description, contains('COMP FR FENDER'));
    expect(rows[5].mrp, '192.00');
    expect(rows[5].qty, '5');
    expect(rows[5].location, '311A');
    // NOTE: PACK='' for row 6 — OCR missed the PACK "1" for that row
    expect(rows[5].stock, '895');
  });
}
