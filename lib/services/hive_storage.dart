import 'package:hive_flutter/hive_flutter.dart';

class HiveStorage {
  static Future<void> save(String boxName, String key, dynamic value) async {
    final box = await Hive.openBox(boxName);
    await box.put(key, value);
  }

  static Future<dynamic> get(String boxName, String key) async {
    final box = await Hive.openBox(boxName);
    return box.get(key);
  }

  static Future<void> delete(String boxName, String key) async {
    final box = await Hive.openBox(boxName);
    await box.delete(key);
  }

  static Future<void> clearBox(String boxName) async {
    final box = await Hive.openBox(boxName);
    await box.clear();
  }
}
