import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../server_bridge.dart';

class HttpEngine {
  static final ServerBridge _bridge = ServerBridge();

  static Future<int> start(int port, String password) async {
    String root;

    final manage = await Permission.manageExternalStorage.status;
    if (manage.isGranted) {
      root = '/storage/emulated/0';
    } else {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return -3;
      root = '${dir.path}/HTTP';
      await Directory(root).create(recursive: true);
    }

    try {
      _bridge.httpStartWithRoot(port, root, password);
      return 0;
    } catch (_) {
      return -1;
    }
  }

  static Future<void> stop() async {
    try {
      _bridge.httpStop();
    } catch (_) {}
  }

  static Future<bool> isRunning() async {
    try {
      return _bridge.httpIsRunning();
    } catch (_) {
      return false;
    }
  }
}
