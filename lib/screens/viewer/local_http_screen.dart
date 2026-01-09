import 'package:flutter/material.dart';
import 'package:colourswift_cloud/utils/network_utils.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/http_engine.dart';
import 'local_http_browser_screen.dart';

class LocalHttpScreen extends StatefulWidget {
  const LocalHttpScreen({super.key});

  @override
  State<LocalHttpScreen> createState() => _LocalHttpScreenState();
}

class _LocalHttpScreenState extends State<LocalHttpScreen> {
  final TextEditingController _portController = TextEditingController(text: '8080');
  final TextEditingController _passwordController = TextEditingController();
  bool _running = false;
  String _ip = '';

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _loadIp();
  }

  Future<void> _loadIp() async {
    final ip = await NetworkUtils.getLocalIp();
    setState(() {
      _ip = ip ?? '';
    });
  }

  Future<void> _loadStatus() async {
    final r = await HttpEngine.isRunning();
    setState(() {
      _running = r;
    });
  }

  Future<void> _start() async {
    final port = int.tryParse(_portController.text.trim()) ?? 8080;
    final pass = _passwordController.text.trim();

    final manage = await Permission.manageExternalStorage.request();
    if (!manage.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Serving app folder only. Grant “All files access” to browse device root.'),
        ),
      );
    }

    final code = await HttpEngine.start(port, pass);
    if (code == 0) {
      setState(() => _running = true);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to start server')),
      );
    }
  }

  Future<void> _stop() async{
    await HttpEngine.stop();
    setState(() {
      _running = false;
    });
  }

  void _openBrowser() {
    final port = int.tryParse(_portController.text.trim()) ?? 8080;
    final pass = _passwordController.text.trim();
    if (_ip.isEmpty || pass.isEmpty) {
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocalHttpBrowserScreen(
          host: _ip,
          port: port,
          password: pass,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final canBrowse = _running && _ip.isNotEmpty && _passwordController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local HTTP Server'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Port', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 20),
                    Text('Password', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      onChanged: (_) {
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _running ? _stop : _start,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(_running ? 'Stop Server' : 'Start Server'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_running && _ip.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Access URL', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(
                            'http://$_ip:${_portController.text}/',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 24),
                    if (_running && _ip.isNotEmpty && _passwordController.text.trim().isNotEmpty)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _openBrowser,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Browse files (in app)'),
                        ),
                      ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
