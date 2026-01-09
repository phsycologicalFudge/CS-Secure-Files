import 'package:flutter/material.dart';

import 'ftp_screen.dart';
import 'viewer/local_http_screen.dart';

class CloudHubTab extends StatelessWidget {
  const CloudHubTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.computer, size: 90, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              'Remote Access',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Select a connection method',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 180,
              child: ElevatedButton(
                onPressed: () async {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: theme.dialogBackgroundColor,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    builder: (_) {
                      return SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: Icon(Icons.folder_shared, color: theme.colorScheme.primary),
                              title: Text('FTP Server', style: theme.textTheme.bodyMedium),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  PageRouteBuilder(
                                    pageBuilder: (_, __, ___) => const FTPScreen(),
                                  ),
                                );
                              },
                            ),
                            ListTile(
                              leading: Icon(Icons.cloud, color: theme.colorScheme.primary),
                              title: Text('Local HTTP Server', style: theme.textTheme.bodyMedium),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  PageRouteBuilder(
                                    pageBuilder: (_, __, ___) => const LocalHttpScreen(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Select Method'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
