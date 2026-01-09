import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class TextViewerScreen extends StatelessWidget {
  final String path;
  const TextViewerScreen({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isMarkdown = path.toLowerCase().endsWith('.md');

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text(
          path.split('/').last,
          style: textTheme.titleMedium?.copyWith(color: colors.onSurface),
        ),
        iconTheme: IconThemeData(color: colors.onSurface),
      ),
      body: FutureBuilder<String>(
        future: File(path).readAsString(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return Center(
              child: CircularProgressIndicator(color: colors.primary),
            );
          }

          final content = snap.data!;
          if (isMarkdown) {
            return Markdown(
              data: content,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: textTheme.bodyMedium?.copyWith(
                  color: colors.onBackground,
                  fontSize: 15,
                ),
                h1: textTheme.headlineSmall?.copyWith(color: colors.primary),
                h2: textTheme.titleLarge?.copyWith(color: colors.primary),
                h3: textTheme.titleMedium?.copyWith(color: colors.primary),
                h4: textTheme.titleSmall?.copyWith(color: colors.primary),
                code: TextStyle(
                  backgroundColor: colors.surfaceVariant,
                  color: colors.primary,
                  fontFamily: 'monospace',
                ),
                blockquote: textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
                a: TextStyle(color: colors.secondary),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              content,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.onBackground,
                fontSize: 15,
                fontFamily: 'monospace',
              ),
            ),
          );
        },
      ),
    );
  }
}