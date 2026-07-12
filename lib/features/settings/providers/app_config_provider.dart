import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../models/app_config_model.dart';

part 'app_config_provider.g.dart';

@riverpod
class AppConfigNotifier extends _$AppConfigNotifier {
  @override
  Future<AppConfigModel?> build() async {
    return _fetchConfig();
  }

  Future<AppConfigModel?> _fetchConfig() async {
    final client = ref.read(apiClientProvider);
    try {
      final res = await client.get('/system/app-config');
      if (res['success'] == true && res['data'] != null) {
        return AppConfigModel.fromJson(res['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchConfig());
  }
}
