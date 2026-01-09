import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class LocalHttpBrowserScreen extends StatefulWidget {
  final String host;
  final int port;
  final String password;

  const LocalHttpBrowserScreen({
    super.key,
    required this.host,
    required this.port,
    required this.password,
  });

  @override
  State<LocalHttpBrowserScreen> createState() => _LocalHttpBrowserScreenState();
}

class _LocalHttpBrowserScreenState extends State<LocalHttpBrowserScreen> {
  String _currentPath = '/';
  bool _loading = false;
  String? _error;
  List<_HttpEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadList();
  }

  String get _baseUrl => 'http://${widget.host}:${widget.port}';

  String _joinPath(String base, String name) {
    if (base == '/' || base.isEmpty) {
      return '/$name';
    }
    return '$base/$name';
  }

  Future<void> _loadList() async {
    if (_currentPath.isEmpty) {
      _currentPath = '/';
    }

    setState(() {
      _loading = true;
      _error = null;
      _entries = [];
    });

    try {
      final uri = Uri.parse('$_baseUrl/list')
          .replace(queryParameters: {'path': _currentPath});
      final resp = await http.get(
        uri,
        headers: {'X-Auth': widget.password},
      );

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data is List) {
          final items = <_HttpEntry>[];
          for (final item in data) {
            if (item is Map<String, dynamic>) {
              final n = item['name']?.toString() ?? '';
              final d = item['is_dir'] == true;
              final s = (item['size'] is int) ? item['size'] as int : 0;
              if (n.isEmpty) continue;
              items.add(_HttpEntry(name: n, isDir: d, size: s));
            }
          }

          items.sort((a, b) {
            if (a.isDir && !b.isDir) return -1;
            if (!a.isDir && b.isDir) return 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

          setState(() {
            _entries = items;
          });
        } else {
          setState(() {
            _error = 'Invalid response format';
          });
        }
      } else if (resp.statusCode == 401) {
        setState(() {
          _error = 'Unauthorized, check password';
        });
      } else if (resp.statusCode == 400) {
        setState(() {
          _error = 'Server rejected the path';
        });
      } else {
        setState(() {
          _error = 'Server error ${resp.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Connection failed';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  void _goUp() {
    if (_currentPath == '/' || _currentPath.isEmpty) return;
    final trimmed = _currentPath.endsWith('/') && _currentPath != '/'
        ? _currentPath.substring(0, _currentPath.length - 1)
        : _currentPath;
    final last = trimmed.lastIndexOf('/');
    if (last <= 0) {
      _currentPath = '/';
    } else {
      _currentPath = trimmed.substring(0, last);
    }
    _loadList();
  }

  void _navigateInto(_HttpEntry entry) {
    if (!entry.isDir) return;
    final newPath = _joinPath(_currentPath, entry.name);
    setState(() {
      _currentPath = newPath;
    });
    _loadList();
  }

  Future<void> _downloadFile(_HttpEntry entry) async {
    if (entry.isDir) return;
    final p = _joinPath(_currentPath, entry.name);
    final uri = Uri.parse('$_baseUrl/download').replace(queryParameters: {
      'path': p,
      'token': widget.password,
    });
    final url = uri.toString();

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('HTTP File Browser'),
        actions: [
          IconButton(
            onPressed: _loadList,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _currentPath,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                IconButton(
                  onPressed: _goUp,
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'Up',
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
              child: Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            )
                : ListView.separated(
              itemCount: _entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final e = _entries[index];
                return ListTile(
                  leading: Icon(
                    e.isDir
                        ? Icons.folder
                        : Icons.insert_drive_file,
                    color: e.isDir
                        ? theme.colorScheme.primary
                        : theme.iconTheme.color,
                  ),
                  title: Text(e.name),
                  subtitle: Text(
                    e.isDir ? 'Folder' : _formatSize(e.size),
                  ),
                  onTap: () {
                    if (e.isDir) {
                      _navigateInto(e);
                    } else {
                      _downloadFile(e);
                    }
                  },
                  trailing: e.isDir
                      ? null
                      : IconButton(
                    icon: const Icon(Icons.download),
                    onPressed: () => _downloadFile(e),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes} B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }
}

class _HttpEntry {
  final String name;
  final bool isDir;
  final int size;

  _HttpEntry({
    required this.name,
    required this.isDir,
    required this.size,
  });
}
