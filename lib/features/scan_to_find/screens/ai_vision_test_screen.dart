import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import '../../settings/repositories/inventory_repository.dart';
import '../../../core/utils/barcode_util.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';

enum AIVisionMode { memo, redLabel }

class AIVisionTestScreen extends ConsumerStatefulWidget {
  const AIVisionTestScreen({super.key});

  @override
  ConsumerState<AIVisionTestScreen> createState() => _AIVisionTestScreenState();
}

class _AIVisionTestScreenState extends ConsumerState<AIVisionTestScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  
  AIVisionMode _mode = AIVisionMode.memo;
  List<File> _imageFiles = [];
  bool _isProcessing = false;
  String _resultText = '';
  List<dynamic> _parsedItems = [];
  bool _hasPriority = false;

  @override
  void dispose() {
    _apiKeyController.dispose();
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
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _showError('Please enter your Gemini API Key first.');
      return;
    }
    if (_imageFiles.isEmpty) {
      _showError('Please select an image first.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _resultText = 'Initializing Gemini Model...';
      _parsedItems = [];
      _hasPriority = false;
    });

    try {
      final prompt = _getPromptForMode();
      final List<Part> parts = [TextPart(prompt)];
      for (final file in _imageFiles) {
        final bytes = await file.readAsBytes();
        parts.add(DataPart('image/jpeg', bytes));
      }

      final List<String> fallbackModels = [
        'gemini-2.5-flash',
        'gemini-2.5-pro',
        'gemini-2.0-flash',
        'gemini-2.0-pro',
        'gemini-1.5-flash',
        'gemini-1.5-pro',
      ];
      
      GenerateContentResponse? response;
      String? lastError;

      for (final modelName in fallbackModels) {
        try {
          final model = GenerativeModel(
            model: modelName,
            apiKey: apiKey,
            generationConfig: GenerationConfig(
              temperature: 0.1,
              responseMimeType: 'application/json',
            ),
          );

          response = await model.generateContent([
            Content.multi(parts)
          ]);
          break; // Success!
        } catch (e) {
          lastError = e.toString();
          if (!lastError.contains('is not found') && !lastError.contains('404')) {
            rethrow; // Re-throw if it's an auth error or other issue
          }
        }
      }

      if (response == null) {
        String availableModels = '';
        try {
          final request = await HttpClient().getUrl(Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey'));
          final res = await request.close();
          final body = await res.transform(utf8.decoder).join();
          final data = jsonDecode(body);
          if (data['models'] != null) {
            final modelsList = (data['models'] as List).map((m) => m['name'].toString().replaceAll('models/', '')).join(', ');
            availableModels = '\n\nAvailable Models for your key: $modelsList';
          } else {
            availableModels = '\n\nAPI Response: $body';
          }
        } catch (e) {
          availableModels = '\n\nCould not fetch models list: $e';
        }
        throw Exception('All Gemini models failed. Last error: $lastError$availableModels');
      }

      setState(() {
        _resultText = 'Analyzing image... this usually takes 3-5 seconds.';
      });

      final responseText = response.text;

      if (responseText == null || responseText.isEmpty) {
        throw Exception('Empty response from Gemini');
      }

      setState(() {
        _resultText = 'Parsing JSON...';
      });

      // Parse JSON
      final parsedData = jsonDecode(responseText);
      
      setState(() {
        _resultText = 'Validating against database...';
      });

      if (_mode == AIVisionMode.memo) {
        await _processMemoResult(parsedData);
      } else {
        await _processRedLabelResult(parsedData);
      }

    } catch (e) {
      setState(() {
        _resultText = 'Error:\n$e';
      });
      _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  String _getPromptForMode() {
    if (_mode == AIVisionMode.memo) {
      return '''
Analyze this order memo and extract all line items into a JSON array. 
CRITICAL INSTRUCTION: You must read the data strictly ROW by ROW. Trace your eyes horizontally across each row from left to right. Do NOT mix columns from different rows! 
The table columns are: SR, PART No, DESCRIPTION, M.R.P., QTY, LOCATION, PACK, STOCK.
For each item, extract: 
- `part_no`
- `description` (the name of the part)
- `location`
- `mrp`
- `qty`
- `in_stock` (from the STOCK column)
- `pack_of` (from the PACK column)

Correct any obvious character ambiguities in part numbers based on standard LLLLL-LLL-LLL Honda formats (e.g. O vs 0, S vs 5, Z vs 2). Ignore stray vertical lines like `|` or `1` at the edges of columns.

Additionally, check the ENTIRE memo for handwritten priority keywords such as 'porter', 'leva aavshe', 'urgent', 'asap'.
If any of these priority keywords are found, set a `priority` flag to true in a top-level wrapper object.

Strictly return a JSON object with this structure:
{
  "priority": true/false,
  "items": [
    { "part_no": "...", "description": "...", "location": "...", "mrp": 12.3, "qty": 1, "in_stock": 1, "pack_of": 1 }
  ]
}
''';
    } else {
      return '''
Extract only the `part_no`, `qty`, and `price` from this red label. 
Ignore all other text, instructions, or background noise. 
Return the result strictly as a JSON object with this structure:
{
  "part_no": "...",
  "qty": "...",
  "price": "..."
}
''';
    }
  }

  Future<void> _processMemoResult(dynamic parsedData) async {
    final bool priority = parsedData['priority'] ?? false;
    final List<dynamic> items = parsedData['items'] ?? [];

    final repo = ref.read(inventoryRepositoryProvider);
    final allDbParts = await repo.getAllPartNumbers();

    List<Map<String, dynamic>> validatedItems = [];

    for (var item in items) {
      String rawPartNo = item['part_no']?.toString() ?? '';
      final extractedPartNo = BarcodeUtil.cleanExtractedPartNo(rawPartNo);
      
      // Update the item so the UI displays the cleaned version
      item['part_no'] = extractedPartNo;
      
      // Attempt Fuzzy Match
      final bestMatch = BarcodeUtil.findBestMatch(extractedPartNo, allDbParts);
      
      String validationStatus = 'Unknown (Not in DB)';
      Color statusColor = Colors.orange;

      if (bestMatch != null) {
        // Fetch actual location from DB
        final dbItem = await repo.searchByPartNo(bestMatch);
        if (dbItem.isNotEmpty) {
          validationStatus = 'Verified ($bestMatch)';
          statusColor = Colors.green;
          item['location_db'] = dbItem.first.location; // inject true location
        }
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
          Container(
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.surfaceContainerLowest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  controller: _apiKeyController,
                  label: 'Gemini API Key',
                  hint: 'AIza...',
                  obscureText: true,
                  prefixIcon: Icons.key_rounded,
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
                  onPressed: (_imageFiles.isNotEmpty && !_isProcessing) ? _processImage : null,
                ),
              ],
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
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
