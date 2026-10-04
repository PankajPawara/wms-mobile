import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';

class NotificationSandboxScreen extends ConsumerStatefulWidget {
  const NotificationSandboxScreen({super.key});

  @override
  ConsumerState<NotificationSandboxScreen> createState() => _NotificationSandboxScreenState();
}

class _NotificationSandboxScreenState extends ConsumerState<NotificationSandboxScreen> {
  String? _fcmToken;
  bool _isLoading = false;
  String _logs = '';

  @override
  void initState() {
    super.initState();
    _fetchToken();
  }

  void _addLog(String message) {
    setState(() {
      _logs += '${DateTime.now().toIso8601String().substring(11, 19)}: $message\n';
    });
    debugPrint(message);
  }

  Future<void> _fetchToken() async {
    setState(() => _isLoading = true);
    try {
      final token = await FirebaseMessaging.instance.getToken();
      setState(() {
        _fcmToken = token;
      });
      _addLog('FCM Token fetched successfully: ${token?.substring(0, 15)}...');
    } catch (e) {
      _addLog('Error fetching FCM Token: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _triggerLocalNotification() async {
    try {
      _addLog('Triggering local notification...');
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.show(
        999,
        'Local Test',
        'This is a local notification test',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'inventory_updates_channel_v2',
            'Inventory Updates',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            enableVibration: true,
          ),
        ),
      );
      _addLog('Local notification triggered successfully.');
    } catch (e) {
      _addLog('Error triggering local notification: $e');
    }
  }

  Future<void> _sendRemoteTestPush() async {
    if (_fcmToken == null) {
      _addLog('No FCM token available to send push.');
      return;
    }

    setState(() => _isLoading = true);
    _addLog('Sending test push request to backend...');
    try {
      final apiClient = ref.read(apiClientProvider);
      final res = await apiClient.post(
        '/notifications/test-push',
        data: {
          'token': _fcmToken,
          'title': 'Remote Push Test',
          'body': 'This was sent via Firebase Admin SDK from the backend.',
        },
      );
      if (res['success'] == true) {
        _addLog('Backend successfully pushed message to FCM.');
      } else {
        _addLog('Backend returned failure: $res');
      }
    } catch (e) {
      _addLog('Error calling backend API: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Sandbox'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('FCM Token', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SelectableText(_fcmToken ?? 'Loading...'),
                    if (_fcmToken != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _fcmToken!));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy'),
                        ),
                      )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _fetchToken,
              child: const Text('Refresh FCM Token'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _triggerLocalNotification,
              child: const Text('Trigger Local Notification'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isLoading ? null : _sendRemoteTestPush,
              child: const Text('Send Remote Test Push (Backend)'),
            ),
            const SizedBox(height: 16),
            const Text('Logs', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _logs,
                    style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
