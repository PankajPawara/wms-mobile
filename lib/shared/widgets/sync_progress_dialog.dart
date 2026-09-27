import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';

class SyncProgressDialog extends StatefulWidget {
  final Future<bool> Function(void Function(double) onProgress) syncTask;
  final String title;
  final String description;
  final String successMessage;
  final String errorMessage;
  final String errorDescription;

  const SyncProgressDialog({
    super.key, 
    required this.syncTask,
    this.title = 'Syncing Database',
    this.description = 'Please wait a moment while the database is being downloaded and updated...',
    this.successMessage = 'Sync Successful!',
    this.errorMessage = 'Sync Failed',
    this.errorDescription = 'An error occurred while updating the database. You can continue your work and try again later.',
  });

  static Future<bool> show(
    BuildContext context, 
    Future<bool> Function(void Function(double)) syncTask, {
    String title = 'Syncing Database',
    String description = 'Please wait a moment while the database is being downloaded and updated...',
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
        description: description,
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

  @override
  void initState() {
    super.initState();
    _successAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _scaleAnimation = CurvedAnimation(parent: _successAnimController, curve: Curves.elasticOut);
    _startSync();
  }

  Future<void> _startSync() async {
    setState(() {
      _progress = 0.0;
      _isSuccess = false;
      _isError = false;
    });

    try {
      final result = await widget.syncTask((progress) {
        if (mounted) setState(() => _progress = progress);
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
            // Already up to date (returns false when no sync needed)
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
  void dispose() {
    _successAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isSuccess && !_isError) ...[
              Text(
                widget.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                widget.description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: _progress >= 1.0 ? null : _progress,
                      strokeWidth: 6,
                      backgroundColor: Colors.grey[200],
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                  Text(
                    _progress >= 1.0 ? 'Wait...' : '${(_progress * 100).toInt()}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
            ] else if (_isSuccess) ...[
              ScaleTransition(
                scale: _scaleAnimation,
                child: const Icon(Icons.check_circle, color: Colors.green, size: 80),
              ),
              const SizedBox(height: 16),
              Text(
                widget.successMessage,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ] else if (_isError) ...[
              const Icon(Icons.error, color: Colors.red, size: 80),
              const SizedBox(height: 16),
              Text(
                widget.errorMessage,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const SizedBox(height: 8),
              Text(
                widget.errorDescription,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Continue'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _startSync,
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                    child: const Text('Try Again', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
