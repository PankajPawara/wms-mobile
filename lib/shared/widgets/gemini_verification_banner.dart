import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/models/extracted_memo.dart';
import '../../core/providers/gemini_verification_provider.dart';

/// A persistent top banner that shows Gemini verification progress.
/// Mount this widget at the root scaffold so it survives screen navigation.
/// It auto-hides when verification is idle or complete and the user has dismissed it.
class GeminiVerificationBanner extends ConsumerStatefulWidget {
  const GeminiVerificationBanner({super.key});

  @override
  ConsumerState<GeminiVerificationBanner> createState() =>
      _GeminiVerificationBannerState();
}

class _GeminiVerificationBannerState
    extends ConsumerState<GeminiVerificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightAnim;
  bool _dismissed = false;
  GeminiVerificationStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _heightAnim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _show() {
    _dismissed = false;
    _controller.forward();
  }

  void _hide() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(geminiVerificationProvider);

    // React to status changes
    if (state.status != _lastStatus) {
      _lastStatus = state.status;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (state.isRunning) {
          _show();
        } else if (state.isCompleted || state.hasFailed) {
          // Keep banner visible briefly so user can see the result
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted && !_dismissed) _hide();
          });
        }
      });
    }

    return SizeTransition(
      sizeFactor: _heightAnim,
      alignment: Alignment.topCenter,
      child: _buildBannerContent(context, state),
    );
  }

  Widget _buildBannerContent(
      BuildContext context, GeminiVerificationState state) {
    final (bg, icon, text) = switch (state.status) {
      GeminiVerificationStatus.running => (
          AppColors.primary,
          Icons.auto_fix_high_rounded,
          state.totalCount > 0
              ? 'Correcting with AI... (${state.processedCount}/${state.totalCount})'
              : 'Correcting with AI...',
        ),
      GeminiVerificationStatus.completed => (
          AppColors.success,
          Icons.check_circle_rounded,
          '\u2705 AI verification complete — ${state.updatedItems.where((i) => i.confidence.score >= 80).length} items verified',
        ),
      GeminiVerificationStatus.failed => (
          AppColors.danger,
          Icons.error_rounded,
          'AI verification failed: ${state.errorMessage ?? 'unknown error'}',
        ),
      _ => (AppColors.primary, Icons.auto_fix_high_rounded, 'Processing...'),
    };

    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (state.isRunning)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!state.isRunning)
                GestureDetector(
                  onTap: () {
                    _dismissed = true;
                    _hide();
                  },
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
