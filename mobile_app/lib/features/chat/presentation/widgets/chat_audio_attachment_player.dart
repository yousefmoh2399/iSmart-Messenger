import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/providers/providers.dart';
import '../../models/chat_models.dart';

/// Global coordinator to ensure only one voice note plays at a time (like WhatsApp)
/// and to coordinate persistent voice note playback speed across all audio players.
class ChatAudioPlaybackCoordinator {
  static const String _voiceSpeedPrefKey = 'preferred_voice_speed';

  static final ValueNotifier<String?> activePlayerNotifier =
      ValueNotifier<String?>(null);

  static final ValueNotifier<double> playbackSpeedNotifier =
      ValueNotifier<double>(1.0);

  static bool _isSpeedInitialized = false;

  static void setActive(String messageId) {
    activePlayerNotifier.value = messageId;
  }

  static void stopIfActive(String messageId) {
    if (activePlayerNotifier.value == messageId) {
      activePlayerNotifier.value = null;
    }
  }

  /// Initialize preferred voice playback speed from persistent storage.
  static Future<void> ensureSpeedInitialized() async {
    if (_isSpeedInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_voiceSpeedPrefKey);
      if (saved != null && (saved == 1.0 || saved == 1.5 || saved == 2.0)) {
        playbackSpeedNotifier.value = saved;
      }
    } catch (_) {}
    _isSpeedInitialized = true;
  }

  /// Update preferred voice playback speed and persist to SharedPreferences.
  static Future<void> setPlaybackSpeed(double speed) async {
    playbackSpeedNotifier.value = speed;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_voiceSpeedPrefKey, speed);
    } catch (_) {}
  }
}

/// WhatsApp-style voice note audio player.
///
/// Features:
/// - Distinctive WhatsApp voice bubble layout (Play button, custom waveform with scrubber thumb, duration & speed pill, and mic status badge).
/// - Instant duration preview from metadata so the duration is visible before streaming starts.
/// - Interactive touch scrubbing: drag or tap along the waveform to seek.
/// - Speed toggle pill (1x, 1.5x, 2x).
/// - Auto-rewind on playback completion.
class ChatAudioAttachmentPlayer extends ConsumerStatefulWidget {
  const ChatAudioAttachmentPlayer({
    super.key,
    required this.message,
    this.isMine = false,
  });

  final ChatMessage message;
  final bool isMine;

  @override
  ConsumerState<ChatAudioAttachmentPlayer> createState() =>
      _ChatAudioAttachmentPlayerState();
}

