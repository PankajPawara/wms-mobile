import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../models/notification_model.dart';

part 'notification_provider.g.dart';

@riverpod
class NotificationNotifier extends _$NotificationNotifier {
  @override
  Future<List<NotificationModel>> build() async {
    return _fetchNotifications();
  }

  Future<List<NotificationModel>> _fetchNotifications() async {
    final client = ref.read(apiClientProvider);
    try {
      final res = await client.get('/notifications');
      final items = res['data']['items'] as List<dynamic>;
      return items.map((e) => NotificationModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      // Return empty on error / offline
      return [];
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchNotifications());
  }

  Future<bool> requestPasswordReset(String employeeId) async {
    final client = ref.read(apiClientProvider);
    try {
      await client.post('/notifications/reset-request', data: {
        'employee_id': employeeId,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> actionResetRequest(String id, String action) async {
    final client = ref.read(apiClientProvider);
    try {
      await client.patch('/notifications/$id/action', data: {
        'action': action,
      });
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> markAllAsRead() async {
    if (state.hasValue && state.value != null) {
      final updated = state.value!.map((e) => e.copyWith(isRead: true)).toList();
      state = AsyncValue.data(updated);
    }

    final client = ref.read(apiClientProvider);
    try {
      await client.post('/notifications/read-all');
      // Quiet refresh
      final res = await client.get('/notifications');
      final items = res['data']['items'] as List<dynamic>;
      state = AsyncValue.data(items.map((e) => NotificationModel.fromJson(e as Map<String, dynamic>)).toList());
    } catch (_) {}
  }
}
