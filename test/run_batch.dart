import 'dart:convert';
import 'dart:io';

import 'package:wms_mobile/core/pipeline/engine_01_acquisition.dart';
import 'package:wms_mobile/core/pipeline/engine_02_processing.dart';
import 'package:wms_mobile/core/pipeline/engine_02a_optimization.dart';
import 'package:wms_mobile/core/pipeline/engine_03_header.dart';
import 'package:wms_mobile/core/pipeline/engine_04_table_detection.dart';
import 'package:wms_mobile/core/pipeline/engine_07_row.dart';
import 'package:wms_mobile/core/database/app_database.dart';
import 'package:wms_mobile/core/services/candidate_generator.dart';
import 'package:wms_mobile/core/models/extracted_memo.dart';
import 'package:wms_mobile/core/pipeline/ocr_pipeline_manager.dart';

void main() async {
  // Since we are running in Dart VM, we can't use MLKit natively.
  // Wait, if I can't use MLKit, I can't run Engine 03 and 04!
  // I need to use the OCR words from some mocked JSON or run it on emulator.
}
