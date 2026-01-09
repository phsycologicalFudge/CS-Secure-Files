import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../archive/engine.dart';
import '../../archive/dart_archive_engine.dart';

class ArchiveViewerScreen extends StatefulWidget {
  final String path;
  const ArchiveViewerScreen({super.key, required this.path});

  @override
  State<ArchiveViewerScreen> createState() => _ArchiveViewerScreenState();
}

class _ArchiveViewerScreenState extends State<ArchiveViewerScreen> {
  final ArchiveEngine engine = DartArchiveEngine();
  List<ArchiveEntry> entries = [];
  bool loading = true;
  bool extracting = false;
  double progress = 0;
  String current = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await engine.list(widget.path);
      if (mounted) {
        setState(() {
          entries = list;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _extract() async {
    if (extracting) return;
    setState(() => extracting = true);
    final dest = p.dirname(widget.path);
    await for (final prog in engine.extract(widget.path, dest, overwrite: true)) {
      if (!mounted) break;
      setState(() {
        progress = prog.percent;
        current = prog.currentFile;
      });
    }
    if (mounted) {
      setState(() => extracting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Extraction complete'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        elevation: 1,
        backgroundColor: colors.surface,
        title: Text(
          p.basename(widget.path),
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleMedium?.copyWith(color: colors.onSurface),
        ),
      ),
      floatingActionButton: extracting
          ? null
          : FloatingActionButton.extended(
        onPressed: _extract,
        label: const Text('Extract All'),
        icon: const Icon(Icons.unarchive_outlined),
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: loading
            ? Center(child: CircularProgressIndicator(color: colors.primary))
            : extracting
            ? _buildExtractProgress(colors, textTheme)
            : entries.isEmpty
            ? Center(
          child: Text(
            'Empty archive',
            style: textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        )
            : _buildEntryList(colors, textTheme),
      ),
    );
  }

  Widget _buildExtractProgress(ColorScheme colors, TextTheme textTheme) {
    return Center(
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        color: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_bottom, size: 48),
              const SizedBox(height: 12),
              Text(
                'Extracting files...',
                style: textTheme.titleMedium?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                current.isEmpty ? '' : p.basename(current),
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(8),
                color: colors.primary,
                backgroundColor: colors.surfaceVariant,
              ),
              const SizedBox(height: 10),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: textTheme.bodySmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntryList(ColorScheme colors, TextTheme textTheme) {
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => Divider(
        color: colors.outlineVariant.withOpacity(0.3),
        height: 1,
      ),
      itemBuilder: (context, i) {
        final f = entries[i];
        final icon = f.isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined;
        return _SlideFadeIn(
          delay: Duration(milliseconds: 60 + i * 12),
          child: ListTile(
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: colors.surfaceVariant,
              child: Icon(icon, color: colors.primary, size: 20),
            ),
            title: Text(
              f.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyLarge?.copyWith(color: colors.onBackground),
            ),
            subtitle: Text(
              '${f.size} bytes',
              style: textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SlideFadeIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _SlideFadeIn({required this.child, this.delay = Duration.zero, super.key});

  @override
  State<_SlideFadeIn> createState() => _SlideFadeInState();
}

class _SlideFadeInState extends State<_SlideFadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  late final Animation<double> _opacity = CurvedAnimation(parent: _c, curve: Curves.easeOut);
  late final Animation<Offset> _offset = Tween(begin: const Offset(0, .08), end: Offset.zero).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}
