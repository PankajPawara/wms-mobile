import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';

import '../../../core/services/sandbox_ocr_engine.dart';

class OcrSandboxScreen extends ConsumerStatefulWidget {
  const OcrSandboxScreen({super.key});

  @override
  ConsumerState<OcrSandboxScreen> createState() => _OcrSandboxScreenState();
}

class _OcrSandboxScreenState extends ConsumerState<OcrSandboxScreen> {
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();
  
  // Pipeline Results
  bool _isProcessing = false;
  SandboxOcrResult? _ocrResult;
  Map<String, dynamic>? _geminiResult;
  String? _error;

  Future<void> _loadTestAsset(String assetName) async {
    try {
      final byteData = await rootBundle.load('assets/test_images/$assetName');
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$assetName');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      setState(() {
        _imageFile = file;
        _runPipeline();
      });
    } catch (e) {
      debugPrint('Failed to load asset: $e');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          _runPipeline();
        });
      }
    } catch (e) {
      debugPrint('Failed to pick image: $e');
    }
  }

  Future<void> _scanDocument() async {
    try {
      final pictures = await CunningDocumentScanner.getPictures();
      if (pictures != null && pictures.isNotEmpty) {
        setState(() {
          _imageFile = File(pictures.first);
          _runPipeline();
        });
      }
    } catch (e) {
      debugPrint('Failed to scan document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to scan document: $e')),
        );
      }
    }
  }
  
  Future<void> _runPipeline() async {
    if (_imageFile == null) return;
    
    setState(() {
      _isProcessing = true;
      _ocrResult = null;
      _geminiResult = null;
      _error = null;
    });
    
    try {
      final result = await SandboxOcrEngine.processImage(_imageFile!);
      Map<String, dynamic>? geminiRes;
      
      if (result.pickupJson != null) {
        geminiRes = await SandboxGeminiVerifier.verify(result.pickupJson!, _imageFile!);
      }
      
      setState(() {
        _ocrResult = result;
        _geminiResult = geminiRes;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('OCR Sandbox Laboratory'),
        backgroundColor: colorScheme.surface,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.image),
            tooltip: 'Select Input Image',
            onSelected: (value) {
              if (value == 'camera') {
                _pickImage(ImageSource.camera);
              } else if (value == 'gallery') {
                _pickImage(ImageSource.gallery);
              } else if (value == 'scan') {
                _scanDocument();
              } else {
                _loadTestAsset(value);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'camera', child: Text('📸 Camera')),
              const PopupMenuItem(value: 'gallery', child: Text('🖼️ Gallery')),
              const PopupMenuItem(value: 'scan', child: Text('📄 Scan Document')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'test1.jpg', child: Text('Test Image 1 (Perfect)')),
              const PopupMenuItem(value: 'test2.jpg', child: Text('Test Image 2 (Low Light)')),
              const PopupMenuItem(value: 'test3.jpg', child: Text('Test Image 3 (Skewed)')),
              const PopupMenuItem(value: 'test4.jpg', child: Text('Test Image 4 (Dense)')),
              const PopupMenuItem(value: 'test5.jpg', child: Text('Test Image 5 (Rotated)')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Run Pipeline',
            onPressed: _imageFile != null ? _runPipeline : null,
          ),
        ],
      ),
      body: _imageFile == null
          ? const Center(child: Text('Select an image from the top right menu to begin.'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionCard('Original Image', Image.file(_imageFile!, height: 300, fit: BoxFit.contain)),
                  const SizedBox(height: 16),
                  
                  if (_isProcessing)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null)
                    _buildSectionCard('Error', Text(_error!, style: const TextStyle(color: Colors.red)))
                  else if (_ocrResult != null) ...[
                    _buildSectionCard(
                      'Table Geometry', 
                      Text(_ocrResult!.geometry != null 
                          ? const JsonEncoder.withIndent('  ').convert(_ocrResult!.geometry!.toJson()) 
                          : 'No geometry detected'),
                      copyText: _ocrResult!.geometry != null ? const JsonEncoder.withIndent('  ').convert(_ocrResult!.geometry!.toJson()) : null,
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      'Header JSON', 
                      Text(_ocrResult!.headerJson != null 
                          ? const JsonEncoder.withIndent('  ').convert(_ocrResult!.headerJson) 
                          : 'No header detected'),
                      copyText: _ocrResult!.headerJson != null ? const JsonEncoder.withIndent('  ').convert(_ocrResult!.headerJson) : null,
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      'Cell Matrix JSON', 
                      Text(_ocrResult!.tableMatrixJson != null 
                          ? const JsonEncoder.withIndent('  ').convert(_ocrResult!.tableMatrixJson) 
                          : 'No table matrix detected'),
                      copyText: _ocrResult!.tableMatrixJson != null ? const JsonEncoder.withIndent('  ').convert(_ocrResult!.tableMatrixJson) : null,
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      'Pickup JSON', 
                      Text(_ocrResult!.pickupJson != null 
                          ? const JsonEncoder.withIndent('  ').convert(_ocrResult!.pickupJson) 
                          : 'No pickup json generated'),
                      copyText: _ocrResult!.pickupJson != null ? const JsonEncoder.withIndent('  ').convert(_ocrResult!.pickupJson) : null,
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      'Gemini Validation JSON', 
                      Text(_geminiResult != null 
                          ? const JsonEncoder.withIndent('  ').convert(_geminiResult) 
                          : 'No gemini validation executed'),
                      copyText: _geminiResult != null ? const JsonEncoder.withIndent('  ').convert(_geminiResult) : null,
                    ),
                  ]
                ],
              ),
            ),
    );
  }
  
  Widget _buildSectionCard(String title, Widget child, {String? copyText}) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (copyText != null)
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    tooltip: 'Copy JSON',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: copyText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
                      );
                    },
                  ),
              ],
            ),
            const Divider(),
            child,
          ],
        ),
      ),
    );
  }
}