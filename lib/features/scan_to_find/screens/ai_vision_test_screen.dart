import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../../settings/repositories/inventory_repository.dart';
import '../../../core/utils/barcode_util.dart';
import '../../../core/utils/local_ocr_parser.dart';
import '../../../shared/widgets/app_button.dart';

enum AIVisionMode { memo, redLabel }

class AIVisionTestScreen extends ConsumerStatefulWidget {
  const AIVisionTestScreen({super.key});

  @override
  ConsumerState<AIVisionTestScreen> createState() => _AIVisionTestScreenState();
}

class _AIVisionTestScreenState extends ConsumerState<AIVisionTestScreen> {
  final ImagePicker _picker = ImagePicker();
  
  AIVisionMode _mode = AIVisionMode.memo;
  List<File> _imageFiles = [];
  bool _isProcessing = false;
  String _resultText = '';
  List<dynamic> _parsedItems = [];
  bool _hasPriority = false;
  bool _showControls = true;
  // Debug: raw OCR output for root-cause analysis
  String _rawOcrDebug = '';
  bool _showDebugPanel = false;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final List<XFile> pickedFiles = await _picker.pickMultiImage();
        if (pickedFiles.isNotEmpty) {
          setState(() {
            _imageFiles.addAll(pickedFiles.map((f) => File(f.path)));
            _resultText = '';
            _parsedItems = [];
            _hasPriority = false;
          });
        }
      } else {
        final XFile? pickedFile = await _picker.pickImage(source: source);
        if (pickedFile != null) {
          setState(() {
            _imageFiles.add(File(pickedFile.path));
            _resultText = '';
            _parsedItems = [];
            _hasPriority = false;
          });
        }
      }
    } catch (e) {
      _showError('Error picking image: $e');
    }
  }

  void _clearImages() {
    setState(() {
      _imageFiles.clear();
      _resultText = '';
      _parsedItems = [];
      _hasPriority = false;
    });
  }

  Future<void> _processImage() async {
    if (_imageFiles.isEmpty) {
      _showError('Please select an image first.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _resultText = 'Initializing ML Kit...';
      _parsedItems = [];
    });

    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      List<Map<String, dynamic>> allExtractedItems = [];
      final rawDebugBuffer = StringBuffer();

      for (int i = 0; i < _imageFiles.length; i++) {
        setState(() {
          _resultText = 'Scanning image ${i + 1} of ${_imageFiles.length}...';
        });

        final inputImage = InputImage.fromFile(_imageFiles[i]);
        final recognizedText = await textRecognizer.processImage(inputImage);

        // ── Build raw debug dump ──────────────────────────────────────────────
        rawDebugBuffer.writeln('═══ IMAGE ${i + 1} ═══');
        for (int bi = 0; bi < recognizedText.blocks.length; bi++) {
          final block = recognizedText.blocks[bi];
          rawDebugBuffer.writeln('  [BLOCK $bi] y=${block.boundingBox.top.toInt()}–${block.boundingBox.bottom.toInt()}');
          for (int li = 0; li < block.lines.length; li++) {
            final line = block.lines[li];
            rawDebugBuffer.writeln('    [LINE $li] y=${line.boundingBox.top.toInt()}  "${line.text}"');
            for (int ei = 0; ei < line.elements.length; ei++) {
              final el = line.elements[ei];
              rawDebugBuffer.writeln('      [EL $ei] x=${el.boundingBox.left.toInt()} w=${el.boundingBox.width.toInt()}  "${el.text}"');
            }
          }
        }
        rawDebugBuffer.writeln();

        // Feed geometry to LocalOcrParser
        final items = LocalOcrParser.parseTable(recognizedText);
        allExtractedItems.addAll(items);
      }

      setState(() {
        _rawOcrDebug = rawDebugBuffer.toString();
        _resultText = 'Validating against database...';
      });

      if (_mode == AIVisionMode.memo) {
        await _processMemoResult({'items': allExtractedItems, 'priority': _hasPriority});
      } else {
        await _processRedLabelResult({'items': allExtractedItems});
      }

    } catch (e) {
      setState(() {
        _resultText = 'Error:\n$e';
      });
      _showError(e.toString());
    } finally {
      await textRecognizer.close();
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }



  Future<void> _processMemoResult(dynamic parsedData) async {
    final bool priority = parsedData['priority'] ?? false;
    final List<dynamic> items = parsedData['items'] ?? [];

    final repo = ref.read(inventoryRepositoryProvider);
    final dbPartLocations = await repo.getAllPartLocations();

    List<Map<String, dynamic>> validatedItems = [];

    for (var item in items) {
      String rawPartNo = item['part_no']?.toString() ?? '';
      final extractedPartNo = BarcodeUtil.cleanExtractedPartNo(rawPartNo);
      
      // Update the item so the UI displays the cleaned version
      item['part_no'] = extractedPartNo;

      // Sanitise OCR location: strip spurious leading `1` (read as `|`) and validate 3-digit+1-letter format
      final rawLoc = item['location']?.toString() ?? '';
      final cleanedLoc = BarcodeUtil.cleanLocation(rawLoc);
      item['location'] = cleanedLoc;
      
      // Attempt Advanced Fuzzy Match using Location constraint
      final bestMatch = BarcodeUtil.findBestMatchWithLocation(extractedPartNo, cleanedLoc, dbPartLocations);
      
      String validationStatus = 'Unknown (Not in DB)';
      Color statusColor = Colors.orange;

      if (bestMatch != null) {
        // Fetch actual location from our pre-fetched map
        final dbLoc = dbPartLocations[bestMatch];
        validationStatus = 'Verified ($bestMatch)';
        statusColor = Colors.green;
        item['location_db'] = dbLoc; // inject true location
        item['part_no'] = bestMatch; // UPDATE part_no to the verified one!
      } else {
        if (extractedPartNo.isEmpty) {
          validationStatus = 'Failed to extract part no';
          statusColor = Colors.red;
        }
      }

      item['_validation_status'] = validationStatus;
      item['_validation_color'] = statusColor.toARGB32();
      validatedItems.add(item);
    }

    setState(() {
      _hasPriority = priority;
      _parsedItems = validatedItems;
      _resultText = 'Extracted ${validatedItems.length} items. Priority: $priority';
    });
  }

  Future<void> _processRedLabelResult(dynamic parsedData) async {
    setState(() {
      _parsedItems = [parsedData];
      _resultText = 'Red Label Data Extracted Successfully';
    });
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red, duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Vision Sandbox'),
      ),
      body: Column(
        children: [
          // Controls Area
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: !_showControls ? const SizedBox.shrink() : Container(
              padding: const EdgeInsets.all(16),
              color: theme.colorScheme.surfaceContainerLowest,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CheckboxListTile(
                    title: const Text('Mark as Priority (Porter/Urgent)'),
                    value: _hasPriority,
                    onChanged: (bool? value) {
                      setState(() {
                        _hasPriority = value ?? false;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  const SizedBox(height: 16),
                  
                  SegmentedButton<AIVisionMode>(
                    segments: const [
                      ButtonSegment(value: AIVisionMode.memo, label: Text('Memo (Pickup List)')),
                      ButtonSegment(value: AIVisionMode.redLabel, label: Text('Red Label (Checking)')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (Set<AIVisionMode> newSelection) {
                      setState(() {
                        _mode = newSelection.first;
                        _resultText = '';
                        _parsedItems = [];
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                   Wrap(
                     spacing: 8,
                     runSpacing: 8,
                     children: [
                       AppButton(
                         label: 'Camera',
                         icon: Icons.camera_alt_rounded,
                         variant: AppButtonVariant.secondary,
                         onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
                       ),
                       AppButton(
                         label: 'Gallery',
                         icon: Icons.photo_library_rounded,
                         variant: AppButtonVariant.secondary,
                         onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
                       ),
                       if (_imageFiles.isNotEmpty)
                         AppButton(
                           label: 'Clear',
                           icon: Icons.clear,
                           variant: AppButtonVariant.danger,
                           onPressed: _isProcessing ? null : _clearImages,
                         ),
                     ],
                   ),
                  const SizedBox(height: 16),
                  
                  AppButton(
                    label: _isProcessing ? 'Processing with AI...' : 'Process Image',
                    icon: Icons.auto_awesome_rounded,
                    isLoading: _isProcessing,
                    onPressed: (_imageFiles.isNotEmpty && !_isProcessing) ? () {
                        // Collapse controls when processing starts to show results
                        setState(() {
                           _showControls = false;
                        });
                        _processImage();
                    } : null,
                  ),
                ],
              ),
            ),
          ),
          
          InkWell(
            onTap: () => setState(() => _showControls = !_showControls),
            child: Container(
              height: 24,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Center(
                child: Icon(
                  _showControls ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          
          const Divider(height: 1),

          // Results Area
          Expanded(
            child: _imageFiles.isEmpty 
              ? const Center(child: Text('No images selected'))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Thumbnail Preview
                    Container(
                      width: 120,
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: theme.colorScheme.outlineVariant)),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ListView.builder(
                            itemCount: _imageFiles.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4.0),
                                child: Image.file(_imageFiles[index], fit: BoxFit.cover, height: 160),
                              );
                            },
                          ),
                          if (_isProcessing)
                            Container(
                              color: Colors.black54,
                              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                            )
                        ],
                      ),
                    ),
                    
                    // Extracted Data List
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Status bar + debug toggle
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text(_resultText, style: theme.textTheme.bodySmall)),
                                if (_hasPriority)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text('PRIORITY', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                if (_rawOcrDebug.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => setState(() => _showDebugPanel = !_showDebugPanel),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _showDebugPanel ? Colors.amber.withValues(alpha: 0.25) : Colors.grey.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
                                      ),
                                      child: Text(
                                        _showDebugPanel ? 'Hide OCR' : 'Raw OCR',
                                        style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // Raw OCR Debug Panel
                          if (_showDebugPanel && _rawOcrDebug.isNotEmpty)
                            Container(
                              constraints: const BoxConstraints(maxHeight: 260),
                              color: const Color(0xFF1A1A2E),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Toolbar
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    color: const Color(0xFF16213E),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.bug_report, color: Colors.amber, size: 14),
                                        const SizedBox(width: 6),
                                        const Text('Raw ML Kit OCR Output', style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                                        const Spacer(),
                                        GestureDetector(
                                          onTap: () {
                                            Clipboard.setData(ClipboardData(text: _rawOcrDebug));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('OCR debug text copied to clipboard'), duration: Duration(seconds: 2)),
                                            );
                                          },
                                          child: const Row(children: [
                                            Icon(Icons.copy, color: Colors.white54, size: 14),
                                            SizedBox(width: 4),
                                            Text('Copy', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                          ]),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Scrollable raw text
                                  Expanded(
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.all(10),
                                      child: SelectableText(
                                        _rawOcrDebug,
                                        style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFF00FF88), height: 1.4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _parsedItems.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final item = _parsedItems[index];
                                return Card(
                                  margin: EdgeInsets.zero,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Header: Part No & Validation
                                         Row(
                                           crossAxisAlignment: CrossAxisAlignment.start,
                                           children: [
                                             Expanded(
                                               child: Text(
                                                 item['part_no']?.toString() ?? 'N/A', 
                                                 style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                               ),
                                             ),
                                             const SizedBox(width: 8),
                                             if (item['_validation_status'] != null)
                                               Expanded(
                                                 child: Text(
                                                   item['_validation_status'],
                                                   textAlign: TextAlign.right,
                                                   style: TextStyle(
                                                     color: Color(item['_validation_color'] ?? Colors.grey.toARGB32()),
                                                     fontSize: 11,
                                                     fontWeight: FontWeight.w600,
                                                   ),
                                                 ),
                                               ),
                                           ],
                                         ),
                                        
                                        if (item['description'] != null) ...[
                                          const SizedBox(height: 4),
                                          Text(item['description'], style: theme.textTheme.bodySmall),
                                        ],
                                        
                                        const SizedBox(height: 8),
                                        
                                        // Data grid
                                        Wrap(
                                          spacing: 16,
                                          runSpacing: 8,
                                          children: [
                                            if (item['qty'] != null)
                                              _buildDataPoint('Qty', item['qty'].toString()),
                                            if (item['mrp'] != null)
                                              _buildDataPoint('MRP', item['mrp'].toString()),
                                            if (item['price'] != null)
                                              _buildDataPoint('Price', item['price'].toString()),
                                            if (item['location'] != null)
                                              _buildDataPoint('OCR Loc', item['location'].toString()),
                                            if (item['location_db'] != null)
                                              _buildDataPoint('DB Loc', item['location_db'].toString(), color: Colors.green),
                                          ],
                                        )
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataPoint(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(
          value, 
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }
}
