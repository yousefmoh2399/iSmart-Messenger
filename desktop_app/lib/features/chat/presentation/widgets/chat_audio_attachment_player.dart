import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/network/media_url_resolver.dart';
import '../../../../shared/services/web_platform_bridge.dart' as web_bridge;
import '../../models/chat_models.dart';

const Color _kAudioPrimary = Color(0xFF007AFF);

bool _justAudioNativePlaybackSupported() {
  if (kIsWeb) {
    return true;
  }
  return Platform.isWindows || Platform.isMacOS;
}

class GlobalDesktopVoiceSession {
  const GlobalDesktopVoiceSession({
    required this.message,
    required this.senderName,
    required this.url,
  });

  final ChatMessage message;
  final String senderName;
  final String url;
}

/// Singleton coordinator that keeps voice notes playing across conversations on Desktop
/// and powers `GlobalDesktopMiniAudioPlayerBar`.
class DesktopAudioPlaybackCoordinator {
  static final ValueNotifier<GlobalDesktopVoiceSession?> activeSessionNotifier =
      ValueNotifier<GlobalDesktopVoiceSession?>(null);
  static final ValueNotifier<bool> isPlayingNotifier =
      ValueNotifier<bool>(false);
  static final ValueNotifier<Duration> positionNotifier =
      ValueNotifier<Duration>(Duration.zero);
  static final ValueNotifier<Duration> durationNotifier =
      ValueNotifier<Duration>(Duration.zero);
  static final ValueNotifier<double> speedNotifier =
      ValueNotifier<double>(1.0);

  static AudioPlayer? _sharedPlayer;
  static String? _loadedMessageId;
  static String? _electronObjectUrl;
  static bool _unavailable = !_justAudioNativePlaybackSupported();

  static bool get isUnavailable => _unavailable;

  static AudioPlayer? _ensurePlayer() {
    if (_unavailable) return null;
    if (_sharedPlayer != null) return _sharedPlayer;
    try {
      final player = AudioPlayer();
      _sharedPlayer = player;
      player.playerStateStream.listen((state) {
        isPlayingNotifier.value = state.playing;
        if (state.processingState == ProcessingState.completed) {
          player.seek(Duration.zero);
          player.pause();
          positionNotifier.value = Duration.zero;
          isPlayingNotifier.value = false;
        }
      });
      player.positionStream.listen((pos) {
        positionNotifier.value = pos;
      });
      player.durationStream.listen((dur) {
        if (dur != null && dur > Duration.zero) {
          durationNotifier.value = dur;
        }
      });
      return player;
    } on MissingPluginException {
      _unavailable = true;
      return null;
    } catch (_) {
      _unavailable = true;
      return null;
    }
  }

  static String _fallbackMimeType(ChatMessage message) {
    final mime = message.mimeType?.trim().toLowerCase();
    if (mime != null && mime.startsWith('audio/')) {
      return mime;
    }
    final fileName = (message.fileName ?? message.fileUrl ?? '').toLowerCase();
    if (fileName.endsWith('.m4a') || fileName.endsWith('.mp4')) {
      return 'audio/mp4';
    }
    if (fileName.endsWith('.mp3')) {
      return 'audio/mpeg';
    }
    if (fileName.endsWith('.wav')) {
      return 'audio/wav';
    }
    if (fileName.endsWith('.ogg') || fileName.endsWith('.oga')) {
      return 'audio/ogg';
    }
    if (fileName.endsWith('.webm')) {
      return 'audio/webm';
    }
    return 'audio/mpeg';
  }

