import 'dart:io';

class NetworkUtils {
  static Future<String?> getLocalIp() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.address.startsWith('127')) {
            return addr.address;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
