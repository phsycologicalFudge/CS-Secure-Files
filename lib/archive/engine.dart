import 'dart:async';

class ArchiveEntry {
  final String name;
  final int size;
  final bool isDir;
  ArchiveEntry({required this.name, required this.size, required this.isDir});
}

class ArchiveProgress {
  final double percent;
  final String currentFile;
  const ArchiveProgress({required this.percent, required this.currentFile});
}

abstract class ArchiveEngine {
  bool supports(String path);
  Future<List<ArchiveEntry>> list(String path, {String? password});
  Stream<ArchiveProgress> extract(String path, String destDir,
      {String? password, bool overwrite = false});
  Future<void> cancel();
}
