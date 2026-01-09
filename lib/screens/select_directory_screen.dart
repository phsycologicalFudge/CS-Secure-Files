import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class SelectDirectoryScreen extends StatefulWidget {
  final String startPath;
  const SelectDirectoryScreen({super.key, required this.startPath});

  @override
  State<SelectDirectoryScreen> createState() => _SelectDirectoryScreenState();
}

class _SelectDirectoryScreenState extends State<SelectDirectoryScreen> {
  late String currentPath;

  @override
  void initState() {
    super.initState();
    currentPath = widget.startPath;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final dir = Directory(currentPath);
    final children = dir
        .listSync()
        .whereType<Directory>()
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          'Select Destination',
          style: theme.textTheme.titleMedium?.copyWith(color: colors.onSurface),
        ),
        backgroundColor: colors.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        itemCount: children.length,
        itemBuilder: (context, i) {
          final d = children[i];
          return ListTile(
            leading: Icon(Icons.folder, color: colors.primary),
            title: Text(
              p.basename(d.path),
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurface),
            ),
            onTap: () => setState(() => currentPath = d.path),
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton(
          onPressed: () => Navigator.pop(context, currentPath),
          child: const Text('Select this folder'),
        ),
      ),
    );
  }
}
