import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../models/file_entry.dart';

typedef MenuAction = void Function(String action);

class FileContextMenu extends StatelessWidget {
  final FileEntry entry;
  final MenuAction onAction;
  const FileContextMenu({super.key, required this.entry, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isArchive = _isArchive(entry.name);

    return Container(
      color: colors.surface,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tile(context, Icons.open_in_new, 'Open', () => onAction('open')),
            _tile(context, Icons.ios_share, 'Share', () async {
              if (!entry.isDir) {
                await Share.shareXFiles([XFile(entry.path)]);
              }
              Navigator.pop(context);
            }),
            _tile(context, Icons.drive_file_rename_outline, 'Rename', () => onAction('rename')),
            _tile(context, Icons.delete_outline, 'Delete', () => onAction('delete')),

            if (!entry.isDir && isArchive)
              _tile(context, Icons.unarchive_outlined, 'Extract', () => onAction('extract')),

            _tile(context, Icons.archive_outlined, 'Compress', () => onAction('compress')),
            _tile(context, Icons.info_outline, 'Details', () => onAction('details')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String text, VoidCallback onTap) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;

    return ListTile(
      leading: Icon(icon, color: colors.onSurfaceVariant),
      title: Text(
        text,
        style: textTheme.bodyMedium?.copyWith(color: colors.onSurface),
      ),
      onTap: onTap,
      hoverColor: colors.surfaceVariant.withOpacity(0.3),
      splashColor: colors.primary.withOpacity(0.15),
    );
  }

  bool _isArchive(String name) {
    final l = name.toLowerCase();
    return l.endsWith('.zip') ||
        l.endsWith('.tar') ||
        l.endsWith('.tar.gz') ||
        l.endsWith('.tgz') ||
        l.endsWith('.tar.bz2');
  }
}
