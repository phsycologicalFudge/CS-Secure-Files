import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/file_entry.dart';
import '../services/file_service.dart';

class DirectoryViewBlurred extends StatelessWidget {
  final List<FileEntry> items;
  final Function(FileEntry) onOpen;
  final Function(FileEntry) onMenu;
  final FileService svc;

  const DirectoryViewBlurred({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onMenu,
    required this.svc,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    if (items.isEmpty) {
      return Center(
        child: Text(
          'No files found',
          style: text.bodySmall,
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              color: theme.scaffoldBackgroundColor.withOpacity(0.12),
            ),
          ),
        ),
        ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) =>
              Divider(color: theme.dividerColor, height: 1),
          itemBuilder: (context, i) {
            final f = items[i];
            final isDir = f.isDir;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onOpen(f),
              onLongPress: () => onMenu(f), // ✅ this line makes long press work
              child: ListTile(
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Icon(
                  isDir ? Icons.folder : Icons.insert_drive_file_outlined,
                  color: isDir
                      ? theme.colorScheme.primary
                      : theme.iconTheme.color,
                  size: 26,
                ),
                title: Text(
                  f.name,
                  style: text.bodyMedium?.copyWith(fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  isDir
                      ? svc.formatDate(f.modified)
                      : '${svc.humanSize(f.size)} • ${svc.formatDate(f.modified)}',
                  style: text.bodySmall?.copyWith(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: Icon(Icons.more_vert,
                      color: theme.iconTheme.color, size: 20),
                  onPressed: () => onMenu(f),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
