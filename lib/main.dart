import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_colors.dart';
import 'core/router/app_router.dart';
import 'core/providers/theme_provider.dart';
import 'shared/widgets/gemini_verification_banner.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

Future<void> _setupFirebase() async {
  await Firebase.initializeApp();
  
  // Note: Permission request is handled later in the UI layer (MainLayout)
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings();
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );
  
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'inventory_updates_channel_v2', // id
    'Inventory Updates', // name
    description: 'Notifications for location data updates.', // description
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            icon: android.smallIcon ?? '@mipmap/ic_launcher',
            playSound: true,
            enableVibration: true,
            priority: Priority.max,
            importance: Importance.max,
          ),
        ),
      );
    }
  });

  // Subscribe to the global topic for inventory updates
  await FirebaseMessaging.instance.subscribeToTopic('inventory_updates');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Gemini API key is injected at build time via --dart-define=GEMINI_API_KEY=<key>
  // or can be entered manually in the AI Vision settings screen.

  try {
    await _setupFirebase();
  } catch (e) {
    debugPrint("Failed to initialize Firebase (requires google-services.json setup): $e");
  }

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ProviderScope(child: WmsApp()));
}

class WmsApp extends ConsumerWidget {
  const WmsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'WMS',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Column(
          children: [
            const GeminiVerificationBanner(),
            Expanded(child: child ?? const SizedBox()),
          ],
        );
      },
      themeMode: themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          primary: AppColors.primary,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
          primary: AppColors.primary,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 6,
          shadowColor: Colors.black38,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF334155)),
          ),
        ),
      ),
      routerConfig: router,
    );
  }
}
