import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/providers/providers.dart';
import '../../models/chat_models.dart';

/// Represents the currently active voice note session in the global player.
class GlobalVoiceSession {
  const GlobalVoiceSession({
    required this.message,
    required this.conversationId,
    required this.conversationTitle,
    required this.senderName,
    required this.filePath,
    required this.totalDuration,
  });

  final ChatMessage message;
  final String conversationId;
  final String conversationTitle;
  final String senderName;
  final String filePath;
  final Duration totalDuration;

  GlobalVoiceSession copyWith({
    ChatMessage? message,
    String? conversationId,
    String? conversationTitle,
    String? senderName,
    String? filePath,
    Duration? totalDuration,
  }) {
    return GlobalVoiceSession(
      message: message ?? this.message,
      conversationId: conversationId ?? this.conversationId,
      conversationTitle: conversationTitle ?? this.conversationTitle,
      senderName: senderName ?? this.senderName,
      filePath: filePath ?? this.filePath,
      totalDuration: totalDuration ?? this.totalDuration,
    );
  }
}

/// Global coordinator & singleton audio engine (Telegram-style):
/// - Ensures only one voice note plays at a time across the entire app.
/// - Keeps playback alive when navigating out of a conversation or switching tabs.
/// - Coordinates persistent voice note playback speed (1x, 1.5x, 2x).
/// - Drives both inline `ChatAudioAttachmentPlayer` bubbles and `GlobalMiniAudioPlayerBar`.
class ChatAudioPlaybackCoordinator {
  static const String _voiceSpeedPrefKey = 'preferred_voice_speed';

  static final ValueNotifier<String?> activePlayerNotifier =
      ValueNotifier<String?>(null);

  static final ValueNotifier<GlobalVoiceSession?> activeSessionNotifier =
      ValueNotifier<GlobalVoiceSession?>(null);

  static final ValueNotifier<bool> isPlayingNotifier =
      ValueNotifier<bool>(false);

  static final ValueNotifier<bool> isBufferingNotifier =
      ValueNotifier<bool>(false);

  static final ValueNotifier<Duration> positionNotifier =
      ValueNotifier<Duration>(Duration.zero);

  static final ValueNotifier<Duration> durationNotifier =
      ValueNotifier<Duration>(Duration.zero);

  static final ValueNotifier<double> playbackSpeedNotifier =
      ValueNotifier<double>(1.0);

  static final Set<String> playedMessageIds = <String>{};

  static AudioPlayer? _sharedPlayer;
  static bool _isSpeedInitialized = false;
  static bool _audioPluginUnavailable = false;

  static bool get isAudioPluginUnavailable => _audioPluginUnavailable;

  static AudioPlayer _ensurePlayer() {
    if (_sharedPlayer != null) return _sharedPlayer!;
    final player = AudioPlayer(useProxyForRequestHeaders: false);
    _sharedPlayer = player;

    player.setSpeed(playbackSpeedNotifier.value).catchError((_) {});

    player.playerStateStream.listen((state) {
      isPlayingNotifier.value = state.playing;
      isBufferingNotifier.value =
          state.processingState == ProcessingState.buffering ||
              state.processingState == ProcessingState.loading;

      if (state.playing) {
        final activeId = activePlayerNotifier.value;
        if (activeId != null) {
          playedMessageIds.add(activeId);
        }
      }

      if (state.processingState == ProcessingState.completed) {
        player.seek(Duration.zero);
        player.pause();
        positionNotifier.value = Duration.zero;
        isPlayingNotifier.value = false;
        activePlayerNotifier.value = null;
        activeSessionNotifier.value = null;
      }
    });

    player.positionStream.listen((pos) {
      positionNotifier.value = pos;
    });

    player.durationStream.listen((dur) {
      if (dur != null && dur > Duration.zero) {
        durationNotifier.value = dur;
        final currentSession = activeSessionNotifier.value;
        if (currentSession != null) {
          activeSessionNotifier.value =
              currentSession.copyWith(totalDuration: dur);
        }
      }
    });

    return player;
  }

