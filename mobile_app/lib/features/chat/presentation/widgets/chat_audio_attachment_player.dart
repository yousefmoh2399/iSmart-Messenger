import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/network/media_url_resolver.dart';
import '../../../../shared/providers/providers.dart';
import '../../models/chat_models.dart';

/// WhatsApp-style voice note audio player.
///
/// Features:
/// - Distinctive WhatsApp voice bubble layout (Play button, custom waveform with scrubber thumb, duration & speed pill, sender avatar with mic status badge).
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
  String? _loadedUrl;
  String? _loadedToken;
  bool _loading = false;
  bool _audioPluginUnavailable = false;
  double _playbackSpeed = 1.0;

  bool _isScrubbing = false;
  double _scrubPercent = 0.0;
  Duration? _knownTotalDuration;
  bool _hasBeenPlayed = false;

  late final List<double> _waveformAmplitudes;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer(useProxyForRequestHeaders: false);
    _waveformAmplitudes = _generateVoiceAmplitudes(widget.message.id);

    // Seed duration from message metadata if available so it displays instantly
    final metaMs = (widget.message.metadata?['durationMs'] as num?)?.toInt();
    if (metaMs != null && metaMs > 0) {
      _knownTotalDuration = Duration(milliseconds: metaMs);
    }

    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.playing) {
        if (!_hasBeenPlayed) {
          setState(() => _hasBeenPlayed = true);
        }
      }
      if (state.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
      }
    });

    _player.durationStream.listen((duration) {
      if (duration != null && duration > Duration.zero && mounted) {
        setState(() {
          _knownTotalDuration = duration;
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose().catchError((_) {});
    super.dispose();
  }

  Future<void> _ensureLoaded(String token) async {
    final url = resolveMediaUrl(widget.message.fileUrl) ?? '';
    if (url.isEmpty || _audioPluginUnavailable) return;
    if (_loadedUrl == url && _loadedToken == token) return;
    if (_loading) return;

    _loading = true;
    try {
      final dur = await _player.setUrl(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );
      _loadedUrl = url;
      _loadedToken = token;
      if (dur != null && dur > Duration.zero && mounted) {
        setState(() {
          _knownTotalDuration = dur;
        });
      }
    } on MissingPluginException {
      _audioPluginUnavailable = true;
      _loadedUrl = null;
      _loadedToken = null;
    } catch (_) {
      _loadedUrl = null;
      _loadedToken = null;
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString();
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _cyclePlaybackSpeed() {
    HapticFeedback.selectionClick();
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
  }

  void _onWaveformTap(TapDownDetails details, double width, Duration total) {
    if (width <= 0 || total.inMilliseconds <= 0) return;
    final percent = (details.localPosition.dx / width).clamp(0.0, 1.0);
    final targetMs = (percent * total.inMilliseconds).round();
    _player.seek(Duration(milliseconds: targetMs));
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
      final targetMs = (_scrubPercent * total.inMilliseconds).round();
      _player.seek(Duration(milliseconds: targetMs));
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
    final token = ref.watch(authTokenProvider).valueOrNull;

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

    if (token != null && token.isNotEmpty) {
      _ensureLoaded(token);
    }

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

    return Container(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 330),
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
              final position = posSnapshot.data ?? Duration.zero;
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
                    token: token,
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
                        // Waveform with Draggable Thumb
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final waveWidth = constraints.maxWidth;
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (d) => _onWaveformTap(d, waveWidth, total),
                              onHorizontalDragStart: (d) =>
                                  _onWaveformDragStart(d, waveWidth),
                              onHorizontalDragUpdate: (d) =>
                                  _onWaveformDragUpdate(d, waveWidth),
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

                  // 3. Sender Avatar with Mic Status Badge
                  _buildAvatarWithMicBadge(
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
    );
  }

  Widget _buildPlayButton({
    required String? token,
    required bool isPlaying,
    required bool isBuffering,
    required Color actionBgColor,
    required Color actionIconColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: (token == null || token.isEmpty)
            ? null
            : () async {
                try {
                  HapticFeedback.selectionClick();
                  if (isPlaying) {
                    await _player.pause();
                  } else {
                    await _player.play();
                  }
                } on MissingPluginException {
                  if (mounted) {
                    setState(() => _audioPluginUnavailable = true);
                  }
                } catch (_) {}
              },
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

  Widget _buildAvatarWithMicBadge({
    required bool isPlayed,
    required bool isDark,
  }) {
    final sender = widget.message.sender;
    final currentAuthUser = ref.watch(authControllerProvider).valueOrNull;

    final avatarUrl = widget.isMine
        ? (currentAuthUser?.avatarUrl ?? sender?.avatarUrl)
        : sender?.avatarUrl;
    final displayName = widget.isMine
        ? (currentAuthUser?.fullName ?? 'أنا')
        : (sender?.displayName ?? 'مستخدم');

    final resolvedAvatar = resolveMediaUrl(avatarUrl);
    final initial = displayName.trim().isNotEmpty
        ? displayName.trim().characters.first.toUpperCase()
        : '؟';

    // WhatsApp mic badge colors:
    // Green (0xFF00A884) if unplayed, Cyan Blue (0xFF34B7F1) if played/heard
    final micBadgeColor = isPlayed
        ? const Color(0xFF34B7F1)
        : const Color(0xFF00A884);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Circular profile picture or initials avatar
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [const Color(0xFF334155), const Color(0xFF1E293B)]
                  : [const Color(0xFFCBD5E1), const Color(0xFF94A3B8)],
            ),
          ),
          child: ClipOval(
            child: resolvedAvatar != null && resolvedAvatar.isNotEmpty
                ? Image.network(
                    resolvedAvatar,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
          ),
        ),
        // WhatsApp Mic badge at bottom corner
        PositionedDirectional(
          bottom: -1,
          end: -1,
          child: Container(
            width: 17,
            height: 17,
            decoration: BoxDecoration(
              color: micBadgeColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? const Color(0xFF1F2937) : Colors.white,
                width: 1.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.mic_rounded,
                size: 10,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
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
