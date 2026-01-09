
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:colourswift_cloud/screens/viewer/audio_viewer_screen.dart';
import 'package:colourswift_cloud/screens/viewer/video_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../models/file_clipboard.dart';
import '../models/file_entry.dart';
import '../services/file_service.dart';
import '../widgets/extract_dialog.dart';
import '../widgets/floating_menu.dart';
import '../widgets/processing_animation.dart';
import 'cloud_hub_tab.dart';
import 'viewer/image_viewer_screen.dart';
import 'viewer/text_viewer_screen.dart';
import 'viewer/archive_viewer_screen.dart';
import '../widgets/coming_soon_tab.dart';
import 'settings_tab.dart';
import 'landing_screen.dart';
import 'select_directory_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'viewer/pdf_viewer_screen.dart';

PageRouteBuilder<T> animatedRoute<T>(Widget page, {bool reverse = false}) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final scaleTween = Tween<double>(
        begin: reverse ? 1.02 : 0.96,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(scale: animation.drive(scaleTween), child: child),
      );
    },
  );
}

enum FileSection { all, recent, favourites, bin }

final sectionProvider = StateProvider<FileSection>((ref) => FileSection.all);
final searchQueryProvider = StateProvider<String>((ref) => '');

class FilesScreen extends ConsumerStatefulWidget {
  final String? startPath;
  const FilesScreen({super.key, this.startPath});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  final svc = FileService();
  String currentPath = '';
  bool loading = true;
  FileClipboard? _clipboard;

  bool isGridView = false;
  String sortType = 'name';
  bool showHidden = false;
  String tempFilter = 'all';

  final Map<String, Uint8List?> _thumbCache = {};