  static void setActive(String messageId) {
    activePlayerNotifier.value = messageId;
  }

  static void stopIfActive(String messageId) {
    if (activePlayerNotifier.value == messageId) {
      stopAndDismiss();
    }
  }

  /// Stops playback and hides the global mini player bar.
  static Future<void> stopAndDismiss() async {
    activePlayerNotifier.value = null;
    activeSessionNotifier.value = null;
    isPlayingNotifier.value = false;
    isBufferingNotifier.value = false;
    positionNotifier.value = Duration.zero;
    try {
      await _sharedPlayer?.stop();
      await _sharedPlayer?.seek(Duration.zero);
    } catch (_) {}
  }

  /// Toggles play/pause for the currently active session.
  static Future<void> toggleCurrentSession() async {
    final session = activeSessionNotifier.value;
    if (session == null || _audioPluginUnavailable) return;
    final player = _ensurePlayer();
    try {
      if (player.playing) {
        await player.pause();
      } else {
        await player.play();
      }
    } catch (_) {}
  }

  /// Seeks the currently active session to [target].
  static Future<void> seekCurrentSession(Duration target) async {
    if (_sharedPlayer == null || activeSessionNotifier.value == null) return;
    positionNotifier.value = target;
    try {
      await _sharedPlayer!.seek(target);
    } catch (_) {}
  }

  /// Starts or toggles playback of a voice note using the global engine.
  static Future<Duration?> playOrToggleVoiceNote({
    required ChatMessage message,
    required String localPath,
    required String conversationTitle,
    required String senderName,
    Duration? knownDuration,
    Duration? initialSeek,
  }) async {
    if (_audioPluginUnavailable) return null;
    final player = _ensurePlayer();

    final isSameMessage = activePlayerNotifier.value == message.id &&
        activeSessionNotifier.value?.filePath == localPath;

    if (isSameMessage) {
      if (player.playing) {
        await player.pause();
        return durationNotifier.value;
      } else {
        if (initialSeek != null) {
          await player.seek(initialSeek);
        }
        await player.play();
        return durationNotifier.value;
      }
    }

    try {
      isBufferingNotifier.value = true;
      activePlayerNotifier.value = message.id;
      positionNotifier.value = initialSeek ?? Duration.zero;
      final fallbackDuration = knownDuration ?? Duration.zero;
      durationNotifier.value = fallbackDuration;

      activeSessionNotifier.value = GlobalVoiceSession(
        message: message,
        conversationId: message.conversationId,
        conversationTitle: conversationTitle,
        senderName: senderName,
        filePath: localPath,
        totalDuration: fallbackDuration,
      );

      final resolvedDur = await player
          .setFilePath(localPath)
          .timeout(const Duration(seconds: 15));
      await player.setSpeed(playbackSpeedNotifier.value);

      final effectiveDur =
          (resolvedDur != null && resolvedDur > Duration.zero)
              ? resolvedDur
              : fallbackDuration;
      if (effectiveDur > Duration.zero) {
        durationNotifier.value = effectiveDur;
        activeSessionNotifier.value = activeSessionNotifier.value?.copyWith(
          totalDuration: effectiveDur,
        );
      }

      if (initialSeek != null && initialSeek > Duration.zero) {
        await player.seek(initialSeek);
      }
      playedMessageIds.add(message.id);
      await player.play();
      return effectiveDur;
    } on MissingPluginException {
      _audioPluginUnavailable = true;
      await stopAndDismiss();
      return null;
    } catch (_) {
      isBufferingNotifier.value = false;
      rethrow;
    } finally {
      isBufferingNotifier.value = false;
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
      await _sharedPlayer?.setSpeed(speed);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_voiceSpeedPrefKey, speed);
    } catch (_) {}
  }

  /// Cycles playback speed: 1.0 -> 1.5 -> 2.0 -> 1.0.
  static void cyclePlaybackSpeed() {
    HapticFeedback.selectionClick();
    final current = playbackSpeedNotifier.value;
    double nextSpeed = 1.0;
    if (current == 1.0) {
      nextSpeed = 1.5;
    } else if (current == 1.5) {
      nextSpeed = 2.0;
    } else {
      nextSpeed = 1.0;
    }
    setPlaybackSpeed(nextSpeed);
  }
}

