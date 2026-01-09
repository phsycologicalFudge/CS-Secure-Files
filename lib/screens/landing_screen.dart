import 'dart:io';
import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'clean_screen.dart';
import 'files_screen.dart';
import 'settings_tab.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/clean_service.dart';
import '../utils/permissions.dart';
import 'package:colourswift_cloud/screens/cloud_hub_tab.dart';

PageRouteBuilder<T> animatedRoute<T>(Widget page, {bool reverse = false}) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final scaleTween = Tween<double>(
        begin: reverse ? 1.02 : 0.96,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutCubic));

      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: animation.drive(scaleTween),
          child: child,
        ),
      );
    },
  );
}

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  double usedGB = 0;
  double totalGB = 0;
  double percentUsed = 0;
  String version = '';

  @override
  void initState() {
    super.initState();
    _loadStorageInfo();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      version = 'v${info.version}';
    });
  }

  Future<void> _openExternalStorage() async {
    final granted = await PermissionHelper.ensureStorageAccess();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Storage access is needed to view external files.'),
          action: SnackBarAction(label: 'Open Settings', onPressed: openAppSettings),
        ),
      );
      return;
    }

    List<String> candidates = [];
    for (final base in ['/storage', '/mnt/media_rw']) {
      final dir = Directory(base);
      if (dir.existsSync()) {
        for (final entity in dir.listSync(followLinks: false)) {
          if (entity is Directory) {
            final name = entity.uri.pathSegments.isNotEmpty
                ? entity.uri.pathSegments.last.replaceAll('/', '')
                : '';
            if (RegExp(r'^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$').hasMatch(name)) {
              candidates.add(entity.path);
            }
          }
        }
      }
    }

    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No external storage detected.')),
      );
      return;
    }

    final firstExternal = candidates.first;
    if (!mounted) return;
    Navigator.of(context).push(
      animatedRoute(FilesScreen(startPath: firstExternal)),
    );
  }

  Future<void> _loadStorageInfo() async {
    try {
      if (Platform.isAndroid) {
        final result = await Process.run('df', ['/storage/emulated/0']);
        if (result.exitCode == 0) {
          final output = result.stdout.toString().split('\n');
          if (output.length > 1) {
            final data = output[1].split(RegExp(r'\s+'));
            if (data.length >= 5) {
              final totalKb = double.tryParse(data[1]) ?? 0;
              final usedKb = double.tryParse(data[2]) ?? 0;
              setState(() {
                totalGB = totalKb / (1024 * 1024);
                usedGB = usedKb / (1024 * 1024);
                percentUsed = usedGB / totalGB;
              });
              return;
            }
          }
        }
      }

      setState(() {
        totalGB = 0;
        usedGB = 0;
        percentUsed = 0;
      });
    } catch (e) {
      debugPrint('Error loading storage info: $e');
    }
  }

  void _openMainStorage() async {
    final granted = await PermissionHelper.ensureStorageAccess();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Storage access is needed to view files. (Your data remains on this device)',
          ),
          action: SnackBarAction(
            label: 'Open Settings',
            onPressed: openAppSettings,
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(animatedRoute(const FilesScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        title: Text(
          'Storage Overview',
          style: text.titleLarge?.copyWith(
            color: text.bodyLarge?.color,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(color: theme.iconTheme.color),
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, color: theme.iconTheme.color),
            onPressed: () {
              Navigator.push(context, animatedRoute(const SettingsTab()));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: CircularPercentIndicator(
                    radius: 70.0,
                    lineWidth: 10.0,
                    animation: true,
                    percent: percentUsed.isNaN ? 0 : percentUsed.clamp(0, 1),
                    center: Text(
                      '${(percentUsed * 100).toStringAsFixed(0)}%',
                      style: text.headlineSmall?.copyWith(
                        color: text.bodyLarge?.color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    circularStrokeCap: CircularStrokeCap.round,
                    progressColor: theme.colorScheme.primary,
                    backgroundColor: theme.dividerColor.withOpacity(0.1),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    'Main Storage',
                    style: text.titleMedium?.copyWith(
                      color: text.bodyMedium?.color?.withOpacity(0.9),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    '${usedGB.toStringAsFixed(1)} GB / ${totalGB.toStringAsFixed(1)} GB used',
                    style: text.bodySmall?.copyWith(
                      color: text.bodySmall?.color?.withOpacity(0.8),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildCard(context, Icons.phone_android, 'Main Storage', _openMainStorage),
                    _buildCard(context, Icons.sd_card, 'External Storage', _openExternalStorage),
                    _buildCard(context, Icons.cleaning_services, 'Clean Storage', () {
                      Navigator.push(context, animatedRoute(const CleanScreen()));
                    }),
                    _buildCard(context, Icons.cloud_outlined, 'Remote Access', () {
                      Navigator.push(context, animatedRoute(const CloudHubScreen()));
                    }),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 8),
            child: Text(
              version.isEmpty ? 'Loading version…' : 'CS Secure Files $version',
              style: text.bodySmall?.copyWith(
                color: text.bodySmall?.color?.withOpacity(0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 32),
            const SizedBox(height: 10),
            Text(
              title,
              style: text.bodyLarge?.copyWith(
                color: text.bodyLarge?.color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CloudHubScreen extends StatelessWidget {
  const CloudHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Remote Access')),
      body: const CloudHubTab(),
    );
  }
}
