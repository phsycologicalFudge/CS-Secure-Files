import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../main.dart';
import 'ftp_engine.dart';

class FtpForegroundService {
  static Future<int> start(int port, String user, String pass) async {
    FlutterForegroundTask.init(
      androidNotificationOptions: const AndroidNotificationOptions(
        channelId: 'cs_ftp_channel',
        channelName: 'ColourSwift FTP',
        channelDescription: 'Local FTP server',
        isSticky: true,
        playSound: false,
        showWhen: false,
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

    await FlutterForegroundTask.startService(
      notificationTitle: 'ColourSwift FTP Server',
      notificationText: 'Server running on port $port',
      callback: ftpTaskCallback,
    );

    return await FtpEngine.start(port, user, pass);
  }

  static Future<void> stop() async {
    await FtpEngine.stop();
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  static Future<bool> isRunning() async {
    return FtpEngine.isRunning();
  }
}
