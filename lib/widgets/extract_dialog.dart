import 'package:flutter/material.dart';

class ExtractChoice {
  final bool toCurrentDir;
  final bool openOnComplete;
  final String? chosenDir;
  ExtractChoice({
    required this.toCurrentDir,
    required this.openOnComplete,
    this.chosenDir,
  });
}

class ExtractDialog extends StatefulWidget {
  final String currentDir;
  const ExtractDialog({super.key, required this.currentDir});

  @override
  State<ExtractDialog> createState() => _ExtractDialogState();
}

class _ExtractDialogState extends State<ExtractDialog> {
  String mode = 'current';
  bool openAfter = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;

    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'Extract archive',
        style: textTheme.titleMedium?.copyWith(color: colors.onSurface),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<String>(
            value: 'current',
            groupValue: mode,
            onChanged: (v) => setState(() => mode = v!),
            title: Text(
              'Current directory',
              style: textTheme.bodyMedium?.copyWith(color: colors.onSurface),
            ),
            activeColor: colors.primary,
          ),
          RadioListTile<String>(
            value: 'choose',
            groupValue: mode,
            onChanged: (v) => setState(() => mode = v!),
            title: Text(
              'Choose directory',
              style: textTheme.bodyMedium?.copyWith(color: colors.onSurface),
            ),
            activeColor: colors.primary,
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: openAfter,
            onChanged: (v) => setState(() => openAfter = v ?? true),
            title: Text(
              'Open when complete',
              style: textTheme.bodyMedium?.copyWith(color: colors.onSurface),
            ),
            activeColor: colors.primary,
            checkColor: colors.onPrimary,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop<ExtractChoice>(context),
          child: Text(
            'Cancel',
            style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop<ExtractChoice>(
              context,
              ExtractChoice(
                toCurrentDir: mode == 'current',
                openOnComplete: openAfter,
              ),
            );
          },
          child: Text(
            'Extract',
            style: textTheme.bodyMedium?.copyWith(color: colors.primary),
          ),
        ),
      ],
    );
  }
}
