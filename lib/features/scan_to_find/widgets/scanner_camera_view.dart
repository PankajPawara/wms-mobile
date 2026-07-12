import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/barcode_util.dart';

class ScannerCameraView extends StatefulWidget {
  final Future<bool> Function(String result, bool isOcr) onResult;
  final Widget Function(BuildContext context, CameraController controller) builder;

  const ScannerCameraView({
    super.key,
    required this.onResult,
    required this.builder,
  });

  @override
  State<ScannerCameraView> createState() => ScannerCameraViewState();
}

class ScannerCameraViewState extends State<ScannerCameraView> with WidgetsBindingObserver {
  CameraController? _controller;
  int _cameraIndex = -1;
  List<CameraDescription> _cameras = [];

  final BarcodeScanner _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.all]);
  
  bool _isProcessing = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    if (_cameras.isEmpty) {
      try {
        _cameras = await availableCameras();
      } catch (e) {
        if (kDebugMode) print('Error fetching cameras: $e');
        return;
      }
    }
    
    if (_cameras.isEmpty) return;

    for (var i = 0; i < _cameras.length; i++) {
      if (_cameras[i].lensDirection == CameraLensDirection.back) {
        _cameraIndex = i;
        break;
      }
    }
    if (_cameraIndex == -1) _cameraIndex = 0;

    await _startLiveFeed();
  }

  Future<void> _startLiveFeed() async {
    final camera = _cameras[_cameraIndex];
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await _controller?.initialize();
      if (!mounted) return;
      
      // Auto focus settings
      await _controller?.setFocusMode(FocusMode.auto);
      
      _controller?.startImageStream(_processCameraImage);
      setState(() {});
    } catch (e) {
      if (kDebugMode) print('Error initializing camera: $e');
    }
  }

  Future<void> _stopLiveFeed() async {
    if (_controller != null && _controller!.value.isStreamingImages) {
      await _controller?.stopImageStream();
    }
    await _controller?.dispose();
    _controller = null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _stopLiveFeed();
    _barcodeScanner.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _stopLiveFeed();
    } else if (state == AppLifecycleState.resumed) {
      _startLiveFeed();
    }
  }

  void _processCameraImage(CameraImage image) async {
    if (_isProcessing || _isDisposed || !mounted) return;
    _isProcessing = true;

    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) {
      _isProcessing = false;
      return;
    }

    try {
      final barcodes = await _barcodeScanner.processImage(inputImage);
      if (barcodes.isNotEmpty) {
        for (final barcode in barcodes) {
          final rawVal = barcode.rawValue;
          if (rawVal != null && rawVal.isNotEmpty) {
            final success = await widget.onResult(rawVal, false);
            if (success) {
              _stopLiveFeed(); // Stop on success
              return; // We are done!
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error processing frame: $e');
    } finally {
      if (!_isDisposed) {
        _isProcessing = false;
      }
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;

    final camera = _cameras[_cameraIndex];
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = _orientationToDegrees(
          _controller!.value.deviceOrientation);
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) return null;

    if (image.planes.isEmpty) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  int _orientationToDegrees(DeviceOrientation orientation) {
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        return 0;
      case DeviceOrientation.landscapeLeft:
        return 90;
      case DeviceOrientation.portraitDown:
        return 180;
      case DeviceOrientation.landscapeRight:
        return 270;
    }
  }

  Future<void> toggleFlash() async {
    if (_controller == null) return;
    final mode = _controller!.value.flashMode;
    final newMode = mode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    await _controller?.setFlashMode(newMode);
    setState(() {});
  }

  Future<void> setTorch(bool turnOn) async {
    if (_controller == null) return;
    final newMode = turnOn ? FlashMode.torch : FlashMode.off;
    await _controller?.setFlashMode(newMode);
    setState(() {});
  }
  
  bool get isFlashOn => _controller?.value.flashMode == FlashMode.torch;
  FlashMode get flashMode => _controller?.value.flashMode ?? FlashMode.off;

  Future<void> restartFeed() async {
    if (_controller != null && !_controller!.value.isStreamingImages) {
      _isProcessing = false;
      await _controller?.startImageStream(_processCameraImage);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return widget.builder(context, _controller!);
  }
}
