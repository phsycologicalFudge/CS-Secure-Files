import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme_controller.dart';
import 'how_it_works_screen.dart';

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = 'Version ${info.version} (${info.buildNumber})';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final darkMode = ref.watch(themeModeProvider) == ThemeMode.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        title: Text(
          'Settings',
          style: text.titleLarge?.copyWith(color: text.bodyLarge?.color),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: Icon(Icons.brightness_6_outlined,
                color: theme.colorScheme.primary),
            title: Text('Dark Mode', style: text.bodyLarge),
            trailing: Switch(
              value: darkMode,
              onChanged: (val) {
                ref.read(themeModeProvider.notifier).state =
                val ? ThemeMode.dark : ThemeMode.light;
              },
              activeColor: theme.colorScheme.primary,
            ),
          ),
          Divider(color: theme.dividerColor),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Privacy & Transparency',
              style: text.labelLarge?.copyWith(color: text.bodySmall?.color),
            ),
          ),
          ListTile(
            leading: Icon(Icons.lock_outline, color: theme.colorScheme.primary),
            title: Text('Your data stays offline', style: text.bodyLarge),
            subtitle: Text(
              'Everything is local. No analytics, no tracking.',
              style: text.bodySmall,
            ),
          ),
          ListTile(
            leading:
            Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
            title: Text('No ads or trackers', style: text.bodyLarge),
            subtitle: Text('We don’t collect data or show ads.',
                style: text.bodySmall),
          ),
          Divider(color: theme.dividerColor),
          ListTile(
            leading: Icon(Icons.info_outline, color: theme.colorScheme.primary),
            title: Text('How the app works', style: text.bodyLarge),
            trailing: Icon(Icons.chevron_right, color: theme.iconTheme.color),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const HowItWorksScreen()),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                const SizedBox(height: 12),
                if (_version.isNotEmpty)
                  Text(
                    _version,
                    style: text.bodySmall?.copyWith(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