class _ChatAudioAttachmentPlayerState
    extends ConsumerState<ChatAudioAttachmentPlayer> {
  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration?>? _durationSub;
  String? _loadedFilePath;
  bool _isLoaded = false;
  bool _loading = false;
  bool _audioPluginUnavailable = false;
  double _playbackSpeed = 1.0;

  bool _isScrubbing = false;
  double _scrubPercent = 0.0;
  Duration? _pendingSeekDuration;
  Duration? _knownTotalDuration;
  bool _hasBeenPlayed = false;

  late final List<double> _waveformAmplitudes;

  @override
  void initState() {
    super.initState();
    _playbackSpeed = ChatAudioPlaybackCoordinator.playbackSpeedNotifier.value;
    _player = AudioPlayer(useProxyForRequestHeaders: false);
    _waveformAmplitudes = _generateVoiceAmplitudes(widget.message.id);

    // Apply currently active playback speed
    _player.setSpeed(_playbackSpeed).catchError((_) {});

    // Seed duration from message metadata if available so it displays instantly
    final metaMs = (widget.message.metadata?['durationMs'] as num?)?.toInt();
    if (metaMs != null && metaMs > 0) {
      _knownTotalDuration = Duration(milliseconds: metaMs);
    }

    ChatAudioPlaybackCoordinator.activePlayerNotifier
        .addListener(_onActivePlayerChanged);
    ChatAudioPlaybackCoordinator.playbackSpeedNotifier
        .addListener(_onPlaybackSpeedChanged);

    // Ensure preferred speed is loaded from persistent storage
    ChatAudioPlaybackCoordinator.ensureSpeedInitialized().then((_) {
      if (mounted) {
        final currentGlobal =
            ChatAudioPlaybackCoordinator.playbackSpeedNotifier.value;
        if (_playbackSpeed != currentGlobal) {
          setState(() {
            _playbackSpeed = currentGlobal;
          });
          _player.setSpeed(currentGlobal).catchError((_) {});
        }
      }
    });

    _playerStateSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.playing) {
        ChatAudioPlaybackCoordinator.setActive(widget.message.id);
        if (!_hasBeenPlayed) {
          setState(() => _hasBeenPlayed = true);
        }
      }
      if (state.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
        if (mounted) {
          setState(() {
            _pendingSeekDuration = null;
          });
        }
        ChatAudioPlaybackCoordinator.stopIfActive(widget.message.id);
      }
    });

    _durationSub = _player.durationStream.listen((duration) {
      if (duration != null && duration > Duration.zero && mounted) {
        setState(() {
          _knownTotalDuration = duration;
        });
      }
    });

    // Check if audio file is already cached in local phone storage, or pre-cache
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkAndPreloadAudio();
      }
    });
  }

  void _onActivePlayerChanged() {
    if (ChatAudioPlaybackCoordinator.activePlayerNotifier.value !=
        widget.message.id) {
      if (_player.playing) {
        _player.pause();
      }
    }
  }

  void _onPlaybackSpeedChanged() {
    final newSpeed = ChatAudioPlaybackCoordinator.playbackSpeedNotifier.value;
    if (_playbackSpeed != newSpeed) {
      if (mounted) {
        setState(() {
          _playbackSpeed = newSpeed;
        });
      } else {
        _playbackSpeed = newSpeed;
      }
      _player.setSpeed(newSpeed).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _durationSub?.cancel();
    ChatAudioPlaybackCoordinator.activePlayerNotifier
        .removeListener(_onActivePlayerChanged);
    ChatAudioPlaybackCoordinator.playbackSpeedNotifier
        .removeListener(_onPlaybackSpeedChanged);
    ChatAudioPlaybackCoordinator.stopIfActive(widget.message.id);
    _player.dispose().catchError((_) {});
    super.dispose();
  }

  Future<void> _checkAndPreloadAudio() async {
    if (_audioPluginUnavailable || _isLoaded || _loading) return;
    try {
      final repository = ref.read(chatRepositoryProvider);
      final cachedPath =
          await repository.getCachedAttachmentPath(widget.message);
      if (cachedPath != null && await File(cachedPath).exists()) {
        _loadedFilePath = cachedPath;
        if (_knownTotalDuration == null) {
          await _loadFromLocalFile(cachedPath);
        }
      } else {
        // Pre-cache voice note file into internal storage in background
        final fileUrl = widget.message.fileUrl;
        if (fileUrl != null && fileUrl.isNotEmpty) {
          final path = await repository
              .downloadAttachment(widget.message)
              .timeout(const Duration(seconds: 25));
          if (mounted && path.isNotEmpty && await File(path).exists()) {
            _loadedFilePath = path;
            if (_knownTotalDuration == null) {
              await _loadFromLocalFile(path);
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadFromLocalFile(String path) async {
    try {
      final dur = await _player.setFilePath(path);
      await _player.setSpeed(_playbackSpeed);
      _loadedFilePath = path;
      _isLoaded = true;
      if (dur != null && dur > Duration.zero && mounted) {
        setState(() {
          _knownTotalDuration = dur;
        });
      }
    } on MissingPluginException {
      _audioPluginUnavailable = true;
      _isLoaded = false;
    } catch (_) {
      _isLoaded = false;
      _loadedFilePath = null;
    }
  }

  Future<void> _handlePlayPause() async {
    if (_audioPluginUnavailable) return;
    HapticFeedback.selectionClick();

    if (_player.playing) {
      await _player.pause();
      return;
    }

    // 1. If already loaded into player, play immediately!
    if (_isLoaded &&
        _loadedFilePath != null &&
        File(_loadedFilePath!).existsSync()) {
      ChatAudioPlaybackCoordinator.setActive(widget.message.id);
      if (_pendingSeekDuration != null) {
        final seekTarget = _pendingSeekDuration!;
        _pendingSeekDuration = null;
        await _player.seek(seekTarget);
      }
      await _player.play();
      return;
    }

    // 2. Not yet loaded: load from internal storage or download
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final repository = ref.read(chatRepositoryProvider);
      String? localPath = _loadedFilePath;
      if (localPath == null || !File(localPath).existsSync()) {
        localPath = await repository.getCachedAttachmentPath(widget.message);
      }

      if (localPath == null || !File(localPath).existsSync()) {
        localPath = await repository
            .downloadAttachment(widget.message)
            .timeout(const Duration(seconds: 25));
      }

      if (!mounted) return;

      if (localPath.isNotEmpty && await File(localPath).exists()) {
        final dur = await _player
            .setFilePath(localPath)
            .timeout(const Duration(seconds: 15));
        await _player.setSpeed(_playbackSpeed);
        _loadedFilePath = localPath;
        _isLoaded = true;
        if (dur != null && dur > Duration.zero && mounted) {
          _knownTotalDuration = dur;
        }
        if (mounted) {
          ChatAudioPlaybackCoordinator.setActive(widget.message.id);
          if (_pendingSeekDuration != null) {
            final seekTarget = _pendingSeekDuration!;
            _pendingSeekDuration = null;
            await _player.seek(seekTarget);
          }
          await _player.play();
        }
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() => _audioPluginUnavailable = true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر تحميل أو تشغيل التسجيل الصوتي حاليًا'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString();
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _cyclePlaybackSpeed() {
    HapticFeedback.selectionClick();
    final current = ChatAudioPlaybackCoordinator.playbackSpeedNotifier.value;
    double nextSpeed = 1.0;
    if (current == 1.0) {
      nextSpeed = 1.5;
    } else if (current == 1.5) {
      nextSpeed = 2.0;
    } else {
      nextSpeed = 1.0;
    }
    ChatAudioPlaybackCoordinator.setPlaybackSpeed(nextSpeed);
  }

  void _onWaveformTap(TapDownDetails details, double width, Duration total) {
    if (width <= 0 || total.inMilliseconds <= 0) return;
    final percent = (details.localPosition.dx / width).clamp(0.0, 1.0);
    final targetDuration =
        Duration(milliseconds: (percent * total.inMilliseconds).round());
    if (_isLoaded) {
      _player.seek(targetDuration);
    } else {
      setState(() {
        _pendingSeekDuration = targetDuration;
      });
    }
    HapticFeedback.selectionClick();
  }

  void _onWaveformDragStart(DragStartDetails details, double width) {
    if (width <= 0) return;
    setState(() {
      _isScrubbing = true;
      _scrubPercent = (details.localPosition.dx / width).clamp(0.0, 1.0);
    });
    HapticFeedback.lightImpact();
  }

  void _onWaveformDragUpdate(DragUpdateDetails details, double width) {
    if (width <= 0) return;
    setState(() {
      _scrubPercent = (details.localPosition.dx / width).clamp(0.0, 1.0);
    });
  }

  void _onWaveformDragEnd(DragEndDetails details, Duration total) {
    if (total.inMilliseconds > 0) {
      final targetDuration =
          Duration(milliseconds: (_scrubPercent * total.inMilliseconds).round());
      if (_isLoaded) {
        _player.seek(targetDuration);
      } else {
        _pendingSeekDuration = targetDuration;
      }
    }
    setState(() {
      _isScrubbing = false;
    });
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_audioPluginUnavailable) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'تشغيل الصوت غير متاح حاليًا على هذا الجهاز.',
          style: TextStyle(fontSize: 12),
        ),
      );
    }

// Audio preloading and caching handled locally via internal storage

    // Determine colors tailored to outgoing vs incoming bubbles
    final isMine = widget.isMine;
    final Color playedWaveColor;
    final Color unplayedWaveColor;
    final Color thumbColor;
    final Color actionIconColor;
    final Color actionBgColor;
    final Color durationTextColor;

    if (isMine) {
      // Outgoing bubble styling
      playedWaveColor = const Color(0xFF00A884);
      unplayedWaveColor = isDark
          ? Colors.white.withValues(alpha: 0.28)
          : const Color(0xFF94A3B8);
      thumbColor = const Color(0xFF00A884);
      actionIconColor = Colors.white;
      actionBgColor = const Color(0xFF00A884);
      durationTextColor = isDark
          ? Colors.white70
          : const Color(0xFF475569);
    } else {
      // Incoming bubble styling
      playedWaveColor = const Color(0xFF00A884);
      unplayedWaveColor = isDark
          ? Colors.white.withValues(alpha: 0.24)
          : const Color(0xFFCBD5E1);
      thumbColor = const Color(0xFF00A884);
      actionIconColor = Colors.white;
      actionBgColor = const Color(0xFF00A884);
      durationTextColor = isDark
          ? Colors.white70
          : const Color(0xFF64748B);
    }

    return SizedBox(
      width: 272,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: StreamBuilder<PlayerState>(
          stream: _player.playerStateStream,
          builder: (context, playerSnapshot) {
            final playerState = playerSnapshot.data;
            final isPlaying = playerState?.playing == true;
            final isBuffering = playerState?.processingState == ProcessingState.buffering ||
                _loading;

            return StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, posSnapshot) {
                final rawPos = posSnapshot.data ?? Duration.zero;
                final position = (rawPos == Duration.zero && _pendingSeekDuration != null)
                    ? _pendingSeekDuration!
                    : rawPos;
                final total = _knownTotalDuration ?? Duration.zero;
                final safeMaxMs = total.inMilliseconds <= 0
                    ? 1.0
                    : total.inMilliseconds.toDouble();

                final currentProgress = (position.inMilliseconds / safeMaxMs).clamp(0.0, 1.0);
                final effectiveProgress = _isScrubbing ? _scrubPercent : currentProgress;

                // Display duration: while playing/scrubbing show current elapsed, otherwise show total duration
                final displayDuration = _isScrubbing
                    ? Duration(milliseconds: (_scrubPercent * safeMaxMs).round())
                    : (isPlaying || position > Duration.zero
                        ? position
                        : total);

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 1. Play / Pause circular button
                    _buildPlayButton(
                      isPlaying: isPlaying,
                      isBuffering: isBuffering,
                      actionBgColor: actionBgColor,
                      actionIconColor: actionIconColor,
                    ),
                    const SizedBox(width: 8),

                    // 2. Center: Waveform + Duration / Speed
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Waveform with Draggable Thumb (using Builder instead of LayoutBuilder to support IntrinsicWidth)
                          Builder(
                            builder: (waveContext) {
                              double resolveWaveWidth() {
                                final box = waveContext.findRenderObject();
                                if (box is RenderBox && box.hasSize) {
                                  return box.size.width;
                                }
                                return 160.0;
                              }

                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapDown: (d) =>
                                    _onWaveformTap(d, resolveWaveWidth(), total),
                                onHorizontalDragStart: (d) =>
                                    _onWaveformDragStart(d, resolveWaveWidth()),
                                onHorizontalDragUpdate: (d) =>
                                    _onWaveformDragUpdate(d, resolveWaveWidth()),
                                onHorizontalDragEnd: (d) =>
                                    _onWaveformDragEnd(d, total),
                                child: Container(
                                  height: 32,
                                  width: double.infinity,
                                  color: Colors.transparent,
                                  child: CustomPaint(
                                    painter: _WhatsAppWaveformPainter(
                                      amplitudes: _waveformAmplitudes,
                                      progress: effectiveProgress,
                                      playedColor: playedWaveColor,
                                      unplayedColor: unplayedWaveColor,
                                      thumbColor: thumbColor,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 2),
                          // Duration & Speed Indicator
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(displayDuration),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: durationTextColor,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              _buildSpeedPill(isDark: isDark),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),

                    // 3. WhatsApp Mic Status Badge (Unplayed: Green, Played: Blue)
                    _buildMicStatusBadge(
                      isPlayed: _hasBeenPlayed ||
                          position > Duration.zero ||
                          widget.message.seenBy.isNotEmpty,
                      isDark: isDark,
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlayButton({
    required bool isPlaying,
    required bool isBuffering,
    required Color actionBgColor,
    required Color actionIconColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handlePlayPause,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: actionBgColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: actionBgColor.withValues(alpha: 0.32),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: isBuffering
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: actionIconColor,
                    ),
                  )
                : Icon(
                    isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: isPlaying ? 24 : 28,
                    color: actionIconColor,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedPill({required bool isDark}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _cyclePlaybackSpeed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${_playbackSpeed == 1.0 ? '1' : _playbackSpeed == 1.5 ? '1.5' : '2'}×',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMicStatusBadge({
    required bool isPlayed,
    required bool isDark,
  }) {
    // WhatsApp mic badge colors:
    // Green (0xFF00A884) if unplayed, Cyan Blue (0xFF34B7F1) if played/heard
    final micColor = isPlayed
        ? const Color(0xFF34B7F1)
        : const Color(0xFF00A884);

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: micColor.withValues(alpha: isDark ? 0.22 : 0.14),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          Icons.mic_rounded,
          size: 18,
          color: micColor,
        ),
      ),
    );
  }
}

/// Generates a realistic set of 34 voice waveform amplitudes deterministically from a seed.
List<double> _generateVoiceAmplitudes(String seedStr) {
  final seed = seedStr.hashCode;
  final random = math.Random(seed);
  const count = 34;
  return List.generate(count, (index) {
    // Mimic speech cadence: slightly softer towards edges, expressive in the middle
    final normalizedPos = (index / (count - 1)) * math.pi;
    final envelope = math.sin(normalizedPos).clamp(0.25, 1.0);
    final variance = 0.25 + random.nextDouble() * 0.75;
    return (envelope * variance).clamp(0.2, 1.0);
  });
}

/// WhatsApp-style waveform painter with rounded bar ends and scrub thumb.
class _WhatsAppWaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final Color thumbColor;

  _WhatsAppWaveformPainter({
    required this.amplitudes,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    required this.thumbColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty || size.width <= 0) return;

    final barWidth = 2.6;
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

    final thumbX = (progress * size.width).clamp(0.0, size.width);

    for (var i = 0; i < displayAmplitudes.length; i++) {
      final x = i * (barWidth + spacing) + (barWidth / 2);
      final height = displayAmplitudes[i] * size.height;
      final startY = (size.height - height) / 2;
      final endY = startY + height;

      final isPlayed = x <= thumbX;
      canvas.drawLine(
        Offset(x, startY),
        Offset(x, endY),
        isPlayed ? playedPaint : unplayedPaint,
      );
    }

    // Draggable Scrubber Thumb Circle (WhatsApp style dot)
    final thumbPaint = Paint()
      ..color = thumbColor
      ..style = PaintingStyle.fill;

    final thumbBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final thumbCenter = Offset(thumbX, size.height / 2);
    canvas.drawCircle(thumbCenter, 5.0, thumbPaint);
    canvas.drawCircle(thumbCenter, 5.0, thumbBorderPaint);
  }

  @override
  bool shouldRepaint(covariant _WhatsAppWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.amplitudes != amplitudes ||
        oldDelegate.playedColor != playedColor ||
        oldDelegate.unplayedColor != unplayedColor ||
        oldDelegate.thumbColor != thumbColor;
  }
}
