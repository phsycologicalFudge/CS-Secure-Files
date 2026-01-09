import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/clean_service.dart';

class CleanScreen extends StatefulWidget {
  const CleanScreen({super.key});

  @override
  State<CleanScreen> createState() => _CleanScreenState();
}

class _CleanScreenState extends State<CleanScreen> {
  bool scanning = false;
  bool cleaning = false;
  bool cancel = false;

  String status = '';
  double progress = 0;
  int totalFiles = 0;
  double totalSizeMB = 0;
  final List<String> found = [];

  // ===========================================================
  // -------------------- CACHE CLEANER -------------------------
  // ===========================================================
  Future<void> _scanCache() async {
    if (scanning || cleaning) return;
    setState(() {
      scanning = true;
      cancel = false;
      status = 'Scanning cache directories...';
      progress = 0;
      totalFiles = 0;
      totalSizeMB = 0;
      found.clear();
    });

    try {
      final result = await CleanService.scanQuick(onProgress: (pstate) {
        if (cancel) return;
        setState(() => status = 'Scanning ${pstate.folder}');
      });

      if (cancel) {
        setState(() {
          scanning = false;
          status = 'Scan cancelled';
        });
        return;
      }

      setState(() {
        found.addAll(result.paths);
        totalFiles = result.totalFiles;
        totalSizeMB = result.totalSizeMB;
        scanning = false;
        status = totalFiles == 0
            ? 'No cache found'
            : 'Found $totalFiles cache files (${totalSizeMB.toStringAsFixed(2)} MB)';
        progress = 1.0;
      });
    } catch (e) {
      setState(() {
        scanning = false;
        status = 'Error: $e';
      });
    }
  }

  Future<void> _cleanCache() async {
    if (found.isEmpty || cleaning) return;
    setState(() {
      cleaning = true;
      status = 'Deleting cache files...';
    });
    for (final path in List<String>.from(found)) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      cleaning = false;
      found.clear();
      totalFiles = 0;
      totalSizeMB = 0;
      status = 'Cache cleanup complete';
      progress = 0;
    });
  }

  // ===========================================================
  // ---------------- DUPLICATE SCANNER SECTION ----------------
  // ===========================================================
  Future<void> _scanDuplicates(List<String> exts, String label) async {
    if (scanning || cleaning) return;
    setState(() {
      scanning = true;
      cancel = false;
      status = 'Scanning for duplicate $label...';
      progress = 0;
      totalFiles = 0;
      totalSizeMB = 0;
      found.clear();
    });

    try {
      final result = await CleanService.scanDuplicates(exts);

      if (cancel) {
        setState(() {
          scanning = false;
          status = 'Scan cancelled';
        });
        return;
      }

      setState(() {
        found.addAll(result.paths);
        totalFiles = result.totalFiles;
        totalSizeMB = result.totalSizeMB;
        scanning = false;
        status = totalFiles == 0
            ? 'No duplicate $label found'
            : 'Found $totalFiles duplicate $label (${totalSizeMB.toStringAsFixed(2)} MB)';
        progress = 1.0;
      });
    } catch (e) {
      setState(() {
        scanning = false;
        status = 'Error: $e';
      });
    }
  }

  // ===========================================================
  // --------------------------- UI ----------------------------
  // ===========================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Cleaner lite',
          style: text.titleLarge?.copyWith(color: text.bodyLarge?.color),
        ),
        backgroundColor: theme.appBarTheme.backgroundColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (scanning || cleaning) ...[
              LinearProgressIndicator(
                value: scanning ? progress : null,
                minHeight: 6,
                backgroundColor: theme.dividerColor.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
              ),
              const SizedBox(height: 8),
              Text(status, style: text.bodySmall),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: scanning
                      ? () => setState(() {
                    cancel = true;
                    status = 'Cancelling...';
                  })
                      : null,
                  child: const Text('Cancel'),
                ),
              ),
            ] else ...[
              // ---------------- Cache cleaner section ----------------
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Cache Cleaner',
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _scanCache,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white, // <-- ensures visible text
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Scan Cache'),
                  ),
                  ElevatedButton(
                    onPressed: found.isEmpty ? null : _cleanCache,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white, // <-- ensures visible text
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Clean'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ---------------- Duplicate finder section ----------------
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Duplicate Finder',
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.apps_outlined),
                    label: const Text('APKs'),
                    onPressed: () =>
                        _scanDuplicates(['.apk'], 'APKs'),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Images'),
                    onPressed: () => _scanDuplicates(
                        ['.jpg', '.jpeg', '.png', '.webp'], 'images'),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.movie_outlined),
                    label: const Text('Videos'),
                    onPressed: () => _scanDuplicates(
                        ['.mp4', '.mkv', '.mov', '.avi', '.webm'], 'videos'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ---------------- Results ----------------
              if (totalFiles > 0)
                Text(
                  '$totalFiles files • ${totalSizeMB.toStringAsFixed(2)} MB found',
                  style: text.bodyLarge,
                ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: found.length,
                  itemBuilder: (_, i) {
                    final path = found[i];
                    return ListTile(
                      leading: Icon(
                        Icons.insert_drive_file_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        p.basename(path),
                        style: text.bodyLarge,
                      ),
                      subtitle: Text(
                        path,
                        style: text.bodySmall?.copyWith(fontSize: 12),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}