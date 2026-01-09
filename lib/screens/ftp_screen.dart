import 'package:flutter/material.dart';
import 'dart:math';
import '../services/foreground_service.dart';
import '../services/ftp_service_controller.dart';
import 'viewer/ftp_running_screen.dart';

class FTPScreen extends StatefulWidget {
  const FTPScreen({super.key});

  @override
  State<FTPScreen> createState() => _FTPScreenState();
}

class _FTPScreenState extends State<FTPScreen> {
  final port = TextEditingController(text: '');
  final user = TextEditingController(text: 'user');
  final pass = TextEditingController(text: '');

  String randomPort() {
    final r = Random();
    return (49152 + r.nextInt(15000)).toString();
  }

  String randomPassword() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = Random();
    return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> startAutomatic(BuildContext context) async {
    final autoPort = randomPort();
    final autoPass = randomPassword();
    final code = await FtpForegroundService.start(int.parse(autoPort), "user", autoPass);
    debugPrint("ftp start returned: $code");
    if (code == 0) {
      if (!mounted) return;
      Navigator.push(context, PageRouteBuilder(pageBuilder: (_, __, ___) => FTPRunningScreen(port: autoPort, user: "user", password: autoPass)));
    } else {
      showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Failed to start'), content: Text('Code: $code'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
    }
  }

  Future<void> startManual(BuildContext context) async {
    final p = port.text.isEmpty ? "2121" : port.text.trim();
    final u = user.text.trim().isEmpty ? 'user' : user.text.trim();
    final pw = pass.text.isEmpty ? "password" : pass.text.trim();
    final code = await FtpForegroundService.start(int.parse(p), u, pw);
    debugPrint("ftp start returned: $code");
    if (code == 0) {
      if (!mounted) return;
      Navigator.push(context, PageRouteBuilder(pageBuilder: (_, __, ___) => FTPRunningScreen(port: p, user: u, password: pw)));
    } else {
      showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Failed to start'), content: Text('Code: $code'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('FTP Server')),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: ListView(
          physics: const BouncingScrollPhysics(),
          children: [
            Text('Automatic Mode', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: () => startAutomatic(context), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: const Text('Start Server')),
            const SizedBox(height: 32),
            Text('Manual Mode', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
            const SizedBox(height: 12),
            TextField(controller: port, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Port')),
            const SizedBox(height: 16),
            TextField(controller: user, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Username')),
            const SizedBox(height: 16),
            TextField(controller: pass, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Password')),
            const SizedBox(height: 22),
            ElevatedButton(onPressed: () => startManual(context), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: const Text('Start Server')),
          ],
        ),
      ),
    );
  }
}
