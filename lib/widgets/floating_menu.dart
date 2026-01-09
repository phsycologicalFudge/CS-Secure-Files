import 'package:flutter/material.dart';

class FloatingMenu extends StatefulWidget {
  final VoidCallback onNewFolder;
  final VoidCallback onNewFile;

  const FloatingMenu({
    super.key,
    required this.onNewFolder,
    required this.onNewFile,
  });

  @override
  State<FloatingMenu> createState() => _FloatingMenuState();
}

class _FloatingMenuState extends State<FloatingMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
  }

  void _toggle() {
    setState(() {
      _open = !_open;
      _open ? _controller.forward() : _controller.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: 80,
          height: 200,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              Positioned(
                bottom: 130,
                right: 10,
                child: FadeTransition(
                  opacity: fade,
                  child: ScaleTransition(
                    scale: fade,
                    child: IgnorePointer(
                      ignoring: !_open,
                      child: FloatingActionButton(
                        heroTag: 'folder',
                        mini: true,
                        shape: const CircleBorder(),
                        backgroundColor: Colors.blue.shade100,
                        onPressed: () {
                          _toggle();
                          widget.onNewFolder();
                        },
                        child: const Icon(Icons.create_new_folder, color: Colors.black87),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 70,
                right: 10,
                child: FadeTransition(
                  opacity: fade,
                  child: ScaleTransition(
                    scale: fade,
                    child: IgnorePointer(
                      ignoring: !_open,
                      child: FloatingActionButton(
                        heroTag: 'file',
                        mini: true,
                        shape: const CircleBorder(),
                        backgroundColor: Colors.blue.shade100,
                        onPressed: () {
                          _toggle();
                          widget.onNewFile();
                        },
                        child: const Icon(Icons.description_outlined, color: Colors.black87),
                      ),
                    ),
                  ),
                ),
              ),
              FloatingActionButton(
                shape: const CircleBorder(),
                backgroundColor: Colors.blue.shade100,
                onPressed: _toggle,
                child: AnimatedRotation(
                  turns: _open ? 0.125 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: const Icon(Icons.add, color: Colors.black87, size: 28),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
