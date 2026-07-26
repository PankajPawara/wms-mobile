import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'engine_02a_optimization.dart';
import 'engine_05_grid.dart';
import 'engine_06_cell.dart';
import 'models/pipeline_result.dart';
import 'models/pipeline_stage.dart';

class Engine06BZoneOcr {
  static final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  static Future<PipelineResult<CellAssignmentOutput>> processZones(
    OptimizationOutput optimizedImageOutput,
    GridGeometryOutput gridInput,
  ) async {
    final stopwatch = Stopwatch()..start();
    final errors = <String>[];

    try {
      final bytes = await optimizedImageOutput.optimizedImage.readAsBytes();
      final image = await compute(_decodeBytes, bytes);
      if (image == null) throw Exception('Could not decode optimized image for Zone OCR');

      final tableTopY = gridInput.tableGeometry.topY;
      final tableBottomY = gridInput.tableGeometry.bottomY;
      
      final columnsData = <String, List<CellData>>{};
      for (final col in gridInput.columns) {
        columnsData[col.key] = [];
      }

      final tempDir = await getTemporaryDirectory();

      for (final col in gridInput.columns) {
        // Crop the column. Add a small inset (e.g., 4px) to strip out vertical pipe separators.
        // Make sure we don't go out of bounds or create negative width.
        int cropLeft = col.leftX + 4;
        int cropRight = col.rightX - 4;
        
        if (cropRight <= cropLeft) {
          // Fallback if column is too narrow
          cropLeft = col.leftX;
          cropRight = col.rightX;
        }
        
        if (cropLeft < 0) cropLeft = 0;
        if (cropRight > image.width) cropRight = image.width;
        if (tableTopY < 0) continue;
        
        int cropWidth = cropRight - cropLeft;
        int cropHeight = tableBottomY - tableTopY;
        
        if (cropWidth <= 0 || cropHeight <= 0) continue;

        // Run the crop in isolate
        final cropParams = _CropParams(image, cropLeft, tableTopY, cropWidth, cropHeight);
        final croppedBytes = await compute(_cropImageBytes, cropParams);
        
        // Save to temp file for ML Kit
        final tempFile = File('${tempDir.path}/col_${col.key}_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await tempFile.writeAsBytes(croppedBytes);

        // Run OCR on the zone
        final inputImage = InputImage.fromFile(tempFile);
        final recognizedText = await _textRecognizer.processImage(inputImage);
        
        // Convert local crop coordinates back to global image coordinates
        for (final block in recognizedText.blocks) {
          for (final line in block.lines) {
            for (final element in line.elements) {
              columnsData[col.key]!.add(CellData(
                text: element.text,
                topY: tableTopY + element.boundingBox.top.toInt(),
                bottomY: tableTopY + element.boundingBox.bottom.toInt(),
              ));
            }
          }
        }
        
        // Clean up temp file
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }

      // Consolidate cells within the same row (especially for DESCRIPTION)
      // This re-uses the logic from Engine 06
      final consolidatedColumns = <String, List<CellData>>{};
      
      for (final entry in columnsData.entries) {
        final colKey = entry.key;
        final rawCells = entry.value;
        
        if (rawCells.isEmpty) {
          consolidatedColumns[colKey] = [];
          continue;
        }

        // Sort top-to-bottom
        rawCells.sort((a, b) => a.topY.compareTo(b.topY));
        
        final mergedCells = <CellData>[];
        List<CellData> currentRow = [rawCells.first];

        for (int i = 1; i < rawCells.length; i++) {
          final current = rawCells[i];
          final rowTopY = currentRow.first.topY;
          final rowBottomY = currentRow.last.bottomY;
          final rowCenterY = (rowTopY + rowBottomY) ~/ 2;
          final currentCenterY = (current.topY + current.bottomY) ~/ 2;

          // If vertically aligned within 20 pixels, it's the same physical text line
          if ((currentCenterY - rowCenterY).abs() < 20) {
            currentRow.add(current);
          } else {
            // Join the words
            mergedCells.add(CellData(
              text: currentRow.map((c) => c.text).join(' '),
              topY: currentRow.first.topY,
              bottomY: currentRow.last.bottomY, // approximate
            ));
            currentRow = [current];
          }
        }
        
        if (currentRow.isNotEmpty) {
          mergedCells.add(CellData(
            text: currentRow.map((c) => c.text).join(' '),
            topY: currentRow.first.topY,
            bottomY: currentRow.last.bottomY,
          ));
        }

        consolidatedColumns[colKey] = mergedCells;
      }

      stopwatch.stop();

      return PipelineResult(
        data: CellAssignmentOutput(
          gridGeometry: gridInput,
          columns: consolidatedColumns,
        ),
        timingMs: stopwatch.elapsedMilliseconds,
        confidence: 1.0,
        stage: PipelineStage.cell,
        errors: errors,
      );

    } catch (e) {
      stopwatch.stop();
      return PipelineResult.failure(
        stage: PipelineStage.cell,
        reason: e.toString(),
        timingMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  static img.Image? _decodeBytes(List<int> bytes) {
    return img.decodeImage(Uint8List.fromList(bytes));
  }
}

class _CropParams {
  final img.Image image;
  final int x;
  final int y;
  final int w;
  final int h;
  _CropParams(this.image, this.x, this.y, this.w, this.h);
}

List<int> _cropImageBytes(_CropParams params) {
  final cropped = img.copyCrop(params.image, x: params.x, y: params.y, width: params.w, height: params.h);
  return img.encodeJpg(cropped);
}
