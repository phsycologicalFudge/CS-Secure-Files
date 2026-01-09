import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/services.dart';

import 'theme_controller.dart';
import 'screens/LoadingScreen.dart';

@pragma('vm:entry-point')
void ftpTaskCallback() {
  FlutterForegroundTask.setTaskHandler(FtpTaskHandler());
}

class FtpTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {}
  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {}
  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid) {
    await Hive.initFlutter();
    await Hive.openBox('files');
    await Hive.openBox('settings');
  }

  FlutterForegroundTask.init(
    androidNotificationOptions: const AndroidNotificationOptions(
      channelId: 'cs_ftp',
      channelName: 'ColourSwift FTP',
      channelDescription: 'FTP server running',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.MIN,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: const ForegroundTaskOptions(
      interval: 5000,
      isOnceEvent: false,
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  runApp(const ProviderScope(child: ColourSwiftApp()));
}

class ColourSwiftApp extends ConsumerWidget {
  const ColourSwiftApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF9F9F9),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFEFEFEF),
          iconTheme: IconThemeData(color: Colors.black87),
          titleTextStyle: TextStyle(color: Colors.black87, fontSize: 18),
        ),
        colorScheme: const ColorScheme.light(
          primary: Colors.lightBlueAccent,
          secondary: Colors.lightBlueAccent,
          surface: Colors.white,
          onPrimary: Colors.white,
          onSurface: Colors.black87,
        ),
        cardColor: Colors.white,
        dividerColor: Colors.black12,
        iconTheme: const IconThemeData(color: Colors.black87),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.black87),
          bodyMedium: TextStyle(color: Colors.black87),
          bodySmall: TextStyle(color: Colors.black54),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          iconTheme: IconThemeData(color: Colors.white70),
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 18),
        ),
        colorScheme: const ColorScheme.dark(
          primary: Colors.lightBlueAccent,
          secondary: Colors.lightBlueAccent,
          surface: Color(0xFF1E1E1E),
          onPrimary: Colors.white,
          onSurface: Colors.white70,
        ),
        cardColor: const Color(0xFF1E1E1E),
        dividerColor: Colors.white24,
        iconTheme: const IconThemeData(color: Colors.white70),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70),
          bodySmall: TextStyle(color: Colors.white54),
        ),
      ),
      home: const LoadingScreen(),
    );
  }
}

class ForegroundHost {
  static Future<bool> _ensureNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    final sdk = await _sdkInt();
    if (sdk >= 33) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        final r = await Permission.notification.request();
        if (!r.isGranted) return false;
      }
    }
    return true;
  }

  static Future<int> _sdkInt() async {
    try {
      final method = const MethodChannel('flutter_foreground_task/methods');
      final v = await method.invokeMethod<int>('getSdkInt');
      return v ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> ensureStarted({String? title, String? text}) async {
    if (!await _ensureNotificationPermission()) return false;
    final running = await FlutterForegroundTask.isRunningService;
    if (running) return true;
    await FlutterForegroundTask.startService(
      notificationTitle: title ?? 'ColourSwift Server',
      notificationText: text ?? 'Running',
      callback: ftpTaskCallback,
    );
    return true;
  }

  static Future<void> stop() async {
    final running = await FlutterForegroundTask.isRunningService;
    if (running) {
      await FlutterForegroundTask.stopService();
    }
  }
}
