import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2.8,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6.5,
                                ),
                              ),
                              child: Slider(
                                min: 0,
                                max: safeMaxMs,
                                value: value,
                                onChanged: total.inMilliseconds <= 0
                                    ? null
                                    : (next) => _player.seek(
                                        Duration(milliseconds: next.round()),
                                      ),
                              ),
                            ),
                            Text(
                              '${_formatDuration(position)} / ${_formatDuration(total)}',
                              style: Theme.of(context).textTheme.labelSmall,
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
