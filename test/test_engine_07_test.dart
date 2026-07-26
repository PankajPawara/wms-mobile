import 'package:flutter_test/flutter_test.dart';
import 'package:wms_mobile/core/pipeline/engine_07_row.dart';
import 'package:wms_mobile/core/pipeline/engine_06_cell.dart';
import 'package:wms_mobile/core/pipeline/engine_05_grid.dart';
import 'package:wms_mobile/core/pipeline/engine_04_table_detection.dart';

void main() {
  test('Test Engine07 with real E06 data from device', () async {
    // Real data from device log
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
        CellData(text: 'FR.FENDER',                      topY: 338, bottomY: 357),
        CellData(text: 'ASSY START',                     topY: 368, bottomY: 386),
        CellData(text: 'CHAIN SPROCKET SHINE',           topY: 397, bottomY: 425),
        CellData(text: 'CHAIN SPROCKET CB SHINE WITHOUT',topY: 428, bottomY: 459),
        CellData(text: 'SET ACT 5G DIGITAL GRAZIA 2018', topY: 458, bottomY: 492),
        CellData(text: 'COMP FR FENDER',                 topY: 491, bottomY: 512),
      ],
      'MRP': [
        CellData(text: '77.00|',   topY: 352, bottomY: 371),
        CellData(text: '86.001',   topY: 381, bottomY: 401),
        CellData(text: '860.001',  topY: 411, bottomY: 433),
        CellData(text: '860.00',   topY: 441, bottomY: 462),
        CellData(text: '1295.00',  topY: 470, bottomY: 492),
        CellData(text: '192.d0',   topY: 500, bottomY: 520),
      ],
      'QTY': [
        CellData(text: '5 001L',   topY: 350, bottomY: 372),
        CellData(text: '20 021G',  topY: 385, bottomY: 402),
        CellData(text: '035X 6',   topY: 414, bottomY: 432),
        CellData(text: '072R 6',   topY: 443, bottomY: 461),
        CellData(text: 'I 219A',   topY: 474, bottomY: 497),
        CellData(text: '5 I 311A', topY: 506, bottomY: 525),
      ],
      'LOC': [],
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
    print('Total rows: ${rows.length}');
    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      print('Row ${i+1}: SR=${r.sr} | PART=${r.partNo} | DESC=${r.description} | MRP=${r.mrp} | QTY=${r.qty} | LOC=${r.location} | PACK=${r.pack} | STOCK=${r.stock}');
    }

    // Expect exactly 6 rows (one per anchor cell in MRP)
    expect(rows.length, 6);
    expect(rows[0].mrp, '77.00');
    expect(rows[1].mrp, '86.00');
    expect(rows[2].mrp, '860.00');
  });
}
