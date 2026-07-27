import 'dart:io';
import 'package:wms_mobile/core/database/app_database.dart';
import 'package:wms_mobile/core/pipeline/ocr_pipeline_manager.dart';
import 'package:wms_mobile/core/pipeline/engine_01_acquisition.dart';
import 'package:wms_mobile/core/pipeline/engine_02_processing.dart';
import 'package:wms_mobile/core/pipeline/engine_02a_optimization.dart';
import 'package:wms_mobile/core/pipeline/engine_04_table_detection.dart';
import 'package:wms_mobile/core/pipeline/engine_05_grid.dart';
import 'package:wms_mobile/core/pipeline/engine_06b_zone_ocr.dart';
import 'package:wms_mobile/core/pipeline/engine_07_row.dart';
import 'package:wms_mobile/core/pipeline/engine_08_database_match.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Dump test5.jpg intermediate steps', (tester) async {
    final file = File('assets/test_images/test5.jpg');
    
    final acq = AcquisitionOutput(originalImage: file, widthPx: 0, heightPx: 0, fileSizeMB: 0, source: 'camera');
    final e02 = await Engine02Processing.processRaw(acq);
    final e02a = await Engine02aOptimization.optimize(e02.data!);
    final e04 = await Engine04TableDetection.detect(e02a.data!);
    if (!e04.isSuccess) {
      print('Engine 04 failed: ${e04.errors}');
      return;
    }
    print('Engine 04 TopY: ${e04.data!.topY}, BottomY: ${e04.data!.bottomY}');
    
    final e05 = await Engine05GridSystem.generate(e04.data!);
    if (!e05.isSuccess) {
      print('Engine 05 failed: ${e05.errors}');
      return;
    }
    for (var col in e05.data!.columns) {
      print('Engine 05 Col: ${col.key} [${col.leftX} - ${col.rightX}]');
    }
    
    final e06 = await Engine06BZoneOcr.processZones(e02a.data!, e05.data!);
    if (!e06.isSuccess) {
      print('Engine 06B failed: ${e06.errors}');
      return;
    }
    print('Engine 06B PART cells count: ${e06.data!.columns['PART']?.length}');
    for (var cell in e06.data!.columns['PART'] ?? []) {
      print('  - "${cell.text}" (Y: ${cell.topY}-${cell.bottomY})');
    }
    
    final e07 = await Engine07RowBuilder.build(e06.data!);
    if (!e07.isSuccess) {
      print('Engine 07 failed: ${e07.errors}');
      return;
    }
    print('Engine 07 rows count: ${e07.data!.rows.length}');
    for (var row in e07.data!.rows) {
      print('  Row: PART="${row.partNo}" DESC="${row.description}"');
    }
    
    final e08 = await Engine08DatabaseMatch.validateAndCorrect(e07.data!);
    if (!e08.isSuccess) {
      print('Engine 08 failed: ${e08.errors}');
      return;
    }
    for (var row in e08.data!.rows) {
      print('  E08 Row: PART="${row.partNo}" LOC="${row.location}"');
    }
  });
}
