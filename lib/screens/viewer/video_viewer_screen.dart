import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class VideoViewerScreen extends StatefulWidget {
  final String path;
  const VideoViewerScreen({super.key, required this.path});

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  late VideoPlayerController _controller;
  bool _showControls = true;
  Timer? _hideTimer;
  static const _channel = MethodChannel('volume_brightness');
  double? _volume;
  double? _brightness;
  bool _fullscreen = false;
  Timer? _positionTimer;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path))
      ..initialize().then((_) {
        if (mounted) setState(() {});
        _controller.play();
        _startHideTimer();
        _startPositionTimer();
      });
    _initLevels();
  }

  Future<void> _initLevels() async {
    try {
      final v = await _channel.invokeMethod<double>('getVolume');
      final b = await _channel.invokeMethod<double>('getBrightness');
      setState(() {
        _volume = v ?? 0.5;
        _brightness = b ?? 0.5;
      });
    } catch (_) {}
  }

  void _setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    await _channel.invokeMethod('setVolume', {'level': _volume});
  }

  void _setBrightness(double v) async {
    _brightness = v.clamp(0.0, 1.0);
    await _channel.invokeMethod('setBrightness', {'level': _brightness});
  }

  void _toggleFullscreen() {
    _fullscreen = !_fullscreen;
    if (_fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    }
    setState(() {});
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _controller.value.isInitialized) setState(() {});
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  String _format(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Offset? _startDrag;
  bool _dragRight = false;

  void _onVerticalDragStart(DragStartDetails d) {
    final width = MediaQuery.of(context).size.width;
    _startDrag = d.globalPosition;
    _dragRight = d.globalPosition.dx > width / 2;
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    final delta = (_startDrag!.dy - d.globalPosition.dy) / 300;
    if (_dragRight) {
      _setVolume((_volume ?? 0.5) + delta);
    } else {
      _setBrightness((_brightness ?? 0.5) + delta);
    }
  }

  void _skip(bool forward) {
    final pos = _controller.value.position;
    final offset = Duration(seconds: forward ? 10 : -10);
    _controller.seekTo(pos + offset);
    _startHideTimer();
  }

  void _showSpeedDialog() async {
    final speeds = [0.5, 1.0, 1.25, 1.5, 2.0];
    final chosen = await showModalBottomSheet<double>(
      context: context,
      builder: (_) => Container(
        color: Colors.black87,
        child: ListView(
          shrinkWrap: true,
          children: speeds
              .map((s) => ListTile(
            title: Text('${s}x',
                style: const TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context, s),
          ))
              .toList(),
        ),
      ),
    );
    if (chosen != null) {
      _controller.setPlaybackSpeed(chosen);
      _startHideTimer();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _positionTimer?.cancel();
    _controller.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    super.dispose();
  }

  Widget _buildProgressBar() {
    final position = _controller.value.position;
    final duration = _controller.value.duration;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: SliderComponentShape.noOverlay,
            activeTrackColor: Colors.orangeAccent,
            inactiveTrackColor: Colors.white30,
          ),
          child: Slider(
            min: 0,
            max: duration.inMilliseconds.toDouble(),
            value: position.inMilliseconds
                .clamp(0, duration.inMilliseconds)
                .toDouble(),
            onChanged: (v) =>
                _controller.seekTo(Duration(milliseconds: v.toInt())),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_format(position),
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text(_format(duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onDoubleTapDown: (d) {
          final w = MediaQuery.of(context).size.width;
          _skip(d.globalPosition.dx > w / 2);
        },
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: _controller.value.isInitialized
                  ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
                  : const CircularProgressIndicator(color: Colors.white),
            ),
            if (_showControls) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.only(
                      top: 40, left: 16, right: 16, bottom: 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black54, Colors.transparent],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.white, size: 26),
                      ),
                      IconButton(
                        onPressed: _toggleFullscreen,
                        icon: Icon(
                            _fullscreen
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _controller.value.isPlaying
                        ? _controller.pause()
                        : _controller.play();
                  });
                  _startHideTimer();
                },
                onLongPress: _showSpeedDialog,
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black54,
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Icon(
                    _controller.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.black54],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: _buildProgressBar(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