  static Future<void> toggleOrPlay({
    required ChatMessage message,
    required String token,
  }) async {
    final player = _ensurePlayer();
    if (player == null) return;
    final url = resolveMediaUrl(message.fileUrl) ?? '';
    if (url.isEmpty || token.isEmpty) return;

    if (_loadedMessageId == message.id &&
        activeSessionNotifier.value?.message.id == message.id) {
      if (player.playing) {
        await player.pause();
      } else {
        await player.play();
      }
      return;
    }

    try {
      activeSessionNotifier.value = GlobalDesktopVoiceSession(
        message: message,
        senderName: message.sender?.displayName ?? 'عضو',
        url: url,
      );
      positionNotifier.value = Duration.zero;
      durationNotifier.value = Duration.zero;

      final headers = {'Authorization': 'Bearer $token'};
      if (kIsWeb && web_bridge.isElectron()) {
        final objectUrl = await web_bridge.fetchElectronObjectUrl(
          url: url,
          headers: headers,
          fallbackMimeType: _fallbackMimeType(message),
        );
        if (_electronObjectUrl != null) {
          web_bridge.revokeObjectUrl(_electronObjectUrl!);
        }
        _electronObjectUrl = objectUrl;
        await player.setUrl(objectUrl);
      } else {
        await player.setUrl(url, headers: headers);
      }
      _loadedMessageId = message.id;
      await player.setSpeed(speedNotifier.value);
      await player.play();
    } catch (_) {}
  }

  static Future<void> toggleCurrent() async {
    final player = _sharedPlayer;
    if (player == null || activeSessionNotifier.value == null) return;
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  static Future<void> seek(Duration position) async {
    final player = _sharedPlayer;
    if (player == null) return;
    positionNotifier.value = position;
    try {
      await player.seek(position);
    } catch (_) {}
  }

  static Future<void> cycleSpeed() async {
    final current = speedNotifier.value;
    final double next;
    if (current == 1.0) {
      next = 1.5;
    } else if (current == 1.5) {
      next = 2.0;
    } else {
      next = 1.0;
    }
    speedNotifier.value = next;
    try {
      await _sharedPlayer?.setSpeed(next);
    } catch (_) {}
  }

  static Future<void> stopAndDismiss() async {
    activeSessionNotifier.value = null;
    _loadedMessageId = null;
    isPlayingNotifier.value = false;
    positionNotifier.value = Duration.zero;
    durationNotifier.value = Duration.zero;
    try {
      await _sharedPlayer?.stop();
    } catch (_) {}
  }
}

/// Sleek Telegram-style floating top bar for Desktop that keeps voice notes playing
/// even when switching conversations.
class GlobalDesktopMiniAudioPlayerBar extends StatelessWidget {
  const GlobalDesktopMiniAudioPlayerBar({
    super.key,
    this.onTapSession,
  });

