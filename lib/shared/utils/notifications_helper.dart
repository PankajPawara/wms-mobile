import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../features/notifications/providers/notification_provider.dart';
import '../../features/auth/providers/auth_provider.dart';

void showNotificationsDialog(BuildContext context, WidgetRef ref) {
  // Mark all as read when opening notifications panel
  ref.read(notificationNotifierProvider.notifier).markAllAsRead();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Consumer(
              builder: (context, ref, child) {
                final notifState = ref.watch(notificationNotifierProvider);
                final isAdmin = ref.read(authNotifierProvider).user?.role == 'admin';

                return Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Notifications',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111827)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // List
                    Expanded(
                      child: notifState.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (err, stack) => Center(child: Text('Error: $err')),
                        data: (items) {
                          if (items.isEmpty) {
                            return const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.notifications_off_outlined, size: 48, color: Colors.grey),
                                  SizedBox(height: 12),
                                  Text('No notifications yet', style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            );
                          }
                          return ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final isPasswordRequest = item.type == 'PASSWORD_RESET_REQUEST';

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: item.isRead ? Colors.white : const Color(0xFFF5F3FF),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: item.isRead ? const Color(0xFFE5E7EB) : const Color(0xFFDDD6FE),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          isPasswordRequest
                                              ? Icons.lock_reset_rounded
                                              : item.type == 'APP_UPDATE'
                                                  ? Icons.system_update_rounded
                                                  : Icons.info_outline_rounded,
                                          color: isPasswordRequest
                                              ? AppColors.primary
                                              : item.type == 'APP_UPDATE'
                                                  ? const Color(0xFFD97706)
                                                  : const Color(0xFF0EA5E9),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            item.title,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF111827)),
                                          ),
                                        ),
                                        Text(
                                          _formatTime(item.createdAt),
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      item.message,
                                      style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563), height: 1.4),
                                    ),
                                    if (isPasswordRequest && !item.isActioned && isAdmin) ...[
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          _ActionButton(
                                            label: 'Reject',
                                            isOutline: true,
                                            onTap: () => ref
                                                .read(notificationNotifierProvider.notifier)
                                                .actionResetRequest(item.id, 'reject'),
                                          ),
                                          const SizedBox(width: 8),
                                          _ActionButton(
                                            label: 'Approve',
                                            isOutline: false,
                                            onTap: () => ref
                                                .read(notificationNotifierProvider.notifier)
                                                .actionResetRequest(item.id, 'approve'),
                                          ),
                                        ],
                                      ),
                                    ] else if (isPasswordRequest && item.isActioned) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE5E7EB),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'Resolved',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF4B5563),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
    },
  );
}

String _formatTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

class _ActionButton extends StatefulWidget {
  final String label;
  final bool isOutline;
  final Future<bool> Function() onTap;

  const _ActionButton({
    required this.label,
    required this.isOutline,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
      );
    }

    if (widget.isOutline) {
      return OutlinedButton(
        onPressed: () async {
          setState(() => _isLoading = true);
          await widget.onTap();
          if (mounted) setState(() => _isLoading = false);
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.danger,
          side: const BorderSide(color: AppColors.danger),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(widget.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      );
    }

    return ElevatedButton(
      onPressed: () async {
        setState(() => _isLoading = true);
        await widget.onTap();
        if (mounted) setState(() => _isLoading = false);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.success,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        elevation: 0,
      ),
      child: Text(widget.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}
