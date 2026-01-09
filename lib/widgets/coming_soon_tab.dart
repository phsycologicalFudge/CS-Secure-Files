import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ComingSoonTab extends StatelessWidget {
  final String title;
  final String message;
  final String? linkText;
  final String? linkUrl;

  const ComingSoonTab({
    super.key,
    required this.title,
    required this.message,
    this.linkText,
    this.linkUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        color: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 22, color: Colors.white)),
              const SizedBox(height: 12),
              Text(
                message,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              if (linkUrl != null) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(linkUrl!)),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0099FF),
                  ),
                  child: Text(linkText ?? 'Open link'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
