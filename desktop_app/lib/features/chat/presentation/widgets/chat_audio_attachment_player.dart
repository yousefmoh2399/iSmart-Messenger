import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/network/media_url_resolver.dart';
import '../../../../shared/services/web_platform_bridge.dart' as web_bridge;
import '../../models/chat_models.dart';

/// `just_audio` على Linux غالبًا بدون تسجيل native صحيح في هذا المشروع → كراش عند فتح الشات.
bool _justAudioNativePlaybackSupported() {
  if (kIsWeb) {
    return true; // Web (including Electron) is fully supported by just_audio
  }
  return Platform.isWindows || Platform.isMacOS;
}

class ChatAudioAttachmentPlayer extends StatefulWidget {
  const ChatAudioAttachmentPlayer({
    super.key,
    required this.message,
    required this.token,
  });

  final ChatMessage message;
  final String? token;

  @override
  State<ChatAudioAttachmentPlayer> createState() =>
      _ChatAudioAttachmentPlayerState();
}

class _ChatAudioAttachmentPlayerState extends State<ChatAudioAttachmentPlayer> {
  AudioPlayer? _player;
  String? _loadedUrl;
  String? _loadedToken;
  String? _electronObjectUrl;
  bool _loading = false;
  bool _audioPluginUnavailable = false;

  @override
  void initState() {
    super.initState();
    if (!_justAudioNativePlaybackSupported()) {
      _audioPluginUnavailable = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      try {
        _player = AudioPlayer();
      } on MissingPluginException {
        _audioPluginUnavailable = true;
        _player = null;
      } catch (_) {
        _audioPluginUnavailable = true;
        _player = null;
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant ChatAudioAttachmentPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeLoad();
  }

  @override
  void dispose() {
    _revokeElectronObjectUrl();
    _player?.dispose().catchError((_) {});
    super.dispose();
  }

  void _revokeElectronObjectUrl() {
    final objectUrl = _electronObjectUrl;
    if (objectUrl != null) {
      web_bridge.revokeObjectUrl(objectUrl);
      _electronObjectUrl = null;
    }
  }

  String _fallbackMimeType() {
    final mime = widget.message.mimeType?.trim().toLowerCase();
    if (mime != null && mime.startsWith('audio/')) {
      return mime;
    }
    final fileName = (widget.message.fileName ?? widget.message.fileUrl ?? '')
        .toLowerCase();
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

  Future<void> _maybeLoad() async {
    final player = _player;
    final url = resolveMediaUrl(widget.message.fileUrl) ?? '';
    final token = widget.token ?? '';
    if (url.isEmpty || token.isEmpty) {
      return;
    }
    if (player == null) {
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
      final headers = {'Authorization': 'Bearer $token'};
      if (kIsWeb && web_bridge.isElectron()) {
        final objectUrl = await web_bridge.fetchElectronObjectUrl(
          url: url,
          headers: headers,
          fallbackMimeType: _fallbackMimeType(),
        );
        _revokeElectronObjectUrl();
        _electronObjectUrl = objectUrl;
        await player.setUrl(objectUrl);
      } else {
        await player.setUrl(url, headers: headers);
      }
      _loadedUrl = url;
      _loadedToken = token;
    } on MissingPluginException {
      _audioPluginUnavailable = true;
      _loadedUrl = null;
      _loadedToken = null;
    } catch (_) {
      _audioPluginUnavailable = true;
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
    _maybeLoad();
    final player = _player;
    if (_audioPluginUnavailable) {
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
          style: TextStyle(color: Colors.black),
          onLinux
              ? 'تشغيل الملاحظات الصوتية غير مدعوم حاليًا على لينكس. يمكنك تحميل الملف من قائمة الرسالة إن وُجدت.'
              : 'تشغيل الصوت غير متاح حاليًا على هذا الإصدار من التطبيق.',
        ),
      );
    }
    if (player == null) {
      return Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF6F9FC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDCE6F0)),
        ),
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
      padding: const EdgeInsets.all(10),

      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        // border: Border.all(color: const Color(0xFFDCE6F0)),
      ),
      child: Row(
        children: [
          StreamBuilder<PlayerState>(
            stream: player.playerStateStream,
            builder: (context, snapshot) {
              final playing = snapshot.data?.playing == true;
              return IconButton(
                onPressed: widget.token == null || widget.token!.isEmpty
                    ? null
                    : () async {
                        try {
                          if (playing) {
                            await player.pause();
                          } else {
                            await player.play();
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
                  playing
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  size: 30,
                ),
              );
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,

                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                StreamBuilder<Duration>(
                  stream: player.positionStream,
                  builder: (context, posSnapshot) {
                    final position = posSnapshot.data ?? Duration.zero;
                    return StreamBuilder<Duration?>(
                      stream: player.durationStream,
                      builder: (context, durSnapshot) {
                        final total = durSnapshot.data ?? Duration.zero;
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
                                    : (next) => player.seek(
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
