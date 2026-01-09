import 'package:flutter/material.dart';

class ProcessingAnimation extends StatefulWidget {
  final String title;
  final double? progress; // null for indeterminate
  const ProcessingAnimation({super.key, required this.title, this.progress});

  @override
  State<ProcessingAnimation> createState() => _ProcessingAnimationState();
}

class _ProcessingAnimationState extends State<ProcessingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              RotationTransition(
                turns: _ctrl,
                child: Icon(Icons.sync, size: 56, color: colors.primary),
              ),
              SizedBox(
                width: 72,
                height: 72,
                child: CircularProgressIndicator(
                  value: widget.progress,
                  color: colors.primary,
                  strokeWidth: 4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(widget.title,
              style: textTheme.bodyMedium?.copyWith(color: colors.onBackground)),
        ],
      ),
    );
  }
}