  List<Map<String, String>> _storageOptions = [];
  String? _selectedStoragePath;
  bool _checkedPermOnExternal = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _clearCacheOnExit();
    super.dispose();
  }


  Future<void> _boot() async {
    await _loadPrefs();
    currentPath = await svc.initStartPath();
    if (Platform.isAndroid) {
      await _detectStorageMounts();
      if (_storageOptions.isNotEmpty) {
        final internal = _storageOptions.firstWhere(
              (e) => e['kind'] == 'internal',
          orElse: () => _storageOptions.first,
        );
        _selectedStoragePath = internal['path'];
        if (currentPath.isEmpty) currentPath = internal['path'] ?? currentPath;
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isGridView = prefs.getBool('view_grid') ?? false;
      sortType = prefs.getString('sort_type') ?? 'name';
      showHidden = prefs.getBool('show_hidden') ?? false;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('view_grid', isGridView);
    await prefs.setString('sort_type', sortType);
    await prefs.setBool('show_hidden', showHidden);
  }

  Future<void> _detectStorageMounts() async {
    final List<Map<String, String>> found = [];
    String? internalPath;
    try {
      final emu0 = Directory('/storage/emulated/0');
      if (emu0.existsSync()) internalPath = emu0.path;
    } catch (_) {}
    try {
      final root = Directory('/storage');
      if (root.existsSync()) {
        for (final entity in root.listSync(followLinks: false)) {
          if (entity is Directory) {
            final name = p.basename(entity.path);
            final path = entity.path;
            if (name.isEmpty) continue;
            if (!Directory(path).existsSync()) continue;
            if (name == 'enc_emulated' || name == 'enc_subdir') continue;
            if (name == 'emulated' && internalPath != null) continue;
            String kind = 'external';
            String label = 'External ($name)';
            if (internalPath != null && path == p.dirname(internalPath)) continue;
            if (internalPath != null && path == internalPath) {
              kind = 'internal';
              label = 'Internal Storage';
            } else if (name == 'self') {
              kind = 'system';
              label = 'Self';
            } else if (name == 'emulated') {
              kind = 'system';
              label = 'Emulated';
            } else if (RegExp(r'^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$').hasMatch(name)) {
              kind = 'external';
              label = 'SD or USB ($name)';
            }
            found.add({'label': label, 'path': path, 'kind': kind});
          }
        }
      }
    } catch (_) {}
    if (internalPath != null && notIn(found, internalPath)) {
      found.insert(0, {'label': 'Internal Storage', 'path': internalPath, 'kind': 'internal'});
    }
    if (found.isEmpty && currentPath.isNotEmpty) {
      found.add({'label': 'Current', 'path': currentPath, 'kind': 'internal'});
    }
    setState(() {
      _storageOptions = found;
    });
  }

  bool notIn(List<Map<String, String>> list, String path) {
    for (final m in list) {
      if (m['path'] == path) return false;
    }
    return true;
  }

  Future<void> _switchStorage(String path) async {
    if (Platform.isAndroid) {
      bool readable = false;
      try {
        final dir = Directory(path);
        readable = dir.existsSync();
        if (readable) {
          dir.listSync().take(1).toList();
        }
      } catch (_) {
        readable = false;
      }
      if (!readable && !_checkedPermOnExternal) {
        final status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          final granted = await Permission.manageExternalStorage.request();
          if (!granted.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Storage permission is required for this volume')),
              );
            }
            return;
          }
        }
        _checkedPermOnExternal = true;
      }
    }
    setState(() {
      _selectedStoragePath = path;
      currentPath = path;
    });
  }

  Future<void> _clearCacheOnExit() async {
    try {
      final tempDir = Directory.systemTemp;
      if (tempDir.existsSync()) {
        for (final entity in tempDir.listSync(recursive: false)) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
      final appCache = await getTemporaryDirectory();
      if (appCache.existsSync()) {
        for (final entity in appCache.listSync(recursive: false)) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<Uint8List?> _getVideoThumb(String path) async {
    if (_thumbCache.containsKey(path)) return _thumbCache[path];
    final data = await VideoThumbnail.thumbnailData(
      video: path,
      imageFormat: ImageFormat.PNG,
      maxWidth: 320,
      quality: 60,
    );
    _thumbCache[path] = data;
    return data;
  }

  bool _isImage(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.webp') ||
        n.endsWith('.bmp') ||
        n.endsWith('.gif');
  }

  bool _isVideo(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.mp4') ||
        n.endsWith('.mkv') ||
        n.endsWith('.mov') ||
        n.endsWith('.avi') ||
        n.endsWith('.webm');
  }

  Widget _buildThumbBox(FileEntry e) {
    final theme = Theme.of(context);
    final iconColor = theme.iconTheme.color?.withOpacity(0.85);
    if (e.isDir) {
      return Icon(Icons.folder, size: 38, color: Colors.blue.shade600);
    }
    final name = e.name.toLowerCase();
    if (_isImage(name)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(e.path),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
          const Icon(Icons.broken_image_outlined, size: 36, color: Colors.grey),
        ),
      );
    }
    if (_isVideo(name)) {
      return FutureBuilder<Uint8List?>(
        future: _getVideoThumb(e.path),
        builder: (ctx, snap) {
          if (snap.hasData && snap.data != null) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(snap.data!, fit: BoxFit.cover),
            );
          }
          return Icon(Icons.videocam, size: 36, color: Colors.deepPurple.shade400);
        },
      );
    }
    if (name.endsWith('.apk')) {
      return Icon(Icons.android, size: 34, color: Colors.green.shade600);
    } else if (name.endsWith('.pdf')) {
      return Icon(Icons.picture_as_pdf, size: 34, color: Colors.red.shade600);
    } else if (name.endsWith('.zip') ||
        name.endsWith('.rar') ||
        name.endsWith('.7z') ||
        name.endsWith('.tar') ||
        name.endsWith('.gz')) {
      return Icon(Icons.archive_outlined, size: 34, color: Colors.orange.shade700);
    } else if (name.endsWith('.txt') ||
        name.endsWith('.md') ||
        name.endsWith('.json') ||
        name.endsWith('.log')) {
      return Icon(Icons.description_outlined, size: 34, color: Colors.indigo.shade400);
    } else if (name.endsWith('.doc') || name.endsWith('.docx')) {
      return Icon(Icons.article_outlined, size: 34, color: Colors.blue.shade500);
    } else if (name.endsWith('.xls') || name.endsWith('.xlsx')) {
      return Icon(Icons.grid_on, size: 34, color: Colors.green.shade700);
    } else if (name.endsWith('.ppt') || name.endsWith('.pptx')) {
      return Icon(Icons.slideshow, size: 34, color: Colors.orange.shade800);
    } else if (name.endsWith('.mp3') ||
        name.endsWith('.wav') ||
        name.endsWith('.ogg') ||
        name.endsWith('.flac')) {
      return Icon(Icons.music_note, size: 34, color: Colors.purple.shade500);
    }
    return Icon(Icons.insert_drive_file, size: 32, color: iconColor);
  }

  List<FileEntry> _applyFolderFirstAndSort(List<FileEntry> items) {
    List<FileEntry> list = List<FileEntry>.from(items);
    if (!showHidden) {
      list = list.where((e) => !p.basename(e.path).startsWith('.')).toList();
    }
    if (tempFilter == 'images') {
      list = list.where((e) => _isImage(e.name)).toList();
    } else if (tempFilter == 'videos') {
      list = list.where((e) => _isVideo(e.name)).toList();
    }
    final dirs = list.where((e) => e.isDir).toList();
    final files = list.where((e) => !e.isDir).toList();
    dirs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    switch (sortType) {
      case 'size':
        files.sort((a, b) => a.size.compareTo(b.size));
        break;
      case 'time':
        files.sort((a, b) => b.modified.compareTo(a.modified));
        break;
      default:
        files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return [...dirs, ...files];
  }

  Future<List<FileEntry>> _fetch(FileSection section, String query) async {
    List<FileEntry> items;
    if (query.trim().isNotEmpty) {
      items = await svc.recursiveSearch(currentPath, query.trim());
    } else {
      items = await svc.list(currentPath);
    }
    if (section == FileSection.recent) {
      final now = DateTime.now();
      items = items.where((e) => now.difference(e.modified).inDays <= 7).toList();
    }
    return _applyFolderFirstAndSort(items);
  }

  Future<void> _openEntry(FileEntry e) async {
    if (e.isDir) {
      setState(() => currentPath = e.path);
      return;
    }
    final lower = e.name.toLowerCase();
    if (lower.endsWith('.mp3') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.flac')) {
      if (mounted) {
        Navigator.push(context, animatedRoute(AudioViewerScreen(path: e.path)));
      }
      return;
    }
    if (lower.endsWith('.pdf')) {
      if (mounted) {
        Navigator.push(context, animatedRoute(PdfViewerScreen(path: e.path)));
      }
      return;
    }
    if (lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.json') ||
        lower.endsWith('.log') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm')) {
      if (mounted) {
        Navigator.push(context, animatedRoute(TextViewerScreen(path: e.path)));
      }
      return;
    }
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.gif')) {
      if (mounted) {
        Navigator.push(context, animatedRoute(ImageViewerScreen(path: e.path)));
      }
      return;
    }
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.webm')) {
      if (mounted) {
        Navigator.push(context, animatedRoute(VideoViewerScreen(path: e.path)));
      }
      return;
    }
    if (lower.endsWith('.zip') ||
        lower.endsWith('.tar') ||
        lower.endsWith('.tar.gz') ||
        lower.endsWith('.tgz') ||
        lower.endsWith('.tar.bz2')) {
      if (mounted) {
        Navigator.push(context, animatedRoute(ArchiveViewerScreen(path: e.path)));
      }
      return;
    }
    if (lower.endsWith('.apk')) {
      if (Platform.isAndroid) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: Theme.of(context).dialogBackgroundColor,
            title: const Text('Install APK'),
            content: const Text('Do you want to install this APK?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'Install',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        );

        if (proceed == true) {
          try {
            await openApkInstaller(e.path);
          } catch (_) {
            await OpenFilex.open(e.path);
          }
        }
      }
      return;
    }
    final res = await OpenFilex.open(e.path);
    if (res.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to open file',
            style: TextStyle(color: Theme.of(context).colorScheme.onError),
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    }
  }

  Future<void> _onMenu(FileEntry e) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).dialogBackgroundColor,
      builder: (_) {
        final color = Theme.of(context).colorScheme.primary;
        final text = Theme.of(context).textTheme.bodyLarge;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.open_in_new_outlined, color: color),
                title: Text('Open', style: text),
                onTap: () async {
                  Navigator.pop(context);
                  await _openEntry(e);
                },
              ),
              ListTile(
                leading: Icon(Icons.copy_outlined, color: color),
                title: Text('Copy', style: text),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _clipboard = FileClipboard(ClipboardAction.copy, [e]);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.drive_file_rename_outline, color: color),
                title: Text('Rename', style: text),
                onTap: () async {
                  Navigator.pop(context);
                  await _rename(e);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.redAccent),
                title: Text('Delete', style: text),
                onTap: () async {
                  Navigator.pop(context);
                  final ok = await svc.delete(e.path);
                  if (ok) setState(() {});
                },
              ),
              ListTile(
                leading: Icon(Icons.archive_outlined, color: color),
                title: Text('Compress', style: text),
                onTap: () async {
                  Navigator.pop(context);
                  await _compress(e);
                },
              ),
              ListTile(
                leading: Icon(Icons.unarchive_outlined, color: color),
                title: Text('Extract', style: text),
                onTap: () async {
                  Navigator.pop(context);
                  await _extractFlow(e);
                },
              ),
              ListTile(
                leading: Icon(Icons.info_outline, color: color),
                title: Text('Details', style: text),
                onTap: () async {
                  Navigator.pop(context);
                  await _details(e);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _chooseCompressionFormat() async {
    String selected = 'zip';
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).dialogBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        final text = Theme.of(ctx).textTheme;
        final color = Theme.of(ctx).colorScheme.primary;
        Widget option({
          required String value,
          required String label,
          String? subtitle,
        }) {
          final active = selected == value;
          return RadioListTile<String>(
            value: value,
            groupValue: selected,
            onChanged: (v) {
              selected = v!;
              (ctx as Element).markNeedsBuild();
            },
            title: Text(label, style: text.bodyMedium),
            subtitle: subtitle == null
                ? null
                : Text(
              subtitle,
              style: text.bodySmall?.copyWith(
                color: text.bodySmall?.color?.withOpacity(0.7),
              ),
            ),
            activeColor: color,
          );
        }
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        'Choose compression format',
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                    option(
                      value: 'zip',
                      label: 'ZIP (.zip)',
                      subtitle: 'Standard compression format, widely supported.',
                    ),
                    option(
                      value: 'tar',
                      label: 'TAR (.tar)',
                      subtitle: 'Uncompressed archive.',
                    ),
                    option(
                      value: 'tar.gz',
                      label: 'TAR.GZ (.tar.gz)',
                      subtitle: 'Compressed with GZip, a nice middle ground.',
                    ),
                    option(
                      value: 'tar.bz2',
                      label: 'TAR.BZ2 (.tar.bz2)',
                      subtitle: 'Smallest file size, but slower to create and extract.',
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, selected),
                        child: const Text('Confirm'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _askName(BuildContext context, String placeholder) async {
    final c = TextEditingController(text: placeholder);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).dialogBackgroundColor,
        title: Text('Enter name', style: Theme.of(context).textTheme.bodyMedium),
        content: TextField(
          controller: c,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: 'File or folder name',
            hintStyle: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: Theme.of(context).textTheme.bodySmall),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: Text('Create', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(FileEntry e) async {
    final c = TextEditingController(text: e.name);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).dialogBackgroundColor,
        title: Text('Rename', style: Theme.of(context).textTheme.bodyMedium),
        content: TextField(
          controller: c,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: 'New name',
            hintStyle: Theme.of(context).textTheme.bodySmall,
            enabledBorder: const OutlineInputBorder(),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: Theme.of(context).textTheme.bodySmall),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: Text('Save', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    final ok = await svc.rename(e.path, v);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rename failed', style: Theme.of(context).textTheme.bodyMedium)),
      );
    }
    setState(() {});
  }

  Future<void> _compress(FileEntry e) async {
    final format = await _chooseCompressionFormat();
    if (format == null) return;
    final name = await _askName(context, '${p.basename(e.path)}.$format');
    if (name == null || name.trim().isEmpty) return;
    var outPath = p.join(currentPath, name.trim());
    if (!outPath.toLowerCase().endsWith('.$format')) outPath += '.$format';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProcessingAnimation(title: 'Compressing ${p.basename(e.path)}'),
    );
    final success = await FileService().compressSelectedFlexible(
      e.path,
      outPath,
      format: format,
    );
    if (mounted) Navigator.pop(context);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(success ? 'Compression Complete' : 'Compression Failed'),
        content: Text(success
            ? '${p.basename(e.path)} was compressed successfully.'
            : 'An error occurred during compression.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (success) setState(() {});
  }

  Future<void> _extractFlow(FileEntry e) async {
    final choice = await showDialog<ExtractChoice>(
      context: context,
      builder: (_) => ExtractDialog(currentDir: currentPath),
    );
    if (choice == null) return;
    String dest = currentPath;
    if (!choice.toCurrentDir) {
      final dir = await Navigator.push<String>(
        context,
        animatedRoute(SelectDirectoryScreen(startPath: currentPath)),
      );
      if (dir == null) return;
      dest = dir;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProcessingAnimation(title: 'Extracting ${p.basename(e.path)}'),
    );
    final out = await FileService().extractArchive(e.path, dest);
    if (mounted) Navigator.pop(context);
    if (out == null) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Extraction Failed'),
          content: const Text('This archive format is unsupported or corrupted.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Extraction Complete'),
        content: Text('${p.basename(e.path)} was extracted successfully.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (choice.openOnComplete) {
      setState(() => currentPath = out);
    } else {
      setState(() {});
    }
  }

  Future<void> _details(FileEntry e) async {
    final title = e.isDir ? 'Folder details' : 'File details';
    final size = e.isDir ? '' : svc.humanSize(e.size);
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).dialogBackgroundColor,
        title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: ${e.name}'),
            const SizedBox(height: 6),
            Text('Path: ${e.path}'),
            const SizedBox(height: 6),
            if (!e.isDir) Text('Size: $size'),
            if (!e.isDir) const SizedBox(height: 6),
            Text('Modified: ${svc.formatDate(e.modified)}'),
          ],
        ),
        actions: [
          if (!e.isDir)
            TextButton(
              onPressed: () async {
                await Share.shareXFiles([XFile(e.path)]);
                if (mounted) Navigator.pop(context);
              },
              child: Text('Share', style: Theme.of(context).textTheme.bodySmall),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _goUp() async {
    if (Platform.isAndroid) {
      final selectedRoot = _selectedStoragePath;
      if (selectedRoot != null && currentPath == selectedRoot) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            animatedRoute(const LandingScreen(), reverse: true),
                (route) => false,
          );
        }
        return;
      }
      if (currentPath == svc.androidRoot.path) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            animatedRoute(const LandingScreen(), reverse: true),
                (route) => false,
          );
        }
        return;
      }
    }
    final parent = Directory(currentPath).parent.path;
    setState(() => currentPath = parent);
  }

  Future<void> openApkInstaller(String apkPath) async {
    try {
      if (Platform.isAndroid) {
        final file = File(apkPath);
        if (await file.exists()) {
          await OpenFilex.open(apkPath, type: 'application/vnd.android.package-archive');
        } else {
          throw Exception('File not found');
        }
      }
    } catch (e) {}
  }

  Widget _storageDropdown() {
    if (!Platform.isAndroid) {
      final section = ref.watch(sectionProvider);
      final title = switch (section) {
        FileSection.all => 'All Files',
        FileSection.recent => 'Recent Files',
        FileSection.favourites => 'Cloud Storage',
        FileSection.bin => 'Recycle Bin'
      };
      return Text(title,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis);
    }

    if (_storageOptions.isEmpty) {
      return Text('All Files',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis);
    }

    final selected = _storageOptions.firstWhere(
          (e) => e['path'] == _selectedStoragePath,
      orElse: () => _storageOptions.first,
    );

    return PopupMenuButton<String>(
      offset: const Offset(0, 40),
      constraints: const BoxConstraints(maxWidth: 240),
      color: Theme.of(context).dialogBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (v) => _switchStorage(v),
      itemBuilder: (ctx) => _storageOptions
          .map((opt) => PopupMenuItem<String>(
        value: opt['path'],
        child: Text(opt['label'] ?? opt['path']!, overflow: TextOverflow.ellipsis),
      ))
          .toList(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              selected['label'] ?? 'Storage',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }

  Widget _buildGrid(List<FileEntry> items) {
    return GridView.builder(
      key: ValueKey('grid_${currentPath}_${tempFilter}_$sortType'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      physics: const BouncingScrollPhysics(),
      cacheExtent: 600,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.78,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final e = items[i];
        return InkWell(
          onTap: () => _openEntry(e),
          onLongPress: () => _onMenu(e),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _buildThumbBox(e),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  e.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildList(List<FileEntry> items) {
    return ListView.builder(
      key: ValueKey('list_${currentPath}_${tempFilter}_$sortType'),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
      physics: const BouncingScrollPhysics(),
      cacheExtent: 600,
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final e = items[i];
        return ListTile(
          onTap: () => _openEntry(e),
          onLongPress: () => _onMenu(e),
          leading: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: _buildThumbBox(e),
            ),
          ),
          title: Text(e.name, overflow: TextOverflow.ellipsis),
          subtitle: e.isDir
              ? const Text('Folder')
              : Text('${svc.humanSize(e.size)} • ${svc.formatDate(e.modified)}'),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _onMenu(e),
          ),
        );
      },
    );
  }


  Widget _buildFileView(List<FileEntry> items) {
    return isGridView ? _buildGrid(items) : _buildList(items);
  }


  @override
  Widget build(BuildContext context) {
    final section = ref.watch(sectionProvider);
    final query = ref.watch(searchQueryProvider);
    final sectionTitle = switch (section) {
      FileSection.all => 'All Files',
      FileSection.recent => 'Recent Files',
      FileSection.favourites => 'Cloud Storage',
      FileSection.bin => 'Recycle Bin'
    };
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async => _goUp(),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          elevation: 0,
          centerTitle: false,
          titleSpacing: 0,
          title: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back,
                    color: Theme.of(context).appBarTheme.foregroundColor),
                onPressed: loading ? null : _goUp,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _storageDropdown(),
                    Text(currentPath,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.tune),
              color: Theme.of(context).iconTheme.color,
              onPressed: _showViewOptionsSheet,
            ),
            IconButton(
              icon: const Icon(Icons.search),
              color: Theme.of(context).iconTheme.color,
              onPressed: () async {
                final c =
                TextEditingController(text: ref.read(searchQueryProvider));
                await showModalBottomSheet(
                  context: context,
                  backgroundColor: Theme.of(context).dialogBackgroundColor,
                  isScrollControlled: true,
                  builder: (_) => Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                    ),
                    child: TextField(
                      controller: c,
                      autofocus: true,
                      style: Theme.of(context).textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: 'Search files',
                        hintStyle: Theme.of(context).textTheme.bodySmall,
                        prefixIcon: Icon(Icons.search,
                            color: Theme.of(context).iconTheme.color),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) =>
                      ref.read(searchQueryProvider.notifier).state = v,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              color: Theme.of(context).iconTheme.color,
              onPressed: () async {
                Navigator.push(context, animatedRoute(const SettingsTab()));
              },
            ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : (section == FileSection.favourites
            ? const CloudHubTab()
            : section == FileSection.bin
            ? const ComingSoonTab(
          title: 'Recycle Bin',
          message:
          'The Recycle Bin will be available soon.\nDeleted files will appear here by storing them in the cloud.',
        )

            : FutureBuilder<List<FileEntry>>(
          future: _fetch(section, query),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                  child: CircularProgressIndicator());
            }
            final items = snap.data ?? [];
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: Transform.scale(
                    scale: 0.985 + (animation.value * 0.015),
                    child: child,
                  ),
                );
              },
              child: _buildFileView(items),
            );
          },
        )),
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor:
          Theme.of(context).bottomNavigationBarTheme.backgroundColor ??
              Theme.of(context).scaffoldBackgroundColor,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Theme.of(context).unselectedWidgetColor,
          currentIndex: FileSection.values.indexOf(section),
          onTap: (i) =>
          ref.read(sectionProvider.notifier).state = FileSection.values[i],
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'All'),
            BottomNavigationBarItem(icon: Icon(Icons.access_time), label: 'Recent'),
            BottomNavigationBarItem(icon: Icon(Icons.cloud_outlined), label: 'Cloud'),
            BottomNavigationBarItem(icon: Icon(Icons.delete_outline), label: 'Bin'),
          ],
          type: BottomNavigationBarType.fixed,
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_clipboard != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FloatingActionButton.extended(
                    heroTag: 'paste_button',
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    icon: const Icon(Icons.paste, color: Colors.white),
                    label: const Text('Paste here',
                        style: TextStyle(color: Colors.white)),
                    onPressed: () async {
                      final files = _clipboard!;
                      for (final f in files.items) {
                        await svc.copyFile(f.path, currentPath);
                      }
                      setState(() => _clipboard = null);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Paste complete')),
                      );
                    },
                  ),
                ),
              FloatingMenu(
                onNewFolder: () async {
                  final name = await _askName(context, 'New Folder');
                  if (name != null && name.trim().isNotEmpty) {
                    final dir = Directory(p.join(currentPath, name.trim()));
                    await dir.create(recursive: true);
                    setState(() {});
                  }
                },
                onNewFile: () async {
                  final name = await _askName(context, 'Untitled.txt');
                  if (name != null && name.trim().isNotEmpty) {
                    final file = File(p.join(currentPath, name.trim()));
                    await file.writeAsString('');
                    setState(() {});
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
  Future<void> _showViewOptionsSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).dialogBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) {
        final textTheme = Theme.of(context).textTheme;
        final color = Theme.of(context).colorScheme.primary;

        Widget sectionTitle(String t) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            t,
            style: textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sectionTitle('View'),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: Icon(
                              isGridView ? Icons.grid_view : Icons.view_list,
                              color: color,
                            ),
                            onPressed: () {
                              setModal(() => isGridView = !isGridView);
                              setState(() => isGridView = !isGridView);
                              _savePrefs();
                              Navigator.pop(context);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.image_outlined),
                            color: tempFilter == 'images' ? color : null,
                            onPressed: () {
                              setModal(() => tempFilter =
                              tempFilter == 'images' ? 'all' : 'images');
                              setState(() => tempFilter =
                              tempFilter == 'images' ? 'all' : 'images');
                              Navigator.pop(context);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.videocam_outlined),
                            color: tempFilter == 'videos' ? color : null,
                            onPressed: () {
                              setModal(() => tempFilter =
                              tempFilter == 'videos' ? 'all' : 'videos');
                              setState(() => tempFilter =
                              tempFilter == 'videos' ? 'all' : 'videos');
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      sectionTitle('Sort'),
                      Column(
                        children: [
                          RadioListTile<String>(
                            value: 'name',
                            groupValue: sortType,
                            title: const Text('Name'),
                            onChanged: (v) {
                              setModal(() => sortType = v!);
                              setState(() => sortType = v!);
                              _savePrefs();
                            },
                          ),
                          RadioListTile<String>(
                            value: 'size',
                            groupValue: sortType,
                            title: const Text('Size'),
                            onChanged: (v) {
                              setModal(() => sortType = v!);
                              setState(() => sortType = v!);
                              _savePrefs();
                            },
                          ),
                          RadioListTile<String>(
                            value: 'time',
                            groupValue: sortType,
                            title: const Text('Modified'),
                            onChanged: (v) {
                              setModal(() => sortType = v!);
                              setState(() => sortType = v!);
                              _savePrefs();
                            },
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      sectionTitle('Other'),
                      SwitchListTile(
                        title: const Text('Show hidden files'),
                        value: showHidden,
                        onChanged: (v) {
                          setModal(() => showHidden = v);
                          setState(() => showHidden = v);
                          _savePrefs();
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

}
