import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:just_audio/just_audio.dart';

import '../../../../core/network/media_url_resolver.dart';
import '../../../../shared/providers/providers.dart';
import '../../models/chat_models.dart';

class ChatAudioAttachmentPlayer extends ConsumerStatefulWidget {
  const ChatAudioAttachmentPlayer({super.key, required this.message});

  final ChatMessage message;

  @override
  ConsumerState<ChatAudioAttachmentPlayer> createState() =>
      _ChatAudioAttachmentPlayerState();
}

class _ChatAudioAttachmentPlayerState
    extends ConsumerState<ChatAudioAttachmentPlayer> {
  late final AudioPlayer _player;
  String? _loadedUrl;
  String? _loadedToken;
  bool _loading = false;
  bool _audioPluginUnavailable = false;
  double _playbackSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer(useProxyForRequestHeaders: false);
  }

  @override
  void dispose() {
    _player.dispose().catchError((_) {});
    super.dispose();
  }

  Future<void> _ensureLoaded(String token) async {
    final url = resolveMediaUrl(widget.message.fileUrl) ?? '';
    if (url.isEmpty) {
      return;
    }
    if (_audioPluginUnavailable) {
      return;
    }
    if (_loadedUrl == url && _loadedToken == token) {
      return;
    }
    if (_loading) {
      return;
    }
    _loading = true;
    try {
      await _player.setUrl(url, headers: {'Authorization': 'Bearer $token'});
      _loadedUrl = url;
      _loadedToken = token;
    } on MissingPluginException {
      _audioPluginUnavailable = true;
      _loadedUrl = null;
      _loadedToken = null;
    } catch (_) {
      _loadedUrl = null;
      _loadedToken = null;
    } finally {
      _loading = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final token = ref.watch(authTokenProvider).valueOrNull;
    if (_audioPluginUnavailable) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          'تشغيل الصوت غير متاح حاليًا على هذا الإصدار من التطبيق.',
        ),
      );
    }
    if (token != null && token.isNotEmpty) {
      _ensureLoaded(token);
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (context, snapshot) {
              final state = snapshot.data;
              final isPlaying = state?.playing == true;
              return IconButton(
                onPressed: token == null || token.isEmpty
                    ? null
                    : () async {
                        try {
                          if (isPlaying) {
                            await _player.pause();
                          } else {
                            await _player.play();
                          }
                        } on MissingPluginException {
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _audioPluginUnavailable = true;
                          });
                        }
                      },
                icon: Icon(
                  isPlaying
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  size: 30,
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.message.fileName ?? 'ملاحظة صوتية',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                StreamBuilder<Duration>(
                  stream: _player.positionStream,
                  builder: (context, positionSnapshot) {
                    final position = positionSnapshot.data ?? Duration.zero;
                    return StreamBuilder<Duration?>(
                      stream: _player.durationStream,
                      builder: (context, durationSnapshot) {
                        final total = durationSnapshot.data ?? Duration.zero;
                        final safeMaxMs = total.inMilliseconds <= 0
                            ? 1.0
                            : total.inMilliseconds.toDouble();
                        final value = position.inMilliseconds
                            .clamp(0, safeMaxMs.toInt())
                            .toDouble();
                          final progressPercent = safeMaxMs > 0 ? value / safeMaxMs : 0.0;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTapDown: (details) {
                                  if (total.inMilliseconds <= 0) return;
                                  final renderBox = context.findRenderObject() as RenderBox;
                                  final tapPercent = details.localPosition.dx / renderBox.size.width;
                                  _player.seek(Duration(milliseconds: (tapPercent * safeMaxMs).round()));
                                },
                                child: Container(
                                  height: 35,
                                  width: double.infinity,
                                  color: Colors.transparent,
                                  child: CustomPaint(
                                    painter: _VoiceWaveformPainter(
                                      amplitudes: _generateAmplitudes(widget.message.id),
                                      progress: progressPercent,
                                      playedColor: const Color(0xFF2A8CFF),
                                      unplayedColor: Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${_formatDuration(position)} / ${_formatDuration(total)}',
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        if (_playbackSpeed == 1.0) {
                                          _playbackSpeed = 1.5;
                                        } else if (_playbackSpeed == 1.5) {
                                          _playbackSpeed = 2.0;
                                        } else {
                                          _playbackSpeed = 1.0;
                                        }
                                        _player.setSpeed(_playbackSpeed);
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${_playbackSpeed}x',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<double> _generateAmplitudes(String seedStr) {
  final seed = seedStr.hashCode;
  final random = math.Random(seed);
  return List.generate(40, (index) => 0.2 + random.nextDouble() * 0.8);
}

class _VoiceWaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;

  _VoiceWaveformPainter({
    required this.amplitudes,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;

    final barWidth = 3.0;
    final spacing = 2.0;
    final totalBars = (size.width / (barWidth + spacing)).floor();
    
    final displayAmplitudes = <double>[];
    if (totalBars > 0) {
      for (var i = 0; i < totalBars; i++) {
        final index = (i * amplitudes.length / totalBars).floor();
        displayAmplitudes.add(amplitudes[index]);
      }
    }

    final playedPaint = Paint()
      ..color = playedColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    final unplayedPaint = Paint()
      ..color = unplayedColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    for (var i = 0; i < displayAmplitudes.length; i++) {
      final x = i * (barWidth + spacing) + (barWidth / 2);
      final height = displayAmplitudes[i] * size.height;
      final startY = (size.height - height) / 2;
      final endY = startY + height;

      final isPlayed = (i / displayAmplitudes.length) <= progress;
      canvas.drawLine(
        Offset(x, startY),
        Offset(x, endY),
        isPlayed ? playedPaint : unplayedPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
           oldDelegate.amplitudes != amplitudes ||
           oldDelegate.playedColor != playedColor ||
           oldDelegate.unplayedColor != unplayedColor;
  }
}