/// Telegram / Apple-style Global Mini Audio Player Bar.
///
/// Appears at the top of `ChatHomeScreen` and `ConversationScreen` whenever a
/// voice note is active in `ChatAudioPlaybackCoordinator`, allowing the user
/// to control playback, change speed (1x/1.5x/2x), scrub, or jump back to the
/// conversation while browsing anywhere in the app.
class GlobalMiniAudioPlayerBar extends ConsumerWidget {
  const GlobalMiniAudioPlayerBar({
    super.key,
    this.currentConversationId,
    this.onTapSession,
  });

  final String? currentConversationId;
  final void Function(GlobalVoiceSession session)? onTapSession;

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString();
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<GlobalVoiceSession?>(
      valueListenable: ChatAudioPlaybackCoordinator.activeSessionNotifier,
      builder: (context, session, _) {
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: session == null
              ? const SizedBox.shrink()
              : _buildBarContent(context, session, isDark),
        );
      },
    );
  }

  Widget _buildBarContent(
    BuildContext context,
    GlobalVoiceSession session,
    bool isDark,
  ) {
    final bgColor = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.96)
        : Colors.white.withValues(alpha: 0.96);
    final borderColor =
        isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
    const accentColor = Color(0xFF007AFF);

    return Material(
      color: bgColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTapSession != null ? () => onTapSession!(session) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                children: [
                  // 1. Play / Pause Button
                  ValueListenableBuilder<bool>(
                    valueListenable:
                        ChatAudioPlaybackCoordinator.isPlayingNotifier,
                    builder: (context, isPlaying, _) {
                      return ValueListenableBuilder<bool>(
                        valueListenable:
                            ChatAudioPlaybackCoordinator.isBufferingNotifier,
                        builder: (context, isBuffering, _) {
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              ChatAudioPlaybackCoordinator
                                  .toggleCurrentSession();
                            },
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: isBuffering
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: accentColor,
                                        ),
                                      )
                                    : Icon(
                                        isPlaying
                                            ? CupertinoIcons.pause_fill
                                            : CupertinoIcons.play_fill,
                                        size: 17,
                                        color: accentColor,
                                      ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 10),

                  // 2. Sender Name, Conversation Title & Live Timer
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              CupertinoIcons.mic_fill,
                              size: 13,
                              color: Color(0xFF00A884),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                session.conversationTitle.isNotEmpty &&
                                        session.conversationTitle !=
                                            session.senderName
                                    ? '${session.senderName} • ${session.conversationTitle}'
                                    : session.senderName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        ValueListenableBuilder<Duration>(
                          valueListenable:
                              ChatAudioPlaybackCoordinator.positionNotifier,
                          builder: (context, pos, _) {
                            return ValueListenableBuilder<Duration>(
                              valueListenable:
                                  ChatAudioPlaybackCoordinator.durationNotifier,
                              builder: (context, dur, _) {
                                final total = dur > Duration.zero
                                    ? dur
                                    : session.totalDuration;
                                return Text(
                                  total > Duration.zero
                                      ? '${_formatDuration(pos)} / ${_formatDuration(total)}'
                                      : _formatDuration(pos),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? Colors.white54
                                        : const Color(0xFF64748B),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // 3. Speed Toggle Pill (1x / 1.5x / 2x)
                  ValueListenableBuilder<double>(
                    valueListenable:
                        ChatAudioPlaybackCoordinator.playbackSpeedNotifier,
                    builder: (context, speed, _) {
                      final label = speed == 1.0
                          ? '1×'
                          : speed == 1.5
                              ? '1.5×'
                              : '2×';
                      return InkWell(
                        onTap: ChatAudioPlaybackCoordinator.cyclePlaybackSpeed,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: accentColor,
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(width: 4),

                  // 4. Close / Stop Button
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    tooltip: 'إيقاف وإغلاق المشغل',
                    icon: Icon(
                      CupertinoIcons.xmark,
                      size: 16,
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      ChatAudioPlaybackCoordinator.stopAndDismiss();
                    },
                  ),
                ],
              ),
            ),
          ),

          // Interactive Thin Scrubbing Progress Bar at Bottom
          ValueListenableBuilder<Duration>(
            valueListenable: ChatAudioPlaybackCoordinator.positionNotifier,
            builder: (context, pos, _) {
              return ValueListenableBuilder<Duration>(
                valueListenable: ChatAudioPlaybackCoordinator.durationNotifier,
                builder: (context, dur, _) {
                  final total =
                      dur > Duration.zero ? dur : session.totalDuration;
                  final maxMs = total.inMilliseconds <= 0
                      ? 1.0
                      : total.inMilliseconds.toDouble();
                  final progress =
                      (pos.inMilliseconds / maxMs).clamp(0.0, 1.0);

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final barWidth = constraints.maxWidth;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          if (barWidth <= 0 || total.inMilliseconds <= 0) {
                            return;
                          }
                          final pct = (details.localPosition.dx / barWidth)
                              .clamp(0.0, 1.0);
                          final target = Duration(
                            milliseconds:
                                (pct * total.inMilliseconds).round(),
                          );
                          ChatAudioPlaybackCoordinator.seekCurrentSession(
                            target,
                          );
                        },
                        child: SizedBox(
                          height: 3,
                          width: double.infinity,
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: borderColor,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              accentColor,
                            ),
                            minHeight: 2.5,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

/// WhatsApp-style voice note audio player.
///
/// Features:
/// - Distinctive WhatsApp voice bubble layout (Play button, custom waveform with scrubber thumb, duration & speed pill, and mic status badge).
/// - Instant duration preview from metadata so the duration is visible before streaming starts.
/// - Interactive touch scrubbing: drag or tap along the waveform to seek.
/// - Speed toggle pill (1x, 1.5x, 2x).
/// - Powered by `ChatAudioPlaybackCoordinator` so playback continues seamlessly when leaving the chat.
class ChatAudioAttachmentPlayer extends ConsumerStatefulWidget {
  const ChatAudioAttachmentPlayer({
    super.key,
    required this.message,
    this.isMine = false,
    this.conversationTitle,
  });

  final ChatMessage message;
  final bool isMine;
  final String? conversationTitle;

  @override
  ConsumerState<ChatAudioAttachmentPlayer> createState() =>
      _ChatAudioAttachmentPlayerState();
}

class _ChatAudioAttachmentPlayerState
    extends ConsumerState<ChatAudioAttachmentPlayer> {
  String? _loadedFilePath;
  bool _loading = false;
  double _playbackSpeed = 1.0;

  bool _isScrubbing = false;
  double _scrubPercent = 0.0;
  Duration? _pendingSeekDuration;
  Duration? _knownTotalDuration;

  late final List<double> _waveformAmplitudes;

  bool get _isThisMessageActive =>
      ChatAudioPlaybackCoordinator.activePlayerNotifier.value ==
      widget.message.id;

  @override
  void initState() {
    super.initState();
    _playbackSpeed = ChatAudioPlaybackCoordinator.playbackSpeedNotifier.value;
    _waveformAmplitudes = _generateVoiceAmplitudes(widget.message.id);

    // Seed duration from message metadata if available so it displays instantly
    final metaMs = (widget.message.metadata?['durationMs'] as num?)?.toInt();
    if (metaMs != null && metaMs > 0) {
      _knownTotalDuration = Duration(milliseconds: metaMs);
    }

    ChatAudioPlaybackCoordinator.activePlayerNotifier
        .addListener(_onCoordinatorStateChanged);
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
        }
      }
    });

    // Check if audio file is already cached in local phone storage, or pre-cache
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkAndPreloadAudio();
      }
    });
  }

  void _onCoordinatorStateChanged() {
    if (!mounted) return;
    setState(() {});
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
    }
  }

  @override
  void dispose() {
    ChatAudioPlaybackCoordinator.activePlayerNotifier
        .removeListener(_onCoordinatorStateChanged);
    ChatAudioPlaybackCoordinator.playbackSpeedNotifier
        .removeListener(_onPlaybackSpeedChanged);
    // Intentionally do NOT stop playback on dispose so the voice note
    // continues playing in the GlobalMiniAudioPlayerBar when leaving the chat!
    super.dispose();
  }

  Future<void> _checkAndPreloadAudio() async {
    if (ChatAudioPlaybackCoordinator.isAudioPluginUnavailable || _loading) {
      return;
    }
    try {
      final repository = ref.read(chatRepositoryProvider);
      final cachedPath =
          await repository.getCachedAttachmentPath(widget.message);
      if (cachedPath != null && await File(cachedPath).exists()) {
        _loadedFilePath = cachedPath;
      } else {
        // Pre-cache voice note file into internal storage in background
        final fileUrl = widget.message.fileUrl;
        if (fileUrl != null && fileUrl.isNotEmpty) {
          final path = await repository
              .downloadAttachment(widget.message)
              .timeout(const Duration(seconds: 25));
          if (mounted && path.isNotEmpty && await File(path).exists()) {
            _loadedFilePath = path;
          }
        }
      }
    } catch (_) {}
  }

  String _resolveConversationTitle() {
    final explicitTitle = widget.conversationTitle?.trim() ?? '';
    if (explicitTitle.isNotEmpty) return explicitTitle;
    try {
      final authUserId =
          ref.read(authControllerProvider).valueOrNull?.id ?? '';
      final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
      if (overview != null) {
        for (final conv in overview.conversations) {
          if (conv.id == widget.message.conversationId) {
            return conv.displayTitle(authUserId);
          }
        }
      }
    } catch (_) {}
    return 'محادثة';
  }

  String _resolveSenderName() {
    final senderName = widget.message.sender?.displayName.trim() ?? '';
    if (senderName.isNotEmpty) return senderName;
    return widget.isMine ? 'رسالتك الصوتية' : 'رسالة صوتية';
  }

  Future<void> _handlePlayPause() async {
    if (ChatAudioPlaybackCoordinator.isAudioPluginUnavailable) return;
    HapticFeedback.selectionClick();

    if (_isThisMessageActive) {
      await ChatAudioPlaybackCoordinator.toggleCurrentSession();
      return;
    }

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
        _loadedFilePath = localPath;
        final seekTarget = _pendingSeekDuration;
        _pendingSeekDuration = null;

        final dur = await ChatAudioPlaybackCoordinator.playOrToggleVoiceNote(
          message: widget.message,
          localPath: localPath,
          conversationTitle: _resolveConversationTitle(),
          senderName: _resolveSenderName(),
          knownDuration: _knownTotalDuration,
          initialSeek: seekTarget,
        );
        if (dur != null && dur > Duration.zero && mounted) {
          setState(() {
            _knownTotalDuration = dur;
          });
        }
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
    ChatAudioPlaybackCoordinator.cyclePlaybackSpeed();
  }

  void _onWaveformTap(TapDownDetails details, double width, Duration total) {
    if (width <= 0 || total.inMilliseconds <= 0) return;
    final percent = (details.localPosition.dx / width).clamp(0.0, 1.0);
    final targetDuration =
        Duration(milliseconds: (percent * total.inMilliseconds).round());
    if (_isThisMessageActive) {
      ChatAudioPlaybackCoordinator.seekCurrentSession(targetDuration);
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
      final targetDuration = Duration(
        milliseconds: (_scrubPercent * total.inMilliseconds).round(),
      );
      if (_isThisMessageActive) {
        ChatAudioPlaybackCoordinator.seekCurrentSession(targetDuration);
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

    if (ChatAudioPlaybackCoordinator.isAudioPluginUnavailable) {
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

    final isMine = widget.isMine;
    final Color playedWaveColor = const Color(0xFF00A884);
    final Color unplayedWaveColor = isMine
        ? (isDark
            ? Colors.white.withValues(alpha: 0.28)
            : const Color(0xFF94A3B8))
        : (isDark
            ? Colors.white.withValues(alpha: 0.24)
            : const Color(0xFFCBD5E1));
    const Color thumbColor = Color(0xFF00A884);
    const Color actionIconColor = Colors.white;
    const Color actionBgColor = Color(0xFF00A884);
    final Color durationTextColor = isMine
        ? (isDark ? Colors.white70 : const Color(0xFF475569))
        : (isDark ? Colors.white70 : const Color(0xFF64748B));

    return SizedBox(
      width: 272,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: ValueListenableBuilder<bool>(
          valueListenable: ChatAudioPlaybackCoordinator.isPlayingNotifier,
          builder: (context, globalPlaying, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: ChatAudioPlaybackCoordinator.isBufferingNotifier,
              builder: (context, globalBuffering, _) {
                return ValueListenableBuilder<Duration>(
                  valueListenable:
                      ChatAudioPlaybackCoordinator.positionNotifier,
                  builder: (context, globalPosition, _) {
                    return ValueListenableBuilder<Duration>(
                      valueListenable:
                          ChatAudioPlaybackCoordinator.durationNotifier,
                      builder: (context, globalDuration, _) {
                        final isActive = _isThisMessageActive;
                        final isPlaying = isActive && globalPlaying;
                        final isBuffering =
                            _loading || (isActive && globalBuffering);

                        final position = isActive
                            ? globalPosition
                            : (_pendingSeekDuration ?? Duration.zero);
                        final total = (isActive && globalDuration > Duration.zero)
                            ? globalDuration
                            : (_knownTotalDuration ?? Duration.zero);
                        final safeMaxMs = total.inMilliseconds <= 0
                            ? 1.0
                            : total.inMilliseconds.toDouble();

                        final currentProgress =
                            (position.inMilliseconds / safeMaxMs)
                                .clamp(0.0, 1.0);
                        final effectiveProgress =
                            _isScrubbing ? _scrubPercent : currentProgress;

                        final displayDuration = _isScrubbing
                            ? Duration(
                                milliseconds:
                                    (_scrubPercent * safeMaxMs).round(),
                              )
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
                                  Builder(
                                    builder: (waveContext) {
                                      double resolveWaveWidth() {
                                        final box =
                                            waveContext.findRenderObject();
                                        if (box is RenderBox && box.hasSize) {
                                          return box.size.width;
                                        }
                                        return 160.0;
                                      }

                                      return GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTapDown: (d) => _onWaveformTap(
                                          d,
                                          resolveWaveWidth(),
                                          total,
                                        ),
                                        onHorizontalDragStart: (d) =>
                                            _onWaveformDragStart(
                                          d,
                                          resolveWaveWidth(),
                                        ),
                                        onHorizontalDragUpdate: (d) =>
                                            _onWaveformDragUpdate(
                                          d,
                                          resolveWaveWidth(),
                                        ),
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
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
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
                              isPlayed: ChatAudioPlaybackCoordinator
                                      .playedMessageIds
                                      .contains(widget.message.id) ||
                                  position > Duration.zero ||
                                  widget.message.seenBy.isNotEmpty,
                              isDark: isDark,
                            ),
                          ],
                        );
                      },
                    );
                  },
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
