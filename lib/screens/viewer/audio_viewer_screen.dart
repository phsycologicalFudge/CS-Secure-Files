import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

class AudioViewerScreen extends StatefulWidget {
  final String path;
  const AudioViewerScreen({super.key, required this.path});

  @override
  State<AudioViewerScreen> createState() => _AudioViewerScreenState();
}

class _AudioViewerScreenState extends State<AudioViewerScreen> {
  late AudioPlayer _player;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      await _player.setFilePath(widget.path);
      _duration = _player.duration ?? Duration.zero;
      _loading = false;

      _player.positionStream.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });

      _player.playerStateStream.listen((state) {
        if (mounted) setState(() {
          _isPlaying = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _isPlaying = false;
            _player.seek(Duration.zero);
          }
        });
      });

      setState(() {});
    } catch (e) {
      debugPrint('Audio init failed: $e');
    }
  }

  String _format(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${two(m)}:${two(s)}';
  }

  void _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  void _seek(bool forward) {
    var newPos = _position + Duration(seconds: forward ? 10 : -10);
    if (newPos < Duration.zero) newPos = Duration.zero;
    if (newPos > _duration) newPos = _duration;
    _player.seek(newPos);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final filename = p.basename(widget.path);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black, Color(0xFF1A1A1A)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          filename,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),

                  if (_loading)
                    const CircularProgressIndicator(color: Colors.white)
                  else
                    Column(
                      children: [
                        Icon(Icons.music_note_rounded,
                            color: colors.primary, size: 120),
                        const SizedBox(height: 20),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: colors.primary,
                            thumbColor: colors.primary,
                            inactiveTrackColor: Colors.white24,
                          ),
                          child: Slider(
                            value: _position.inMilliseconds.toDouble(),
                            min: 0,
                            max: _duration.inMilliseconds.toDouble(),
                            onChanged: (v) =>
                                _player.seek(Duration(milliseconds: v.toInt())),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_format(_position),
                                style: const TextStyle(color: Colors.white70)),
                            Text(_format(_duration),
                                style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                        const SizedBox(height: 25),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.replay_10,
                                  color: Colors.white, size: 36),
                              onPressed: () => _seek(false),
                            ),
                            const SizedBox(width: 20),
                            GestureDetector(
                              onTap: _togglePlay,
                              child: Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: colors.primary, width: 2),
                                ),
                                child: Icon(
                                  _isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: colors.primary,
                                  size: 40,
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            IconButton(
                              icon: const Icon(Icons.forward_10,
                                  color: Colors.white, size: 36),
                              onPressed: () => _seek(true),
                            ),
                          ],
                        ),
                      ],
                    ),

                  const Spacer(),
                  Text(
                    'Audio playback powered by ColourSwift Engine',
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                        fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
