// =============================================================================
// PIPELINE SANDBOX SCREEN
//
// A visual developer tool for testing each engine independently.
// Every engine has its own tab with:
//   - Input preview
//   - Output image preview
//   - JSON output viewer
//   - Timing + confidence metrics
//   - Copy JSON button
//
// This screen is NEVER used in production flows.
// It lives under Settings → Developer Tools → Pipeline Sandbox.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/pipeline/engine_01_acquisition.dart';
import '../../../core/pipeline/engine_02_processing.dart';
import '../../../core/pipeline/engine_02a_optimization.dart';
import '../../../core/pipeline/engine_03_header.dart';
import '../../../core/pipeline/engine_04_table_detection.dart';
import '../../../core/pipeline/engine_05_grid.dart';
import '../../../core/pipeline/engine_06_cell.dart';
import '../../../core/pipeline/engine_07_row.dart';

class PipelineSandboxScreen extends StatefulWidget {
  const PipelineSandboxScreen({super.key});

  @override
  State<PipelineSandboxScreen> createState() => _PipelineSandboxScreenState();
}

class _PipelineSandboxScreenState extends State<PipelineSandboxScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  // Engine outputs
  AcquisitionOutput? _acquisitionOutput;
  ProcessingOutput? _processingOutput;
  OptimizationOutput? _optimizationOutput;
  HeaderOutput? _headerOutput;
  TableGeometryOutput? _tableGeometryOutput;
  GridGeometryOutput? _gridOutput;
  CellAssignmentOutput? _cellOutput;
  RowBuilderOutput? _rowOutput;

  // State tracking
  bool _e01Running = false;
  bool _e02Running = false;
  bool _e02aRunning = false;
  bool _e03Running = false;
  bool _e04Running = false;
  bool _e05Running = false;
  bool _e06Running = false;
  bool _e07Running = false;

  String? _e01Error;
  String? _e02Error;
  String? _e02aError;
  String? _e03Error;
  String? _e04Error;
  String? _e05Error;
  String? _e06Error;
  String? _e07Error;

  int _e01Timing = 0;
  int _e02Timing = 0;
  int _e02aTiming = 0;
  int _e03Timing = 0;
  int _e04Timing = 0;
  int _e05Timing = 0;
  int _e06Timing = 0;
  int _e07Timing = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // ENGINE 01 — ACQUISITION
  // ---------------------------------------------------------------------------

  Future<void> _runEngine01(String source) async {
    setState(() { _e01Running = true; _e01Error = null; });
    try {
      final result = source == 'camera'
          ? await Engine01Acquisition.fromCamera()
          : await Engine01Acquisition.fromGallery();

      setState(() {
        _e01Running = false;
        _e01Timing = result.timingMs;
        if (result.isSuccess) {
          _acquisitionOutput = result.data;
          // Reset downstream engines
          _processingOutput = null;
          _optimizationOutput = null;
          _headerOutput = null;
          _tableGeometryOutput = null;
        } else {
          _e01Error = result.errors.join('\n');
        }
      });
    } catch (e) {
      setState(() { _e01Running = false; _e01Error = e.toString(); });
    }
  }

  // ---------------------------------------------------------------------------
  // ENGINE 02 — PROCESSING
  // ---------------------------------------------------------------------------

  Future<void> _runEngine02(bool scanned) async {
    if (_acquisitionOutput == null) {
      _showSnack('Run Engine 01 first.');
      return;
    }
    setState(() { _e02Running = true; _e02Error = null; });
    try {
      final result = scanned
          ? await Engine02Processing.processScanned(_acquisitionOutput!)
          : await Engine02Processing.processRaw(_acquisitionOutput!);

      setState(() {
        _e02Running = false;
        _e02Timing = result.timingMs;
        if (result.isSuccess) {
          _processingOutput = result.data;
          _optimizationOutput = null;
          _headerOutput = null;
        } else {
          _e02Error = result.errors.join('\n');
        }
      });
    } catch (e) {
      setState(() { _e02Running = false; _e02Error = e.toString(); });
    }
  }

  // ---------------------------------------------------------------------------
  // ENGINE 02A — OPTIMIZATION
  // ---------------------------------------------------------------------------

  Future<void> _runEngine02a() async {
    if (_processingOutput == null) {
      _showSnack('Run Engine 02 first.');
      return;
    }
    setState(() { _e02aRunning = true; _e02aError = null; });
    try {
      // Added a timeout guard so the UI doesn't hang infinitely if something goes wrong
      final result = await Engine02aOptimization.optimize(_processingOutput!)
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception('Engine 02A timed out after 15 seconds. Processing is stuck.');
      });
      setState(() {
        _e02aRunning = false;
        _e02aTiming = result.timingMs;
        if (result.isSuccess) {
          _optimizationOutput = result.data;
          _headerOutput = null;
        } else {
          _e02aError = result.errors.join('\n');
        }
      });
    } catch (e) {
      setState(() { _e02aRunning = false; _e02aError = e.toString(); });
    }
  }

  // ---------------------------------------------------------------------------
  // ENGINE 03 — HEADER
  // ---------------------------------------------------------------------------

  Future<void> _runEngine03() async {
    if (_optimizationOutput == null) {
      _showSnack('Run Engine 02A first.');
      return;
    }
    setState(() { _e03Running = true; _e03Error = null; });
    try {
      final result = await Engine03Header.extract(_optimizationOutput!);
      setState(() {
        _e03Running = false;
        _e03Timing = result.timingMs;
        if (result.isSuccess) {
          _headerOutput = result.data;
        } else {
          _e03Error = result.errors.join('\n');
        }
      });
    } catch (e) {
      setState(() { _e03Running = false; _e03Error = e.toString(); });
    }
  }

  // ---------------------------------------------------------------------------
  // ENGINE 04 — TABLE DETECTION
  // ---------------------------------------------------------------------------

  Future<void> _runEngine04() async {
    if (_optimizationOutput == null) {
      _showSnack('Run Engine 02A first.');
      return;
    }
    setState(() { _e04Running = true; _e04Error = null; });
    try {
      final result = await Engine04TableDetection.detect(_optimizationOutput!);
      setState(() {
        _e04Running = false;
        _e04Timing = result.timingMs;
        if (result.isSuccess) {
          _tableGeometryOutput = result.data;
        } else {
          _e04Error = result.errors.join('\n');
        }
      });
    } catch (e) {
      setState(() { _e04Running = false; _e04Error = e.toString(); });
    }
  }

  // ---------------------------------------------------------------------------
  // ENGINE 05 — GRID SYSTEM
  // ---------------------------------------------------------------------------

  Future<void> _runEngine05() async {
    if (_tableGeometryOutput == null) {
      _showSnack('Run Engine 04 first.');
      return;
    }
    setState(() { _e05Running = true; _e05Error = null; });
    try {
      final result = await Engine05GridSystem.generate(_tableGeometryOutput!);
      setState(() {
        _e05Running = false;
        _e05Timing = result.timingMs;
        if (result.isSuccess) {
          _gridOutput = result.data;
        } else {
          _e05Error = result.errors.join('\n');
        }
      });
    } catch (e) {
      setState(() { _e05Running = false; _e05Error = e.toString(); });
    }
  }

  // ---------------------------------------------------------------------------
  // ENGINE 06 — CELL ASSIGNMENT
  // ---------------------------------------------------------------------------

  Future<void> _runEngine06() async {
    if (_gridOutput == null) {
      _showSnack('Run Engine 05 first.');
      return;
    }
    setState(() { _e06Running = true; _e06Error = null; });
    try {
      final result = await Engine06CellAssignment.assign(_gridOutput!);
      setState(() {
        _e06Running = false;
        _e06Timing = result.timingMs;
        if (result.isSuccess) {
          _cellOutput = result.data;
        } else {
          _e06Error = result.errors.join('\n');
        }
      });
    } catch (e) {
      setState(() { _e06Running = false; _e06Error = e.toString(); });
    }
  }

  // ---------------------------------------------------------------------------
  // ENGINE 07 — ROW BUILDER
  // ---------------------------------------------------------------------------

  Future<void> _runEngine07() async {
    if (_cellOutput == null) {
      _showSnack('Run Engine 06 first.');
      return;
    }
    setState(() { _e07Running = true; _e07Error = null; });
    try {
      final result = await Engine07RowBuilder.build(_cellOutput!);
      setState(() {
        _e07Running = false;
        _e07Timing = result.timingMs;
        if (result.isSuccess) {
          _rowOutput = result.data;
        } else {
          _e07Error = result.errors.join('\n');
        }
      });
    } catch (e) {
      setState(() { _e07Running = false; _e07Error = e.toString(); });
    }
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _copyJson(Map<String, dynamic> json) {
    Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(json)));
    _showSnack('JSON copied to clipboard!');
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F14),
        foregroundColor: Colors.white,
        title: const Text(
          'Pipeline Sandbox',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.white54,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'E01\nAcquisition', height: 48),
            Tab(text: 'E02\nProcessing', height: 48),
            Tab(text: 'E02A\nOptimization', height: 48),
            Tab(text: 'E03\nHeader', height: 48),
            Tab(text: 'E04\nTable', height: 48),
            Tab(text: 'E05\nGrid', height: 48),
            Tab(text: 'E06\nCells', height: 48),
            Tab(text: 'E07\nRows', height: 48),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _Engine01Tab(
            output: _acquisitionOutput,
            isRunning: _e01Running,
            error: _e01Error,
            timingMs: _e01Timing,
            onPickGallery: () => _runEngine01('gallery'),
            onPickCamera: () => _runEngine01('camera'),
            onCopyJson: _acquisitionOutput != null
                ? () => _copyJson(_acquisitionOutput!.toJson())
                : null,
          ),
          _Engine02Tab(
            acquisitionOutput: _acquisitionOutput,
            output: _processingOutput,
            isRunning: _e02Running,
            error: _e02Error,
            timingMs: _e02Timing,
            onProcessRaw: () => _runEngine02(false),
            onProcessScanned: () => _runEngine02(true),
            onCopyJson: _processingOutput != null
                ? () => _copyJson(_processingOutput!.toJson())
                : null,
          ),
          _Engine02aTab(
            processingOutput: _processingOutput,
            output: _optimizationOutput,
            isRunning: _e02aRunning,
            error: _e02aError,
            timingMs: _e02aTiming,
            onOptimize: _runEngine02a,
            onCopyJson: _optimizationOutput != null
                ? () => _copyJson(_optimizationOutput!.toJson())
                : null,
          ),
          _Engine03Tab(
            optimizationOutput: _optimizationOutput,
            output: _headerOutput,
            isRunning: _e03Running,
            error: _e03Error,
            timingMs: _e03Timing,
            onExtract: _runEngine03,
            onCopyJson: _headerOutput != null
                ? () => _copyJson(_headerOutput!.headerData)
                : null,
          ),
          _Engine04Tab(
            optimizationOutput: _optimizationOutput,
            output: _tableGeometryOutput,
            isRunning: _e04Running,
            error: _e04Error,
            timingMs: _e04Timing,
            onExtract: _runEngine04,
            onCopyJson: _tableGeometryOutput != null
                ? () => _copyJson(_tableGeometryOutput!.toJson())
                : null,
          ),
          _Engine05Tab(
            output: _gridOutput,
            isRunning: _e05Running,
            error: _e05Error,
            timingMs: _e05Timing,
            onExtract: _runEngine05,
            onCopyJson: _gridOutput != null
                ? () => _copyJson(_gridOutput!.toJson())
                : null,
          ),
          _Engine06Tab(
            output: _cellOutput,
            isRunning: _e06Running,
            error: _e06Error,
            timingMs: _e06Timing,
            onExtract: _runEngine06,
            onCopyJson: _cellOutput != null
                ? () => _copyJson(_cellOutput!.toJson())
                : null,
          ),
          _Engine07Tab(
            output: _rowOutput,
            isRunning: _e07Running,
            error: _e07Error,
            timingMs: _e07Timing,
            onExtract: _runEngine07,
            onCopyJson: _rowOutput != null
                ? () => _copyJson(_rowOutput!.toJson())
                : null,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ENGINE 01 TAB
// =============================================================================

class _Engine01Tab extends StatelessWidget {
  final AcquisitionOutput? output;
  final bool isRunning;
  final String? error;
  final int timingMs;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback? onCopyJson;

  const _Engine01Tab({
    required this.output,
    required this.isRunning,
    required this.error,
    required this.timingMs,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onCopyJson,
  });

  @override
  Widget build(BuildContext context) {
    return _PipelineTabLayout(
      stageName: 'Engine 01 — Image Acquisition',
      stageDesc: 'Captures or loads an image, corrects EXIF rotation, and saves it as original_image.jpg.',
      isRunning: isRunning,
      error: error,
      timingMs: timingMs,
      hasOutput: output != null,
      onCopyJson: onCopyJson,
      jsonOutput: output?.toJson(),
      imageFile: output?.originalImage,
      actions: [
        _SandboxButton(
          icon: Icons.photo_library_rounded,
          label: 'Gallery',
          color: const Color(0xFF6366F1),
          onTap: isRunning ? null : onPickGallery,
        ),
        const SizedBox(width: 12),
        _SandboxButton(
          icon: Icons.camera_alt_rounded,
          label: 'Camera',
          color: const Color(0xFF8B5CF6),
          onTap: isRunning ? null : onPickCamera,
        ),
      ],
    );
  }
}

// =============================================================================
// ENGINE 02 TAB
// =============================================================================

class _Engine02Tab extends StatelessWidget {
  final AcquisitionOutput? acquisitionOutput;
  final ProcessingOutput? output;
  final bool isRunning;
  final String? error;
  final int timingMs;
  final VoidCallback onProcessRaw;
  final VoidCallback onProcessScanned;
  final VoidCallback? onCopyJson;

  const _Engine02Tab({
    required this.acquisitionOutput,
    required this.output,
    required this.isRunning,
    required this.error,
    required this.timingMs,
    required this.onProcessRaw,
    required this.onProcessScanned,
    required this.onCopyJson,
  });

  @override
  Widget build(BuildContext context) {
    return _PipelineTabLayout(
      stageName: 'Engine 02 — Image Processing',
      stageDesc: 'Deskews, normalises brightness, boosts contrast, and sharpens edges. Outputs processed_image.png.',
      isRunning: isRunning,
      error: error,
      timingMs: timingMs,
      hasOutput: output != null,
      prerequisite: acquisitionOutput == null ? 'Run Engine 01 first' : null,
      onCopyJson: onCopyJson,
      jsonOutput: output?.toJson(),
      imageFile: output?.processedImage,
      actions: [
        _SandboxButton(
          icon: Icons.auto_fix_high_rounded,
          label: 'Process Raw',
          color: const Color(0xFF0EA5E9),
          onTap: (isRunning || acquisitionOutput == null) ? null : onProcessRaw,
        ),
        const SizedBox(width: 12),
        _SandboxButton(
          icon: Icons.document_scanner_rounded,
          label: 'Already Scanned',
          color: const Color(0xFF10B981),
          onTap: (isRunning || acquisitionOutput == null) ? null : onProcessScanned,
        ),
      ],
    );
  }
}

// =============================================================================
// ENGINE 02A TAB
// =============================================================================

class _Engine02aTab extends StatelessWidget {
  final ProcessingOutput? processingOutput;
  final OptimizationOutput? output;
  final bool isRunning;
  final String? error;
  final int timingMs;
  final VoidCallback onOptimize;
  final VoidCallback? onCopyJson;

  const _Engine02aTab({
    required this.processingOutput,
    required this.output,
    required this.isRunning,
    required this.error,
    required this.timingMs,
    required this.onOptimize,
    required this.onCopyJson,
  });

  @override
  Widget build(BuildContext context) {
    return _PipelineTabLayout(
      stageName: 'Engine 02A — Image Optimization',
      stageDesc: 'Crops margins, converts to grayscale, applies CLAHE + adaptive threshold, then compresses to an OCR-ready JPEG.',
      isRunning: isRunning,
      error: error,
      timingMs: timingMs,
      hasOutput: output != null,
      prerequisite: processingOutput == null ? 'Run Engine 02 first' : null,
      onCopyJson: onCopyJson,
      jsonOutput: output?.toJson(),
      imageFile: output?.optimizedImage,
      actions: [
        _SandboxButton(
          icon: Icons.compress_rounded,
          label: 'Optimize Image',
          color: const Color(0xFFF59E0B),
          onTap: (isRunning || processingOutput == null) ? null : onOptimize,
        ),
      ],
    );
  }
}

// =============================================================================
// SHARED TAB LAYOUT
// =============================================================================

class _PipelineTabLayout extends StatelessWidget {
  final String stageName;
  final String stageDesc;
  final bool isRunning;
  final String? error;
  final int timingMs;
  final bool hasOutput;
  final String? prerequisite;
  final VoidCallback? onCopyJson;
  final Map<String, dynamic>? jsonOutput;
  final File? imageFile;
  final List<Widget> actions;

  const _PipelineTabLayout({
    required this.stageName,
    required this.stageDesc,
    required this.isRunning,
    required this.error,
    required this.timingMs,
    required this.hasOutput,
    required this.actions,
    this.prerequisite,
    this.onCopyJson,
    this.jsonOutput,
    this.imageFile,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stage header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stageName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(stageDesc,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Prerequisite warning
          if (prerequisite != null)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, color: Color(0xFF7C3AED), size: 16),
                const SizedBox(width: 8),
                Text(prerequisite!, style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 12)),
              ]),
            ),

          // Action buttons
          Row(children: actions),

          const SizedBox(height: 16),

          // Running indicator
          if (isRunning)
            const Center(
              child: Column(
                children: [
                  SizedBox(height: 24),
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 12),
                  Text('Processing...', style: TextStyle(color: Colors.white70)),
                  SizedBox(height: 24),
                ],
              ),
            ),

          // Error display
          if (error != null && !isRunning)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
              ),
              child: Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),

          // Output preview
          if (hasOutput && !isRunning) ...[
            // Timing badge
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('✓ Done in ${timingMs}ms',
                    style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 12),

            // Image preview
            if (imageFile != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(imageFile!, fit: BoxFit.contain),
              ),
            const SizedBox(height: 12),

            // JSON output panel
            if (jsonOutput != null)
              _JsonPanel(json: jsonOutput!, onCopy: onCopyJson),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// REUSABLE WIDGETS
// =============================================================================

class _SandboxButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _SandboxButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: disabled ? const Color(0xFF2A2A3E) : color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: disabled ? Colors.white12 : color.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: disabled ? Colors.white24 : color, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: disabled ? Colors.white24 : color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _JsonPanel extends StatelessWidget {
  final Map<String, dynamic> json;
  final VoidCallback? onCopy;

  const _JsonPanel({required this.json, this.onCopy});

  @override
  Widget build(BuildContext context) {
    final pretty = const JsonEncoder.withIndent('  ').convert(json);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Text('JSON Output',
                    style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (onCopy != null)
                  GestureDetector(
                    onTap: onCopy,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.copy_rounded, color: AppColors.primary, size: 14),
                          SizedBox(width: 4),
                          Text('Copy', style: TextStyle(color: AppColors.primary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          // JSON text
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              pretty,
              style: const TextStyle(
                color: Color(0xFF7DD3FC),
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ENGINE 03 TAB
// =============================================================================

class _Engine03Tab extends StatelessWidget {
  final OptimizationOutput? optimizationOutput;
  final HeaderOutput? output;
  final bool isRunning;
  final String? error;
  final int timingMs;
  final VoidCallback onExtract;
  final VoidCallback? onCopyJson;

  const _Engine03Tab({
    required this.optimizationOutput,
    required this.output,
    required this.isRunning,
    required this.error,
    required this.timingMs,
    required this.onExtract,
    required this.onCopyJson,
  });

  @override
  Widget build(BuildContext context) {
    return _PipelineTabLayout(
      stageName: 'Engine 03 — Header Extraction',
      stageDesc: 'Crops the top 35% of the image, runs ML Kit, and extracts Header fields using spatial proximity.',
      isRunning: isRunning,
      error: error,
      timingMs: timingMs,
      hasOutput: output != null,
      prerequisite: optimizationOutput == null ? 'Run Engine 02A first' : null,
      onCopyJson: onCopyJson,
      jsonOutput: output?.headerData,
      imageFile: output?.croppedHeaderImage,
      actions: [
        _SandboxButton(
          icon: Icons.subtitles_rounded,
          label: 'Extract Header',
          color: const Color(0xFFEC4899),
          onTap: (isRunning || optimizationOutput == null) ? null : onExtract,
        ),
      ],
    );
  }
}


// =============================================================================
// ENGINE 04 TAB
// =============================================================================

class _Engine04Tab extends StatelessWidget {
  final OptimizationOutput? optimizationOutput;
  final TableGeometryOutput? output;
  final bool isRunning;
  final String? error;
  final int timingMs;
  final VoidCallback onExtract;
  final VoidCallback? onCopyJson;

  const _Engine04Tab({
    required this.optimizationOutput,
    required this.output,
    required this.isRunning,
    required this.error,
    required this.timingMs,
    required this.onExtract,
    required this.onCopyJson,
  });

  @override
  Widget build(BuildContext context) {
    return _PipelineTabLayout(
      stageName: 'Engine 04 — Table Detection',
      stageDesc: 'Runs full image OCR and strict header row matching to find exact table boundaries.',
      isRunning: isRunning,
      error: error,
      timingMs: timingMs,
      hasOutput: output != null,
      prerequisite: optimizationOutput == null ? 'Run Engine 02A first' : null,
      onCopyJson: onCopyJson,
      jsonOutput: output?.toJson(),
      actions: [
        _SandboxButton(
          icon: Icons.grid_on_rounded,
          label: 'Detect Table Boundaries',
          color: const Color(0xFFF59E0B),
          onTap: (isRunning || optimizationOutput == null) ? null : onExtract,
        ),
      ],
    );
  }
}


// =============================================================================
// ENGINE 05 TAB
// =============================================================================

class _Engine05Tab extends StatelessWidget {
  final GridGeometryOutput? output;
  final bool isRunning;
  final String? error;
  final int timingMs;
  final VoidCallback onExtract;
  final VoidCallback? onCopyJson;

  const _Engine05Tab({
    required this.output,
    required this.isRunning,
    required this.error,
    required this.timingMs,
    required this.onExtract,
    required this.onCopyJson,
  });

  @override
  Widget build(BuildContext context) {
    return _PipelineTabLayout(
      stageName: 'Engine 05 — Grid System',
      stageDesc: 'Calculates the vertical boundaries for the 8 columns based on the header.',
      isRunning: isRunning,
      error: error,
      timingMs: timingMs,
      hasOutput: output != null,
      onCopyJson: onCopyJson,
      jsonOutput: output?.toJson(),
      actions: [
        _SandboxButton(
          icon: Icons.grid_goldenratio,
          label: 'Calculate Grid',
          color: Colors.green,
          onTap: isRunning ? null : onExtract,
        ),
      ],
    );
  }
}

// =============================================================================
// ENGINE 06 TAB
// =============================================================================

class _Engine06Tab extends StatelessWidget {
  final CellAssignmentOutput? output;
  final bool isRunning;
  final String? error;
  final int timingMs;
  final VoidCallback onExtract;
  final VoidCallback? onCopyJson;

  const _Engine06Tab({
    required this.output,
    required this.isRunning,
    required this.error,
    required this.timingMs,
    required this.onExtract,
    required this.onCopyJson,
  });

  @override
  Widget build(BuildContext context) {
    return _PipelineTabLayout(
      stageName: 'Engine 06 — Cell Assignment',
      stageDesc: 'Assigns every OCR word in the table to the correct column and merges text on the same line.',
      isRunning: isRunning,
      error: error,
      timingMs: timingMs,
      hasOutput: output != null,
      onCopyJson: onCopyJson,
      jsonOutput: output?.toJson(),
      actions: [
        _SandboxButton(
          icon: Icons.view_column,
          label: 'Assign Cells',
          color: Colors.teal,
          onTap: isRunning ? null : onExtract,
        ),
      ],
    );
  }
}

// =============================================================================
// ENGINE 07 TAB
// =============================================================================

class _Engine07Tab extends StatelessWidget {
  final RowBuilderOutput? output;
  final bool isRunning;
  final String? error;
  final int timingMs;
  final VoidCallback onExtract;
  final VoidCallback? onCopyJson;

  const _Engine07Tab({
    required this.output,
    required this.isRunning,
    required this.error,
    required this.timingMs,
    required this.onExtract,
    required this.onCopyJson,
  });

  @override
  Widget build(BuildContext context) {
    return _PipelineTabLayout(
      stageName: 'Engine 07 — Row Builder',
      stageDesc: 'Links the cells horizontally to build complete Part Rows.',
      isRunning: isRunning,
      error: error,
      timingMs: timingMs,
      hasOutput: output != null,
      onCopyJson: onCopyJson,
      jsonOutput: output?.toJson(),
      actions: [
        _SandboxButton(
          icon: Icons.table_rows,
          label: 'Build Rows',
          color: Colors.blue,
          onTap: isRunning ? null : onExtract,
        ),
      ],
    );
  }
}
