import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ProgressInfo {
  final String folder;
  final int files;
  final double sizeMB;

  const ProgressInfo(this.folder, this.files, this.sizeMB);
}

class CleanResult {
  final List<String> paths;
  final double totalSizeMB;
  final int totalFiles;

  const CleanResult({
    required this.paths,
    required this.totalSizeMB,
    required this.totalFiles,
  });
}

class CleanService {
  static const int _maxDepth = 3;

  /// Quick scan (cache/temp/thumbs)
  static Future<CleanResult> scanQuick({Function(ProgressInfo)? onProgress}) async {
    final port = ReceivePort();
    await Isolate.spawn(_scanQuickIsolate, port.sendPort);
    final send = await port.first as SendPort;

    final response = ReceivePort();
    send.send({'reply': response.sendPort});

    final completer = Completer<CleanResult>();
    response.listen((msg) {
      if (msg is ProgressInfo) {
        onProgress?.call(msg);
      } else if (msg is CleanResult) {
        completer.complete(msg);
        response.close();
      }
    });

    return completer.future;
  }

  static void _scanQuickIsolate(SendPort mainSendPort) {
    final command = ReceivePort();
    mainSendPort.send(command.sendPort);

    command.listen((msg) {
      if (msg is Map && msg['reply'] is SendPort) {
        final reply = msg['reply'] as SendPort;
        final found = <String>[];
        double totalSizeMB = 0;
        final roots = [
          '/storage/emulated/0/Download',
          '/storage/emulated/0/DCIM',
          '/storage/emulated/0/Pictures',
          '/storage/emulated/0/Movies',
          '/storage/emulated/0/Documents',
          '/storage/emulated/0/Music',
        ];

        void walk(Directory dir, [int depth = 0]) {
          if (depth > _maxDepth) return;
          List<FileSystemEntity> entries;
          try {
            entries = dir.listSync(followLinks: false);
          } catch (_) {
            return;
          }
          reply.send(ProgressInfo(dir.path, found.length, totalSizeMB));
          for (final e in entries) {
            if (e is Directory) {
              final name = p.basename(e.path).toLowerCase();
              if (name.contains('cache') || name.contains('temp') || name == '.thumbnails') {
                try {
                  for (final f in e.listSync(recursive: true, followLinks: false)) {
                    if (f is File) {
                      found.add(f.path);
                      totalSizeMB += f.lengthSync() / (1024 * 1024);
                    }
                  }
                } catch (_) {}
                continue;
              }
              walk(e, depth + 1);
            } else if (e is File) {
              final name = p.basename(e.path).toLowerCase();
              if (name.endsWith('.tmp') ||
                  name.endsWith('.log') ||
                  name.contains('thumb') ||
                  name.contains('cache')) {
                try {
                  found.add(e.path);
                  totalSizeMB += e.lengthSync() / (1024 * 1024);
                } catch (_) {}
              }
            }
          }
        }

        for (final r in roots) {
          final d = Directory(r);
          if (d.existsSync()) walk(d);
        }

        reply.send(CleanResult(
          paths: found,
          totalSizeMB: totalSizeMB,
          totalFiles: found.length,
        ));
      }
    });
  }

  /// App cache (temporary directory)
  static Future<CleanResult> scanAppCache() async {
    final tmp = await getTemporaryDirectory();
    final response = ReceivePort();
    await Isolate.spawn(_scanDirIsolate, {'sendPort': response.sendPort, 'root': tmp.path});
    final result = await response.first as CleanResult;
    response.close();
    return result;
  }

  static void _scanDirIsolate(Map args) {
    final send = args['sendPort'] as SendPort;
    final root = args['root'] as String;
    final files = <String>[];
    double totalSizeMB = 0;
    final dir = Directory(root);
    if (dir.existsSync()) {
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is File) {
          files.add(e.path);
          totalSizeMB += e.lengthSync() / (1024 * 1024);
        }
      }
    }
    send.send(CleanResult(paths: files, totalSizeMB: totalSizeMB, totalFiles: files.length));
  }

  /// True duplicate detector (safe, SHA-1 based)
  static Future<CleanResult> scanDuplicates(List<String> extensions) async {
    final response = ReceivePort();
    await Isolate.spawn(_scanDuplicatesIsolate, {
      'sendPort': response.sendPort,
      'exts': extensions.map((e) => e.toLowerCase()).toList(),
    });
    final result = await response.first as CleanResult;
    response.close();
    return result;
  }

  static void _scanDuplicatesIsolate(Map args) async {
    final send = args['sendPort'] as SendPort;
    final extensions = (args['exts'] as List).cast<String>();

    final dirs = [
      Directory('/storage/emulated/0/Download'),
      Directory('/storage/emulated/0/DCIM'),
      Directory('/storage/emulated/0/Movies'),
      Directory('/storage/emulated/0/Pictures'),
      Directory('/storage/emulated/0/Documents'),
    ];

    final map = <String, List<File>>{};
    final dup = <String>[];
    double totalSizeMB = 0;

    for (final dir in dirs) {
      if (!dir.existsSync()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final ext = p.extension(entity.path).toLowerCase();
          if (!extensions.contains(ext)) continue;

          try {
            final digest = await sha1.bind(entity.openRead()).first;
            final key = '$digest:${await entity.length()}';
            map.putIfAbsent(key, () => []).add(entity);
          } catch (_) {}
        }
      } catch (_) {}
    }

    for (final group in map.values) {
      if (group.length > 1) {
        for (final f in group.skip(1)) {
          dup.add(f.path);
          totalSizeMB += (await f.length()) / (1024 * 1024);
        }
      }
    }

    send.send(CleanResult(
      paths: dup,
      totalSizeMB: totalSizeMB,
      totalFiles: dup.length,
    ));
  }
}
