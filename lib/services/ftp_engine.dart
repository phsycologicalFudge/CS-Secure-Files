import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '../server_bridge.dart';

class FtpEngine {
  static final ServerBridge _bridge = ServerBridge();

  static Future<int> start(int port, String user, String pass) async {
    String root;

    final manage = await Permission.manageExternalStorage.status;
    if (manage.isGranted) {
      root = '/storage/emulated/0';
    } else {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return -3;
      root = '${dir.path}/FTP';
      await Directory(root).create(recursive: true);
    }

    try {
      _bridge.ftpStartWithRoot(port, root, user, pass);
      return 0;
    } catch (_) {
      return -1;
    }
  }

  static Future<void> stop() async {
    try {
      _bridge.ftpStop();
    } catch (_) {}
  }

  static Future<bool> isRunning() async {
    try {
      return _bridge.ftpIsRunning();
    } catch (_) {
      return false;
    }
  }
}
