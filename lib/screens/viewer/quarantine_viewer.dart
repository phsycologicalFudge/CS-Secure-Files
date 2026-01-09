import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../files_screen.dart';

class QuarantineViewer extends StatefulWidget {
  const QuarantineViewer({super.key});

  @override
  State<QuarantineViewer> createState() => _QuarantineViewerState();
}

class _QuarantineViewerState extends State<QuarantineViewer> {
  final quarantineDir = Directory('/storage/emulated/0/Documents/CS_Quarantine');
  List<FileSystemEntity> files = [];
  final Set<String> selected = {};

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    try {
      if (!await quarantineDir.exists()) {
        await quarantineDir.create(recursive: true);
      }
      final items = await quarantineDir
          .list(recursive: false, followLinks: false)
          .where((e) => e is File)
          .toList();
      setState(() => files = items);
    } catch (_) {
      setState(() => files = []);
    }
  }

  Future<void> _deleteSelected() async {
    if (selected.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete selected?'),
        content: Text(
          'This will permanently delete ${selected.length} quarantined file(s). Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    for (final path in selected) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    setState(() {
      selected.clear();
    });
    await _loadFiles();
  }

  Future<void> _restoreSelected() async {
    if (selected.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore selected?'),
        content: Text(
          'Restored files will be moved back to the Downloads folder.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final destDir = Directory('/storage/emulated/0/Download');
    if (!await destDir.exists()) await destDir.create();

    for (final path in selected) {
      try {
        final f = File(path);
        final dest = p.join(destDir.path, p.basename(path));
        await f.rename(dest);
      } catch (_) {}
    }
    setState(() {
      selected.clear();
    });
    await _loadFiles();
  }

  void _toggleSelect(String path) {
    setState(() {
      if (selected.contains(path)) {
        selected.remove(path);
      } else {
        selected.add(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final allSelected = selected.length == files.length && files.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Quarantine'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        actions: [
          if (files.isNotEmpty)
            IconButton(
              icon: Icon(allSelected ? Icons.check_box : Icons.check_box_outline_blank),
              tooltip: allSelected ? 'Unselect all' : 'Select all',
              onPressed: () {
                setState(() {
                  if (allSelected) {
                    selected.clear();
                  } else {
                    selected.addAll(files.map((f) => f.path));
                  }
                });
              },
            ),
        ],
      ),
      body: files.isEmpty
          ? Center(
        child: Text(
          'No quarantined files found',
          style: text.bodyMedium?.copyWith(
            color: text.bodySmall?.color?.withOpacity(0.6),
          ),
        ),
      )
          : ListView.builder(
        itemCount: files.length,
        itemBuilder: (_, i) {
          final f = files[i];
          final name = p.basename(f.path);
          final sel = selected.contains(f.path);
          return Card(
            color: theme.cardColor.withOpacity(sel ? 0.25 : 0.15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListTile(
              onTap: () => _toggleSelect(f.path),
              onLongPress: () {
                showModalBottomSheet(
                  context: context,
                  builder: (_) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.restore),
                          title: const Text('Restore file'),
                          onTap: () async {
                            Navigator.pop(context);
                            await File(f.path).rename(
                              '/storage/emulated/0/Download/$name',
                            );
                            await _loadFiles();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          title: const Text('Delete permanently'),
                          onTap: () async {
                            Navigator.pop(context);
                            await File(f.path).delete();
                            await _loadFiles();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
              leading: Icon(
                Icons.insert_drive_file_rounded,
                color: sel ? theme.colorScheme.primary : theme.iconTheme.color,
              ),
              title: Text(name, style: text.bodyMedium),
              trailing: sel
                  ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                  : null,
            ),
          );
        },
      ),
      bottomNavigationBar: selected.isEmpty
          ? null
          : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore'),
                  onPressed: _restoreSelected,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Delete'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                  ),
                  onPressed: _deleteSelected,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
