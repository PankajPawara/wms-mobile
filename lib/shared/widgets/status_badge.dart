import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Use opacity-based tints on semantic colors so they adapt to dark mode
    final (label, bg, fg) = switch (status) {
      'draft' => ('Draft', colorScheme.surfaceContainerHighest, colorScheme.onSurfaceVariant),
      'picking' => ('Picking', AppColors.warning.withValues(alpha: 0.15), AppColors.warning),
      'pending_checking' => ('Pending Check', AppColors.info.withValues(alpha: 0.15), AppColors.info),
      'checked' => ('Checked', AppColors.success.withValues(alpha: 0.15), AppColors.success),
      'cancelled' => ('Cancelled', AppColors.danger.withValues(alpha: 0.15), AppColors.danger),
      'matched' => ('Matched', AppColors.success.withValues(alpha: 0.15), AppColors.success),
      'possible_match' => ('Possible', AppColors.warning.withValues(alpha: 0.15), AppColors.warning),
      'unknown' => ('Unknown', colorScheme.surfaceContainerHighest, colorScheme.onSurfaceVariant),
      'picked' => ('Picked', AppColors.success.withValues(alpha: 0.15), AppColors.success),
      'missing' => ('Missing', AppColors.danger.withValues(alpha: 0.15), AppColors.danger),
      _ => (status, colorScheme.surfaceContainerHighest, colorScheme.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
