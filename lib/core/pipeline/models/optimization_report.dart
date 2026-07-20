// =============================================================================
// OPTIMIZATION REPORT MODEL
// Output of Engine 02A. Contains compression metrics and file metadata.
// =============================================================================

class OptimizationReport {
  final double originalSizeMB;
  final double optimizedSizeMB;
  final String compressionRatio;
  final int processingTimeMs;
  final bool uploadReady;
  final int originalWidth;
  final int originalHeight;
  final int optimizedWidth;
  final int optimizedHeight;

  const OptimizationReport({
    required this.originalSizeMB,
    required this.optimizedSizeMB,
    required this.compressionRatio,
    required this.processingTimeMs,
    required this.uploadReady,
    required this.originalWidth,
    required this.originalHeight,
    required this.optimizedWidth,
    required this.optimizedHeight,
  });

  Map<String, dynamic> toJson() => {
    'originalSizeMB': double.parse(originalSizeMB.toStringAsFixed(2)),
    'optimizedSizeMB': double.parse(optimizedSizeMB.toStringAsFixed(2)),
    'compressionRatio': compressionRatio,
    'processingTimeMs': processingTimeMs,
    'uploadReady': uploadReady,
    'resolution': {
      'original': '${originalWidth}x${originalHeight}',
      'optimized': '${optimizedWidth}x${optimizedHeight}',
    },
  };
}
