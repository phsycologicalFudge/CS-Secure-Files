import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateService {
  static const String versionUrl = 'https://phsycologicalfudge.github.io/AVDatabase/version.json';
  static const String defsUrl = 'https://phsycologicalfudge.github.io/AVDatabase/defs.vxpack';
  static const String keyUrl  = 'https://phsycologicalfudge.github.io/AVDatabase/defs_key.bin';

  static Future<Map<String, dynamic>?> checkServerVersion() async {
    try {
      final uri = Uri.parse(versionUrl);
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'ColourSwiftAV/1.0 (Flutter; Android)',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final err = 'HTTP ${response.statusCode} from $uri';
        await _logError(err);
        print(err);
      }
    } catch (e, stack) {
      final err = 'Update server error: $e\n$stack';
      await _logError(err);
      print(err);
    }
    return null;
  }

  static Future<void> _logError(String text) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/update_error.log');
    await file.writeAsString(
      '[${DateTime.now()}] $text\n',
      mode: FileMode.append,
    );
  }


  static Future<String> getLocalVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('defs_version') ?? '0.0.0';
  }

  static Future<void> setLocalVersion(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('defs_version', v);
  }

  static Future<bool> downloadDatabase({
    required void Function(double) onProgress,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final defsPath = '${dir.path}/defs.vxpack';
      final keyPath  = '${dir.path}/defs_key.bin';

      final client = http.Client();

      for (final entry in [
        {'url': defsUrl, 'path': defsPath},
        {'url': keyUrl,  'path': keyPath}
      ]) {
        // Add cache-buster to ensure newest file
        final uri = Uri.parse('${entry['url']}?t=${DateTime.now().millisecondsSinceEpoch}');
        final req = http.Request('GET', uri);
        final res = await client.send(req);
        if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
        final file = File(entry['path']!);
        final total = res.contentLength ?? 0;
        int received = 0;
        final sink = file.openWrite();

        await for (final chunk in res.stream) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) onProgress(received / total);
        }

        await sink.close();
      }

      client.close();
      return true;
    } catch (e) {
      print('Update error: $e');
      return false;
    }
  }

}
