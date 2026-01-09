import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/foreground_service.dart';
import '../../services/ftp_service_controller.dart';

class FTPRunningScreen extends StatefulWidget {
  final String port;
  final String user;
  final String password;

  const FTPRunningScreen({super.key, required this.port, required this.user, required this.password});

  @override
  State<FTPRunningScreen> createState() => _FTPRunningScreenState();
}

class _FTPRunningScreenState extends State<FTPRunningScreen> {
  String ip = '';

  @override
  void initState() {
    super.initState();
    _loadIp();
    _watchService();
  }

  Future<void> _loadIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      String found = '';
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final host = addr.address;
          if (host.startsWith('192.168.') || host.startsWith('10.') || host.startsWith('172.')) {
            found = host;
            break;
          }
        }
        if (found.isNotEmpty) break;
      }
      setState(() => ip = found.isEmpty ? '0.0.0.0' : found);
    } catch (_) {
      setState(() => ip = '0.0.0.0');
    }
  }

  void _watchService() async {
    while (mounted) {
      final running = await FtpForegroundService.isRunning();
      if (!running) {
        if (!mounted) return;
        Navigator.pop(context);
        break;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = 'ftp://${widget.user}:${widget.password}@$ip:${widget.port}';

    return Scaffold(
      appBar: AppBar(title: const Text('FTP Server Running')),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_done, size: 88, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(18)),
                child: Column(
                  children: [
                    Text('IP Address: $ip', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    Text('Port: ${widget.port}', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    Text('Username: ${widget.user}', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    Text('Password: ${widget.password}', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              QrImageView(
                data: url,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 14),
              Text(url, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied connection details')));
                },
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('Copy Details'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  await FtpForegroundService.stop();
                  if (mounted) Navigator.pop(context);
                },
                child: Text('Stop Server', style: TextStyle(color: theme.colorScheme.error)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
