import 'dart:io';
import 'package:path/path.dart' as p;

class FileEntry {
  final String path;
  final bool isDir;
  final String name;
  final int size;
  final DateTime modified;

  FileEntry({
    required this.path,
    required this.isDir,
    required this.name,
    required this.size,
    required this.modified,
  });

  static FileEntry fromEntity(FileSystemEntity e) {
    final st = e.statSync();
    return FileEntry(
      path: e.path,
      isDir: e is Directory,
      name: p.basename(e.path),
      size: e is File ? st.size : 0,
      modified: st.modified,
    );
  }
}
