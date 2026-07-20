// =============================================================================
// PIPELINE STAGE ENUM
// Identifies each stage in the Document Processing Pipeline for logging and
// debug tracking. Each engine emits its stage identifier in every PipelineResult.
// =============================================================================

enum PipelineStage {
  acquisition,    // Engine 01
  processing,     // Engine 02
  optimization,   // Engine 02A
  header,         // Engine 03
  tableDetection, // Engine 04
  grid,           // Engine 05
  cell,           // Engine 06
  columnReaders,  // Engine 07
  rowBuilder,     // Engine 08
  validation,     // Engine 09
  geminiVerify,   // Engine 10
  merge,          // Engine 11
}

extension PipelineStageLabel on PipelineStage {
  String get label {
    switch (this) {
      case PipelineStage.acquisition:    return 'Image Acquisition';
      case PipelineStage.processing:     return 'Image Processing';
      case PipelineStage.optimization:   return 'Image Optimization';
      case PipelineStage.header:         return 'Header Engine';
      case PipelineStage.tableDetection: return 'Table Detection';
      case PipelineStage.grid:           return 'Grid Engine';
      case PipelineStage.cell:           return 'Cell Engine';
      case PipelineStage.columnReaders:  return 'Column Readers';
      case PipelineStage.rowBuilder:     return 'Row Builder';
      case PipelineStage.validation:     return 'Validation Engine';
      case PipelineStage.geminiVerify:   return 'Gemini Verification';
      case PipelineStage.merge:          return 'Merge Engine';
    }
  }
}
