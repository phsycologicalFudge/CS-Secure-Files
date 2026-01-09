import 'package:hive_flutter/hive_flutter.dart';

class OfflineFiles {
  static const String boxName = 'files';

  static Future<List<Map<String, dynamic>>> loadFiles() async {
    final box = await Hive.openBox(boxName);
    final raw = box.get('cache');

    if (raw == null) return [];

    // Safely cast each entry to Map<String, dynamic>
    return (raw as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<void> saveFiles(List<Map<String, dynamic>> files) async {
    final box = await Hive.openBox(boxName);
    await box.put('cache', files);
  }

  static Future<void> clearFiles() async {
    final box = await Hive.openBox(boxName);
    await box.delete('cache');
  }
}
