import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class PermissionHelper {
  static Future<bool> ensureStorageAccess() async {
    if (!Platform.isAndroid) return true;

    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }

    final status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }
}
