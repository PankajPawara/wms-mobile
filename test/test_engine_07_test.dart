import 'package:flutter_test/flutter_test.dart';
import 'package:wms_mobile/core/pipeline/engine_07_row.dart';
import 'package:wms_mobile/core/models/extracted_memo.dart';
import 'package:wms_mobile/core/pipeline/models/pipeline_result.dart';
import 'package:wms_mobile/core/pipeline/engine_04_table_detection.dart';
import 'package:wms_mobile/core/pipeline/models/ocr_word.dart';

void main() {
  test('Test Engine07', () async {
    final words = [
      OcrWord(text: '3', left: 10, top: 10, right: 20, bottom: 20),
      OcrWord(text: '35010-W1-B02', left: 30, top: 10, right: 100, bottom: 20),
      OcrWord(text: 'SWITCH', left: 110, top: 10, right: 150, bottom: 20),
      OcrWord(text: '120.00', left: 160, top: 10, right: 200, bottom: 20),
      OcrWord(text: '2', left: 210, top: 10, right: 220, bottom: 20),
      OcrWord(text: 'BOX-001', left: 230, top: 10, right: 280, bottom: 20),
    ];

    final rows = await Engine07RowBuilder.build(TableGeometryOutput(topY: 0, bottomY: 100, leftX: 0, rightX: 100, imageWidth: 1000, imageHeight: 1000, hasHeader: false, allWords: words));
    for (var row in rows.data!.rows) {
      print('SR: ${row.sr}');
      print('PART: ${row.partNo}');
      print('MRP: ${row.mrp}');
      print('QTY: ${row.qty}');
      print('LOC: ${row.location}');
    }
  });
}
