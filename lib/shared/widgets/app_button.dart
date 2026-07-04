import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';

enum AppButtonVariant { primary, secondary, danger, outline }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final AppButtonVariant variant;
  final IconData? icon;
  final double? width;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bg = switch (variant) {
      AppButtonVariant.primary => AppColors.primary,
      AppButtonVariant.secondary => colorScheme.surface,
      AppButtonVariant.danger => AppColors.danger,
      AppButtonVariant.outline => Colors.transparent,
    };
    final fg = switch (variant) {
      AppButtonVariant.primary => Colors.white,
      AppButtonVariant.secondary => colorScheme.onSurface,
      AppButtonVariant.danger => Colors.white,
      AppButtonVariant.outline => AppColors.primary,
    };

    return SizedBox(
      width: width ?? double.infinity,
      height: AppDimensions.buttonHeight,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            side: variant == AppButtonVariant.outline
                ? const BorderSide(color: AppColors.primary)
                : BorderSide.none,
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: fg,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                  Text(
                    label,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
      ),
    );
  }
}
