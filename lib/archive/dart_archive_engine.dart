import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'engine.dart';

class DartArchiveEngine implements ArchiveEngine {
  bool _cancelled = false;

  @override
  bool supports(String path) {
    final l = path.toLowerCase();
    return l.endsWith('.zip') ||
        l.endsWith('.tar') ||
        l.endsWith('.tar.gz') ||
        l.endsWith('.tgz') ||
        l.endsWith('.tar.bz2');
  }

  @override
  Future<List<ArchiveEntry>> list(String path, {String? password}) async {
    final bytes = await File(path).readAsBytes();
    Archive arc = _decode(bytes, path);
    return arc.files
        .map((f) => ArchiveEntry(name: f.name, size: f.size, isDir: f.isFile == false))
        .toList();
  }

  @override
  Stream<ArchiveProgress> extract(String path, String destDir,
      {String? password, bool overwrite = false}) async* {
    _cancelled = false;
    final bytes = await File(path).readAsBytes();
    Archive arc = _decode(bytes, path);
    final totalFiles = arc.length;
    int processed = 0;

    for (final f in arc) {
      if (_cancelled) break;
      final outPath = p.join(destDir, f.name);
      if (f.isFile) {
        final outFile = File(outPath);
        if (!overwrite && outFile.existsSync()) continue;
        outFile.createSync(recursive: true);
        outFile.writeAsBytesSync(f.content);
      } else {
        Directory(outPath).createSync(recursive: true);
      }
      processed++;
      final percent = (processed / totalFiles).clamp(0, 1).toDouble();
      yield ArchiveProgress(percent: percent, currentFile: f.name);
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
  }

  Archive _decode(List<int> bytes, String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.zip')) return ZipDecoder().decodeBytes(bytes);
    if (lower.endsWith('.tar')) return TarDecoder().decodeBytes(bytes);
    if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
      final gz = GZipDecoder().decodeBytes(bytes);
      return TarDecoder().decodeBytes(gz);
    }
    if (lower.endsWith('.tar.bz2')) {
      final bz = BZip2Decoder().decodeBytes(bytes);
      return TarDecoder().decodeBytes(bz);
    }
    throw Exception('Unsupported archive format');
  }
}
