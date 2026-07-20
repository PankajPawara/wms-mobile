// =============================================================================
// PIPELINE RESULT — Generic wrapper for every engine's output.
//
// Every engine in the Document Processing Pipeline returns a PipelineResult<T>.
// This enforces a consistent contract:
//   - data:        The typed output of the engine (can be null on failure)
//   - timingMs:    How long the engine took to execute
//   - confidence:  0.0 to 1.0 confidence score (engine-determined)
//   - errors:      List of non-fatal warnings / fatal error messages
//   - stage:       Which pipeline stage produced this result
// =============================================================================

import 'pipeline_stage.dart';

class PipelineResult<T> {
  final T? data;
  final int timingMs;
  final double confidence;
  final List<String> errors;
  final PipelineStage stage;

  const PipelineResult({
    this.data,
    required this.timingMs,
    required this.confidence,
    required this.stage,
    this.errors = const [],
  });

  bool get isSuccess => data != null && errors.every((e) => !e.startsWith('[FATAL]'));

  /// Create a failed result with no data.
  factory PipelineResult.failure({
    required PipelineStage stage,
    required String reason,
    int timingMs = 0,
  }) {
    return PipelineResult<T>(
      data: null,
      timingMs: timingMs,
      confidence: 0.0,
      stage: stage,
      errors: ['[FATAL] $reason'],
    );
  }

  Map<String, dynamic> toDebugJson() => {
    'stage': stage.label,
    'success': isSuccess,
    'timingMs': timingMs,
    'confidence': confidence,
    'errors': errors,
  };
}
