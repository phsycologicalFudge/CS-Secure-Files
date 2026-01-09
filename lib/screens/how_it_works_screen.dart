import 'package:flutter/material.dart';

class HowItWorksScreen extends StatelessWidget {
  const HowItWorksScreen({super.key});

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
          'How ColourSwift Secure Files Works',
          style: text.titleLarge?.copyWith(color: text.bodyLarge?.color),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            Text(
              'Why this page exists',
              style: text.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'ColourSwift Secure Files is a closed-source app, meaning the inner workings '
                  'are not publicly visible. This page exists to help you understand how your data '
                  'is handled without revealing sensitive design details that protect my product '
                  'from being copied or compromised.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 30),

            Text(
              'The limits',
              style: text.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "I'm just an average dev with a very specific skill set. "
                  "The app’s performance and abilities are entirely limited by what I can build right now. "
                  "But I plan to keep improving the engine, UX, and overall stability as I learn more. "
                  "So yeah, forgive the several hundred bugs you might run into 🐛",
              style: text.bodyMedium,
            ),
            const SizedBox(height: 30),

            Text(
              'How the app works',
              style: text.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'ColourSwift Secure Files is first and foremost a private file manager. '
                  'All file operations happen directly on your device. Nothing is uploaded to external servers, sold, or shared in any way. '
                  'The app manages files locally, offering organization, cleaning, '
                  'and security tools designed around your privacy.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 30),

            Text(
              'The antivirus',
              style: text.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Your device is protected by a lite version of the ColourSwift AV+, my personal solution to a good antivirus without ads. '
                  'The APK-scanner is built on industry-standard detection methods. It analyses files, quarantines and restores any false detections. '
                  'It works entirely offline so it is not as powerful as could be, but hey, that\'s what makes it private no?',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 30),

            Text(
              'Privacy first',
              style: text.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Every scan, cleanup, or file action happens locally on your phone. '
                  'There are no analytics, telemetry, or tracking of any kind.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 50),

            Text(
              'Thank you',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(
                color: text.bodySmall?.color?.withOpacity(0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
