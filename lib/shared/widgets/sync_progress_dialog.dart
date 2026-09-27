import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';

class SyncProgressDialog extends StatefulWidget {
  final Future<bool> Function(void Function(double) onProgress) syncTask;
  final String title;
  final String successMessage;
  final String errorMessage;
  final String errorDescription;

  const SyncProgressDialog({
    super.key, 
    required this.syncTask,
    this.title = 'Syncing Database',
    this.successMessage = 'Sync Successful!',
    this.errorMessage = 'Sync Failed',
    this.errorDescription = 'An error occurred while updating the database. You can continue your work and try again later.',
  });

  static Future<bool> show(
    BuildContext context, 
    Future<bool> Function(void Function(double)) syncTask, {
    String title = 'Syncing Database',
    String successMessage = 'Sync Successful!',
    String errorMessage = 'Sync Failed',
    String errorDescription = 'An error occurred while updating the database. You can continue your work and try again later.',
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SyncProgressDialog(
        syncTask: syncTask,
        title: title,
        successMessage: successMessage,
        errorMessage: errorMessage,
        errorDescription: errorDescription,
      ),
    ).then((value) => value ?? false);
  }

  @override
  State<SyncProgressDialog> createState() => _SyncProgressDialogState();
}

class _SyncProgressDialogState extends State<SyncProgressDialog> with SingleTickerProviderStateMixin {
  double _progress = 0.0;
  bool _isSuccess = false;
  bool _isError = false;
  late AnimationController _successAnimController;
  late Animation<double> _scaleAnimation;
  
  Timer? _messageTimer;
  Timer? _fakeProgressTimer;
  int _messageIndex = 0;
  
  final List<String> _messages = [
    'Please wait a moment...',
    'Just a few seconds left...',
    'Almost there...',
    'Processing data...',
    'Taking longer than expected, please hold on...',
    'Finalizing details...',
  ];

  @override
  void initState() {
    super.initState();
    _successAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _scaleAnimation = CurvedAnimation(parent: _successAnimController, curve: Curves.elasticOut);
    
    _messageTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted && !_isSuccess && !_isError) {
        setState(() {
          _messageIndex = (_messageIndex + 1) % _messages.length;
        });
      }
    });

    _fakeProgressTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted && !_isSuccess && !_isError && _progress < 0.95) {
        setState(() {
          // Slow down progress as it reaches 95%
          double increment = (0.95 - _progress) * 0.05;
          if (increment < 0.001) increment = 0.001;
          _progress += increment;
          if (_progress > 0.95) _progress = 0.95;
        });
      }
    });

    _startSync();
  }
  
  @override
  void dispose() {
    _messageTimer?.cancel();
    _fakeProgressTimer?.cancel();
    _successAnimController.dispose();
    super.dispose();
  }

  Future<void> _startSync() async {
    try {
      final result = await widget.syncTask((realProgress) {
        // Only use real progress if it's faster, but cap it at 0.95 until actually done.
        if (mounted && realProgress > _progress) {
          setState(() {
            _progress = realProgress > 0.95 ? 0.95 : realProgress;
          });
        }
      });

      if (mounted) {
        setState(() {
          _progress = 1.0;
          if (result) {
            _isSuccess = true;
            _successAnimController.forward();
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) Navigator.pop(context, true);
            });
          } else {
            _isSuccess = true;
            _successAnimController.forward();
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) Navigator.pop(context, true);
            });
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isError ? widget.errorMessage : (_isSuccess ? widget.successMessage : widget.title),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _isError ? AppColors.danger : const Color(0xFF111827),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_isError) ...[
              const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 64),
              const SizedBox(height: 16),
              Text(
                widget.errorDescription,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF4B5563), height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF3F4F6),
                    foregroundColor: const Color(0xFF374151),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ] else if (_isSuccess) ...[
              ScaleTransition(
                scale: _scaleAnimation,
                child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 64),
              ),
            ] else ...[
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: _progress,
                      strokeWidth: 6,
                      backgroundColor: const Color(0xFFF3F4F6),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                  Text(
                    '${(_progress * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                _messages[_messageIndex],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}