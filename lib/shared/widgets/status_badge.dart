import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      'draft' => ('Draft', AppColors.border, AppColors.textSecondary),
      'picking' => ('Picking', AppColors.warningLight, AppColors.warning),
      'pending_checking' =>
        ('Pending Check', AppColors.infoLight, AppColors.info),
      'checked' => ('Checked', AppColors.successLight, AppColors.success),
      'cancelled' => ('Cancelled', AppColors.dangerLight, AppColors.danger),
      'matched' => ('Matched', AppColors.successLight, AppColors.success),
      'possible_match' =>
        ('Possible', AppColors.warningLight, AppColors.warning),
      'unknown' => ('Unknown', AppColors.border, AppColors.textSecondary),
      'picked' => ('Picked', AppColors.successLight, AppColors.success),
      'missing' => ('Missing', AppColors.dangerLight, AppColors.danger),
      _ => (status, AppColors.border, AppColors.textSecondary),
    };

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
