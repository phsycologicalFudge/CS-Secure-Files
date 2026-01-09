import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: android);
    await _plugin.initialize(init);
  }

  static Future<void> show(String title, String body) async {
    const android = AndroidNotificationDetails(
      'av_scanner',
      'AV Scanner',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: android);
    await _plugin.show(DateTime.now().millisecondsSinceEpoch ~/ 1000, title, body, details);
  }
}
