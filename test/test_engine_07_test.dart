import 'package:flutter_test/flutter_test.dart';
import 'package:wms_mobile/core/pipeline/engine_07_row.dart';
import 'package:wms_mobile/core/pipeline/engine_06_cell.dart';
import 'package:wms_mobile/core/pipeline/engine_05_grid.dart';
import 'package:wms_mobile/core/pipeline/engine_04_table_detection.dart';

void main() {
  test('Test Engine07', () async {
    final columns = <String, List<CellData>>{
      'SR': [CellData(text: '3', topY: 10, bottomY: 20)],
      'PART': [CellData(text: '35010-W1-B02', topY: 10, bottomY: 20)],
      'DESC': [CellData(text: 'SWITCH', topY: 10, bottomY: 20)],
      'MRP': [CellData(text: '120.00', topY: 10, bottomY: 20)],
      'QTY': [CellData(text: '2', topY: 10, bottomY: 20)],
      'LOC': [CellData(text: 'BOX-001', topY: 10, bottomY: 20)],
      'PACK': [],
      'STOCK': [],
    };
    
    final input = CellAssignmentOutput(
      gridGeometry: GridGeometryOutput(
        tableGeometry: TableGeometryOutput(topY: 0, bottomY: 100, leftX: 0, rightX: 100, imageWidth: 1000, imageHeight: 1000, hasHeader: false, allWords: []),
        columns: [],
      ),
      columns: columns,
    );

    final rows = await Engine07RowBuilder.build(input);
    for (var row in rows.data!.rows) {
      print('SR: ${row.sr}');
      print('PART: ${row.partNo}');
      print('MRP: ${row.mrp}');
      print('QTY: ${row.qty}');
      print('LOC: ${row.location}');
    }
  });
}
