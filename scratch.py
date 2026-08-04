import sys

def modify():
    with open('lib/core/pipeline/engine_07_row.dart', 'r', encoding='utf-8') as f:
        lines = f.readlines()
        
    # Find insert index for _ProjectedCell
    insert_idx = 0
    for i, line in enumerate(lines):
        if line.startswith('class Engine07RowBuilder'):
            insert_idx = i
            break
            
    # Find start and end for replacement
    start_idx = -1
    end_idx = -1
    for i, line in enumerate(lines):
        if 'STEP 1 — Choose the anchor column' in line:
            start_idx = i - 1
        if 'stopwatch.stop();' in line and start_idx != -1 and i > start_idx + 10:
            if 'return PipelineResult' in lines[i+2]:
                end_idx = i
                break
                
    if start_idx == -1 or end_idx == -1:
        print('Could not find bounds')
        return

    new_body = '''      // -----------------------------------------------------------------------
      // STEP 1 — Calculate Global Skew (Slope)
      // -----------------------------------------------------------------------
      // Pre-calculate column center X coordinates
      final colCenters = <String, double>{};
      for (final col in input.gridGeometry.columns) {
        colCenters[col.key] = (col.leftX + col.rightX) / 2.0;
      }

      // Collect pairs of adjacent cells to calculate slopes
      final slopes = <double>[];
      final colKeys = input.gridGeometry.columns.map((c) => c.key).toList();
      
      for (int i = 0; i < colKeys.length - 1; i++) {
        final leftKey = colKeys[i];
        final rightKey = colKeys[i + 1];
        final leftCells = input.columns[leftKey] ?? [];
        final rightCells = input.columns[rightKey] ?? [];
        
        final leftX = colCenters[leftKey] ?? 0.0;
        final rightX = colCenters[rightKey] ?? 0.0;
        if (rightX - leftX < 10) continue; // avoid divide by zero

        // For each left cell, find the closest right cell in Y
        for (final lCell in leftCells) {
          CellData? bestR;
          double bestDist = 30.0; // max reasonable Y drift between adjacent columns
          for (final rCell in rightCells) {
            final dist = (lCell.topY - rCell.topY).abs();
            if (dist < bestDist) {
              bestDist = dist;
              bestR = rCell;
            }
          }
          if (bestR != null) {
            final slope = (bestR.topY - lCell.topY) / (rightX - leftX);
            slopes.add(slope);
          }
        }
      }

      double globalSlope = 0.0;
      if (slopes.isNotEmpty) {
        slopes.sort();
        globalSlope = slopes[slopes.length ~/ 2];
      }

      // -----------------------------------------------------------------------
      // STEP 2 — Project all cells to Base Y (X = 0) and Cluster
      // -----------------------------------------------------------------------
      // Wrapper to hold cell with its projected base Y
      final allProjected = <_ProjectedCell>[];
      for (final entry in input.columns.entries) {
        final key = entry.key;
        final centerX = colCenters[key] ?? 0.0;
        for (final cell in entry.value) {
          final baseY = cell.topY - (centerX * globalSlope);
          allProjected.add(_ProjectedCell(key, cell, baseY));
        }
      }

      // Sort all cells globally by their flattened baseY
      allProjected.sort((a, b) => a.baseY.compareTo(b.baseY));

      // 1D Clustering
      final rowClusters = <List<_ProjectedCell>>[];
      List<_ProjectedCell> currentCluster = [];
      
      for (final pc in allProjected) {
        if (currentCluster.isEmpty) {
          currentCluster.add(pc);
        } else {
          final avgBaseY = currentCluster.map((c) => c.baseY).reduce((a, b) => a + b) / currentCluster.length;
          if ((pc.baseY - avgBaseY).abs() < 15.0) { // row tolerance
            currentCluster.add(pc);
          } else {
            rowClusters.add(currentCluster);
            currentCluster = [pc];
          }
        }
      }
      if (currentCluster.isNotEmpty) {
        rowClusters.add(currentCluster);
      }

      // -----------------------------------------------------------------------
      // STEP 3 — Assemble Rows
      // -----------------------------------------------------------------------
      final rows = <PartRow>[];

      for (final cluster in rowClusters) {
        // Find average BaseY for this cluster to resolve duplicate columns
        final avgBaseY = cluster.map((c) => c.baseY).reduce((a, b) => a + b) / cluster.length;

        // If multiple cells in the cluster belong to the SAME column, pick the one closest to avgBaseY
        final columnMap = <String, CellData>{};
        final columnBestDist = <String, double>{};

        for (final pc in cluster) {
          final dist = (pc.baseY - avgBaseY).abs();
          if (!columnMap.containsKey(pc.columnKey) || dist < columnBestDist[pc.columnKey]!) {
            columnMap[pc.columnKey] = pc.cell;
            columnBestDist[pc.columnKey] = dist;
          }
        }

        final rawSr    = columnMap['SR']?.text ?? '';
        final rawPart  = columnMap['PART']?.text ?? '';
        final rawDesc  = columnMap['DESC']?.text ?? '';
        final rawMrp   = columnMap['MRP']?.text ?? '';
        final rawQty   = columnMap['QTY']?.text ?? '';
        final rawLoc   = columnMap['LOC']?.text ?? '';
        final rawPack  = columnMap['PACK']?.text ?? '';
        final rawStock = columnMap['STOCK']?.text ?? '';

        // Clean SR — digits only
        final sr = rawSr.replaceAll(RegExp(r'[^0-9]'), '').trim();

        // Extract part number and recover leaked description prefix words
        final partResult = _processPartAndDesc(rawPart, rawDesc);
        final partNo = partResult['part']!;
        final desc   = partResult['desc']!;

        // Extract QTY, MRP, and LOC together from right-side columns
        final rightSideData = _extractMrpQtyLoc(rawMrp, rawQty, rawLoc);
        final mrp = rightSideData['mrp']!;
        final qty = rightSideData['qty']!;
        final loc = rightSideData['loc']!;

        // Clean PACK — first number only
        final pack = _cleanCount(rawPack);

        // Clean STOCK — OCR letter substitutions
        final stock = rawStock
            .replaceAll(RegExp(r'[|!]'), '')
            .replaceAll('l', '1')
            .replaceAll('O', '0')
            .trim();

        if (partNo.isEmpty && desc.isEmpty && mrp.isEmpty) continue;
        if (_isNoiseLine(partNo, desc)) continue;

        rows.add(PartRow(
          sr: sr,
          partNo: partNo,
          description: desc,
          mrp: mrp,
          qty: qty,
          location: loc,
          pack: pack,
          stock: stock,
        ));
      }
'''

    projected_cell_def = '''class _ProjectedCell {
  final String columnKey;
  final CellData cell;
  final double baseY;

  _ProjectedCell(this.columnKey, this.cell, this.baseY);
}

'''
    
    new_lines = lines[:insert_idx] + [projected_cell_def] + lines[insert_idx:start_idx] + [new_body] + lines[end_idx:]
    
    with open('lib/core/pipeline/engine_07_row.dart', 'w', encoding='utf-8') as f:
        f.writelines(new_lines)
    
    print('Replacement complete!')

modify()
