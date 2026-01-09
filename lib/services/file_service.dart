import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import '../models/file_entry.dart';

class FileService {
  final Directory androidRoot = Directory('/storage/emulated/0');

  Future<String> initStartPath() async {
    if (Platform.isAndroid) {
      final dir = androidRoot;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir.path;
    } else {
      return Directory.current.path;
    }
  }

  Future<List<FileEntry>> list(String path) async {
    return compute(_listIsolate, path);
  }

  static List<FileEntry> _listIsolate(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return [];
    final entries = dir.listSync();
    final result = <FileEntry>[];
    for (final e in entries) {
      final stat = e.statSync();
      result.add(FileEntry(
        name: p.basename(e.path),
        path: e.path,
        isDir: e is Directory,
        size: stat.size,
        modified: stat.modified,
      ));
    }
    result.sort((a, b) {
      if (a.isDir && !b.isDir) return -1;
      if (!a.isDir && b.isDir) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  Future<bool> delete(String path) async {
    return compute(_deleteIsolate, path);
  }

  static bool _deleteIsolate(String path) {
    try {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        Directory(path).deleteSync(recursive: true);
      } else if (type == FileSystemEntityType.file) {
        File(path).deleteSync();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> rename(String oldPath, String newName) async {
    return compute(_renameIsolate, {'old': oldPath, 'new': newName});
  }

  static bool _renameIsolate(Map args) {
    try {
      final oldPath = args['old'] as String;
      final newName = args['new'] as String;
      final entityType = FileSystemEntity.typeSync(oldPath);
      final parent = Directory(p.dirname(oldPath));
      final newPath = p.join(parent.path, newName);
      if (entityType == FileSystemEntityType.directory) {
        Directory(oldPath).renameSync(newPath);
      } else if (entityType == FileSystemEntityType.file) {
        File(oldPath).renameSync(newPath);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> extractArchive(String archivePath, String outputDir) async {
    return compute(_extractArchiveIsolate, {'path': archivePath, 'out': outputDir});
  }

  static String? _extractArchiveIsolate(Map args) {
    try {
      final archivePath = args['path'] as String;
      final outputDir = args['out'] as String;
      final file = File(archivePath);
      if (!file.existsSync()) return null;

      final bytes = file.readAsBytesSync();
      Archive archive;
      final lower = archivePath.toLowerCase();
      if (lower.endsWith('.zip')) {
        archive = ZipDecoder().decodeBytes(bytes);
      } else if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
        archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
      } else if (lower.endsWith('.tar.bz2')) {
        archive = TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(bytes));
      } else if (lower.endsWith('.tar')) {
        archive = TarDecoder().decodeBytes(bytes);
      } else {
        return null;
      }

      for (final f in archive) {
        final outPath = p.join(outputDir, f.name);
        if (f.isFile) {
          final outFile = File(outPath);
          outFile.createSync(recursive: true);
          outFile.writeAsBytesSync(f.content as List<int>);
        } else {
          Directory(outPath).createSync(recursive: true);
        }
      }
      return outputDir;
    } catch (_) {
      return null;
    }
  }

  Future<bool> compressSelected(String inputPath, String outPath) async {
    return compute(_compressIsolate, {'in': inputPath, 'out': outPath});
  }

  static bool _compressIsolate(Map args) {
    try {
      final inputPath = args['in'] as String;
      final outPath = args['out'] as String;
      final outFile = File(outPath);
      if (outFile.existsSync()) outFile.deleteSync();

      final encoder = ZipFileEncoder();
      encoder.create(outPath);

      final type = FileSystemEntity.typeSync(inputPath);
      if (type == FileSystemEntityType.directory) {
        encoder.addDirectory(Directory(inputPath), includeDirName: true);
      } else if (type == FileSystemEntityType.file) {
        encoder.addFile(File(inputPath));
      } else {
        encoder.close();
        return false;
      }
      encoder.close();
      return true;
    } catch (_) {
      return false;
    }
  }



  // Flexible compressor that supports zip / tar / tar.gz / tar.bz2
  Future<bool> compressSelectedFlexible(
      String inputPath,
      String outPath, {
        required String format, // 'zip' | 'tar' | 'tar.gz' | 'tar.bz2'
      }) async {
    return compute(_compressFlexibleIsolate, {
      'in': inputPath,
      'out': outPath,
      'format': format,
    });
  }

  static bool _compressFlexibleIsolate(Map args) {
    try {
      final inputPath = args['in'] as String;
      final outPath = args['out'] as String;
      final format = (args['format'] as String).toLowerCase();

      final inputType = FileSystemEntity.typeSync(inputPath);
      if (inputType == FileSystemEntityType.notFound) return false;

      final outFile = File(outPath);
      if (outFile.existsSync()) outFile.deleteSync();

      // ZIP
      if (format == 'zip') {
        final encoder = ZipFileEncoder();
        encoder.create(outPath);
        if (inputType == FileSystemEntityType.directory) {
          encoder.addDirectory(Directory(inputPath), includeDirName: true);
        } else {
          encoder.addFile(File(inputPath));
        }
        encoder.close();
        return true;
      }

      // TAR family (tar / tar.gz / tar.bz2)
      // 1) produce a .tar on disk (temporary if needed) using TarFileEncoder
      String tarPath = outPath;
      if (format == 'tar') {
        if (!tarPath.toLowerCase().endsWith('.tar')) {
          // ensure extension
          tarPath = outPath.replaceAll(RegExp(r'\.(tar\.gz|tar\.bz2)$', caseSensitive: false), '.tar');
          if (!tarPath.toLowerCase().endsWith('.tar')) {
            tarPath = '$outPath.tar';
          }
        }
      } else {
        // for tar.gz or tar.bz2 create a temp .tar next to the final file
        final base = outPath.replaceAll(RegExp(r'\.tar\.gz$|\.tar\.bz2$', caseSensitive: false), '');
        tarPath = '$base.__tmp_build.tar';
      }

      final tarEncoder = TarFileEncoder();
      tarEncoder.create(tarPath);
      if (inputType == FileSystemEntityType.directory) {
        tarEncoder.addDirectory(Directory(inputPath), includeDirName: true);
      } else {
        tarEncoder.addFile(File(inputPath));
      }
      tarEncoder.close();

      // 2) if plain .tar requested, we’re done
      if (format == 'tar') {
        // If outPath was not exactly tarPath (due to extension fix), move it
        if (tarPath != outPath) {
          File(tarPath).renameSync(outPath);
        }
        return true;
      }

      // 3) wrap tar with gzip or bzip2
      final tarBytes = File(tarPath).readAsBytesSync();
      if (format == 'tar.gz') {
        final gzBytes = GZipEncoder().encode(tarBytes) ?? [];
        File(outPath).writeAsBytesSync(gzBytes);
        try { File(tarPath).deleteSync(); } catch (_) {}
        return gzBytes.isNotEmpty;
      }

      if (format == 'tar.bz2') {
        final bzBytes = BZip2Encoder().encode(tarBytes) ?? [];
        File(outPath).writeAsBytesSync(bzBytes);
        try { File(tarPath).deleteSync(); } catch (_) {}
        return bzBytes.isNotEmpty;
      }

      // Unknown format
      // cleanup temp tar if any
      if (tarPath.endsWith('.__tmp_build.tar')) {
        try { File(tarPath).deleteSync(); } catch (_) {}
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  String humanSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    var i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${units[i]}';
  }

  String formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<List<FileEntry>> recursiveSearch(String path, String query) async {
    return compute(_searchIsolate, {'path': path, 'q': query});
  }

  static List<FileEntry> _searchIsolate(Map args) {
    final results = <FileEntry>[];
    final path = args['path'] as String;
    final query = args['q'] as String;
    final dir = Directory(path);
    if (!dir.existsSync()) return results;

    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (p.basename(entity.path).toLowerCase().contains(query.toLowerCase())) {
          final stat = entity.statSync();
          results.add(FileEntry(
            name: p.basename(entity.path),
            path: entity.path,
            isDir: entity is Directory,
            size: stat.size,
            modified: stat.modified,
          ));
        }
      }
    } catch (_) {}
    return results;
  }

  Future<bool> copyFile(String sourcePath, String destinationDir) async {
    return compute(_copyFileIsolate, {'src': sourcePath, 'dst': destinationDir});
  }

  static bool _copyFileIsolate(Map args) {
    try {
      final srcPath = args['src'] as String;
      final dstDir = args['dst'] as String;
      final source = File(srcPath);
      if (!source.existsSync()) return false;

      final baseName = p.basename(srcPath);
      final dstPath = p.join(dstDir, baseName);
      var destination = File(dstPath);

      if (destination.existsSync()) {
        final name = p.basenameWithoutExtension(srcPath);
        final ext = p.extension(srcPath);
        int counter = 1;
        String newPath;
        do {
          newPath = p.join(dstDir, '${name}_copy$counter$ext');
          counter++;
        } while (File(newPath).existsSync());
        destination = File(newPath);
      }
      source.copySync(destination.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> copyMultiple(List<String> sourcePaths, String destinationDir) async {
    for (final path in sourcePaths) {
      await copyFile(path, destinationDir);
    }
  }
}