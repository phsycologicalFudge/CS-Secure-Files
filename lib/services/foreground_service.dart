import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'ftp_engine.dart';

@pragma('vm:entry-point')
void ftpTaskStart() {
  FlutterForegroundTask.setTaskHandler(_FtpTaskHandler());
}

class LegacyForegroundService {
  static Future<void> start(int port, String user, String pass) async {
    FlutterForegroundTask.init(
      androidNotificationOptions: const AndroidNotificationOptions(
        channelId: 'cs_ftp_channel',
        channelName: 'ColourSwift FTP',
        channelDescription: 'Local FTP server running in background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        isSticky: true,
        playSound: false,
        showWhen: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    await FlutterForegroundTask.startService(
      notificationTitle: 'ColourSwift FTP Server',
      notificationText: 'Server running on port $port',
      callback: ftpTaskStart,
    );

    await FtpEngine.start(port, user, pass);
  }

  static Future<void> stop() async {
    await FtpEngine.stop();
    await FlutterForegroundTask.stopService();
  }

  static Future<bool> isRunning() async {
    return FtpEngine.isRunning();
  }
}

class _FtpTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    await FlutterForegroundTask.clearAllData();
  }

  @override
  void onButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp("/");
  }
}