  final ValueChanged<GlobalDesktopVoiceSession>? onTapSession;

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<GlobalDesktopVoiceSession?>(
      valueListenable: DesktopAudioPlaybackCoordinator.activeSessionNotifier,
      builder: (context, session, _) {
        if (session == null) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF0F9FF),
            border: Border(
              bottom: BorderSide(
                color: _kAudioPrimary.withValues(alpha: 0.22),
              ),
            ),
          ),
          child: Row(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable:
                    DesktopAudioPlaybackCoordinator.isPlayingNotifier,
                builder: (context, isPlaying, _) {
                  return IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: DesktopAudioPlaybackCoordinator.toggleCurrent,
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      color: _kAudioPrimary,
                      size: 26,
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: onTapSession != null
                          ? () => onTapSession!(session)
                          : null,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.graphic_eq_rounded,
                              size: 15,
                              color: _kAudioPrimary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'رسالة صوتية • ${session.senderName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            if (onTapSession != null) ...[
                              const SizedBox(width: 6),
                              const Text(
                                'الانتقال للرسالة ↗',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _kAudioPrimary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    ValueListenableBuilder<Duration>(
                      valueListenable:
                          DesktopAudioPlaybackCoordinator.positionNotifier,
                      builder: (context, pos, _) {
                        return ValueListenableBuilder<Duration>(
                          valueListenable:
                              DesktopAudioPlaybackCoordinator.durationNotifier,
                          builder: (context, total, _) {
                            final maxMs = total.inMilliseconds <= 0
                                ? 1.0
                                : total.inMilliseconds.toDouble();
                            final progress =
                                (pos.inMilliseconds / maxMs).clamp(0.0, 1.0);
                            return Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 4,
                                      backgroundColor: _kAudioPrimary
                                          .withValues(alpha: 0.16),
                                      valueColor: const AlwaysStoppedAnimation(
                                        _kAudioPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '${_formatDuration(pos)} / ${_formatDuration(total)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white70
                                        : const Color(0xFF64748B),
                                  ),
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
              const SizedBox(width: 10),
              ValueListenableBuilder<double>(
                valueListenable: DesktopAudioPlaybackCoordinator.speedNotifier,
                builder: (context, speed, _) {
                  return InkWell(
                    onTap: DesktopAudioPlaybackCoordinator.cycleSpeed,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _kAudioPrimary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${speed}x',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: _kAudioPrimary,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'إيقاف وإغلاق المشغل',
                onPressed: DesktopAudioPlaybackCoordinator.stopAndDismiss,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ChatAudioAttachmentPlayer extends StatelessWidget {
  const ChatAudioAttachmentPlayer({
    super.key,
    required this.message,
    required this.token,
  });

  final ChatMessage message;
  final String? token;

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (DesktopAudioPlaybackCoordinator.isUnavailable) {
      final onLinux = !kIsWeb && Platform.isLinux;
      return Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F9FC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDCE6F0)),
        ),
        child: Text(
          style: const TextStyle(color: Colors.black),
          onLinux
              ? 'تشغيل الملاحظات الصوتية غير مدعوم حاليًا على لينكس. يمكنك تحميل الملف من قائمة الرسالة إن وُجدت.'
              : 'تشغيل الصوت غير متاح حاليًا على هذا الإصدار من التطبيق.',
        ),
      );
    }

    return ValueListenableBuilder<GlobalDesktopVoiceSession?>(
      valueListenable: DesktopAudioPlaybackCoordinator.activeSessionNotifier,
      builder: (context, activeSession, _) {
        final isThisActive = activeSession?.message.id == message.id;

        return Container(
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable:
                    DesktopAudioPlaybackCoordinator.isPlayingNotifier,
                builder: (context, isPlaying, _) {
                  final playingThis = isThisActive && isPlaying;
                  return IconButton(
                    onPressed: token == null || token!.isEmpty
                        ? null
                        : () => DesktopAudioPlaybackCoordinator.toggleOrPlay(
                            message: message,
                            token: token!,
                          ),
                    icon: Icon(
                      playingThis
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      size: 30,
                      color: const Color(0xFF2A8CFF),
                    ),
                  );
                },
              ),
              Expanded(
                child: ValueListenableBuilder<Duration>(
                  valueListenable:
                      DesktopAudioPlaybackCoordinator.positionNotifier,
                  builder: (context, globalPos, _) {
                    return ValueListenableBuilder<Duration>(
                      valueListenable:
                          DesktopAudioPlaybackCoordinator.durationNotifier,
                      builder: (context, globalTotal, _) {
                        final position =
                            isThisActive ? globalPos : Duration.zero;
                        final total =
                            isThisActive ? globalTotal : Duration.zero;
                        final safeMaxMs = total.inMilliseconds <= 0
                            ? 1.0
                            : total.inMilliseconds.toDouble();
                        final value = position.inMilliseconds
                            .clamp(0, safeMaxMs.toInt())
                            .toDouble();
                        final progressPercent =
                            safeMaxMs > 0 ? value / safeMaxMs : 0.0;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTapDown: (details) {
                                if (!isThisActive ||
                                    total.inMilliseconds <= 0) {
                                  return;
                                }
                                final renderBox =
                                    context.findRenderObject() as RenderBox;
                                final tapPercent =
                                    details.localPosition.dx /
                                    renderBox.size.width;
                                DesktopAudioPlaybackCoordinator.seek(
                                  Duration(
                                    milliseconds:
                                        (tapPercent * safeMaxMs).round(),
                                  ),
                                );
                              },
                              child: Container(
                                height: 35,
                                width: double.infinity,
                                color: Colors.transparent,
                                child: CustomPaint(
                                  painter: _VoiceWaveformPainter(
                                    amplitudes: _generateAmplitudes(message.id),
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
                                ValueListenableBuilder<double>(
                                  valueListenable:
                                      DesktopAudioPlaybackCoordinator
                                          .speedNotifier,
                                  builder: (context, speed, _) {
                                    return InkWell(
                                      onTap: DesktopAudioPlaybackCoordinator
                                          .cycleSpeed,
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withValues(
                                            alpha: 0.2,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '${speed}x',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
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

    const barWidth = 3.0;
    const spacing = 2.0;
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
