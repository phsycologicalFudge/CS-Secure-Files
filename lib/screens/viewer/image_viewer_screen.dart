import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:image/image.dart' as img;

class ImageViewerScreen extends StatefulWidget {
  final String path;
  const ImageViewerScreen({super.key, required this.path});

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  bool _showUi = true;
  int _rotation = 0;
  bool _isGif = false;

  @override
  void initState() {
    super.initState();
    _isGif = widget.path.toLowerCase().endsWith('.gif');
  }

  void _toggleUi() {
    setState(() => _showUi = !_showUi);
    if (_showUi) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _rotate() {
    setState(() {
      _rotation = (_rotation + 90) % 360;
    });
  }

  Future<void> _shareImage() async {
    await Share.shareXFiles([XFile(widget.path)]);
  }

  Future<void> _showInfoDialog() async {
    final file = File(widget.path);
    final stat = await file.stat();
    final sizeKB = (stat.size / 1024).toStringAsFixed(1);
    String res = '';

    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) res = '${decoded.width} x ${decoded.height}';
    } catch (_) {
      res = 'Unknown';
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black87,
        title: const Text('Image Info',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: ${p.basename(widget.path)}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text('Size: $sizeKB KB',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text('Resolution: $res',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text('Modified: ${stat.modified}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text('Path:\n${widget.path}',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onTap: _toggleUi,
            child: Transform.rotate(
              angle: _rotation * 3.1415926 / 180,
              child: _isGif
                  ? Center(
                child: Image.file(File(widget.path)),
              )
                  : PhotoView(
                imageProvider: FileImage(File(widget.path)),
                backgroundDecoration:
                const BoxDecoration(color: Colors.black),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
                loadingBuilder: (context, _) => Center(
                    child: CircularProgressIndicator(
                        color: colors.primary)),
                errorBuilder: (context, error, _) => Center(
                  child: Text('Failed to load image',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: colors.error)),
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: _showUi ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.only(
                      top: 40, left: 8, right: 8, bottom: 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black54, Colors.transparent],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          File(widget.path).uri.pathSegments.last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.only(bottom: 60, top: 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.black54],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.rotate_right,
                            color: Colors.white),
                        onPressed: _rotate,
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.info_outline,
                            color: Colors.white),
                        onPressed: _showInfoDialog,
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.share_outlined,
                            color: Colors.white),
                        onPressed: _shareImage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
