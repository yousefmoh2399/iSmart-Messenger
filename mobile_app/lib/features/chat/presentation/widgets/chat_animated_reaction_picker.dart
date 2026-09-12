import 'dart:math' as math;

import 'package:animated_emoji/animated_emoji.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../utils/chat_reaction_emoji_stats.dart';

/// إيموجيات افتراضية لصف الاختصار إن لم يوجد تاريخ استخدام بعد.
const List<String> kDefaultQuickReactionEmojis = <String>[
  '👍',
  '❤️',
  '😂',
  '🔥',
  '👏',
  '😮',
  '😍',
  '😭',
  '😁',
  '🤝',
  '🎉',
  '👌',
  '🙏',
  '💯',
  '🤔',
  '😎',
  '🥳',
  '😡',
  '🙌',
  '😢',
  '✅',
  '👀',
  '💪',
  '🙂',
];

const Set<String> kBundledAnimatedReactionNames = <String>{
  'angry',
  'checkMark',
  'clap',
  'eyes',
  'fire',
  'foldedHands',
  'grin',
  'handshake',
  'heartEyes',
  'joy',
  'loudlyCrying',
  'ok',
  'oneHundred',
  'partyingFace',
  'partyPopper',
  'redHeart',
  'sad',
  'sunglassesFace',
  'thinkingFace',
  'thumbsUp',
};

bool isBundledAnimatedReaction(AnimatedEmojiData data) {
  return kBundledAnimatedReactionNames.contains(data.name);
}

List<AnimatedEmojiData>? _cachedChatPickerEmojis;

List<AnimatedEmojiData> chatPickerAnimatedEmojis() {
  if (_cachedChatPickerEmojis != null) {
    return _cachedChatPickerEmojis!;
  }
  final seen = <String>{};
  final out = <AnimatedEmojiData>[];
  for (final e in AnimatedEmojis.values) {
    if (!isBundledAnimatedReaction(e)) {
      continue;
    }
    if (e.categories.contains('Flags')) {
      continue;
    }
    final u = e.toUnicodeEmoji();
    if (u.isEmpty) {
      continue;
    }
    if (seen.add(u)) {
      out.add(e);
    }
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return _cachedChatPickerEmojis = out;
}

class ChatPickerSections {
  ChatPickerSections({required this.frequentTop, required this.gridRest});

  final List<AnimatedEmojiData> frequentTop;
  final List<AnimatedEmojiData> gridRest;
}

/// الأكثر استخدامًا في الأعلى (بدون تكرار في الشبكة السفلية)، والباقي مرتب بالاستخدام ثم الاسم.
Future<ChatPickerSections> loadChatReactionPickerSections({
  int maxFrequent = 18,
}) async {
  final stats = await ChatReactionEmojiStats.load();
  final all = chatPickerAnimatedEmojis();
  return buildPickerSections(all, stats, maxFrequent: maxFrequent);
}

ChatPickerSections buildPickerSections(
  List<AnimatedEmojiData> all,
  Map<String, int> stats, {
  int maxFrequent = 18,
}) {
  final used = all.where((e) => (stats[e.name] ?? 0) > 0).toList()
    ..sort((a, b) {
      final c = (stats[b.name] ?? 0).compareTo(stats[a.name] ?? 0);
      if (c != 0) {
        return c;
      }
      return a.name.compareTo(b.name);
    });
  final frequentTop = used.take(maxFrequent).toList();
  final favNames = frequentTop.map((e) => e.name).toSet();
  final gridRest = all.where((e) => !favNames.contains(e.name)).toList()
    ..sort((a, b) {
      final ca = stats[a.name] ?? 0;
      final cb = stats[b.name] ?? 0;
      if (cb != ca) {
        return cb.compareTo(ca);
      }
      return a.name.compareTo(b.name);
    });
  return ChatPickerSections(frequentTop: frequentTop, gridRest: gridRest);
}

/// صف الاختصار: الأكثر استخدامًا أولًا ثم تعبئة من [kDefaultQuickReactionEmojis].
Future<List<String>> buildQuickReactionUnicodeRow({
  Map<String, int>? stats,
  int count = 6,
}) async {
  final s = stats ?? await ChatReactionEmojiStats.load();
  final all = chatPickerAnimatedEmojis();
  final topUsed = all.where((e) => (s[e.name] ?? 0) > 0).toList()
    ..sort((a, b) => (s[b.name] ?? 0).compareTo(s[a.name] ?? 0));
  final out = <String>[];
  for (final e in topUsed) {
    if (out.length >= count) {
      break;
    }
    out.add(e.toUnicodeEmoji());
  }
  for (final d in kDefaultQuickReactionEmojis) {
    if (out.length >= count) {
      break;
    }
    if (!out.contains(d)) {
      out.add(d);
    }
  }
  return out;
}

/// Lottie محلي من [assets/animated_emoji_lottie/] — يعمل بدون إنترنت.
class ChatOfflineLottieEmoji extends StatelessWidget {
  const ChatOfflineLottieEmoji({
    super.key,
    required this.data,
    required this.size,
    this.repeat = true,
    this.animate = true,
  });

  final AnimatedEmojiData data;
  final double size;
  final bool repeat;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        data.toUnicodeEmoji(),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: size * 0.62, height: 1.0),
      ),
    );

    if (!isBundledAnimatedReaction(data)) {
      return fallback;
    }

    return Lottie.asset(
      'assets/animated_emoji_lottie/${data.name}.json',
      width: size,
      height: size,
      repeat: repeat,
      animate: animate,
      frameBuilder: (context, child, composition) {
        if (composition == null) {
          return fallback;
        }
        return child;
      },
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class ChatAnimatedReactionOption extends StatelessWidget {
  const ChatAnimatedReactionOption({
    super.key,
    required this.data,
    required this.onTap,
    this.size = 44,
    this.animateEmoji = false,
  });

  final AnimatedEmojiData data;
  final VoidCallback onTap;
  final double size;
  final bool animateEmoji;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Center(
            child: ChatOfflineLottieEmoji(
              data: data,
              size: size,
              repeat: false,
              animate: animateEmoji,
            ),
          ),
        ),
      ),
    );
  }
}

class ChatAnimatedReactionQuickChip extends StatelessWidget {
  const ChatAnimatedReactionQuickChip({
    super.key,
    required this.emoji,
    required this.onTap,
    this.size = 34,
    this.animateEmoji = true,
  });

  final String emoji;
  final VoidCallback onTap;
  final double size;
  final bool animateEmoji;

  @override
  Widget build(BuildContext context) {
    final data = AnimatedEmojis.fromEmojiString(emoji);
    final child = data != null && isBundledAnimatedReaction(data)
        ? ChatOfflineLottieEmoji(
            data: data,
            size: size,
            repeat: false,
            animate: animateEmoji,
          )
        : Text(emoji, style: TextStyle(fontSize: size * 0.72, height: 1.05));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: SizedBox(
            width: size + 12,
            height: size + 4,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// نافذة اختيار التفاعلات (ديسكتوب / شريط الملحق) — محليّة + مرتبة بالاستخدام.
Future<void> showChatReactionPickerDialog({
  required BuildContext context,
  required Future<void> Function(String unicodeEmoji) onReact,
}) async {
  final sections = buildPickerSections(
    chatPickerAnimatedEmojis(),
    const <String, int>{},
  );
  final theme = Theme.of(context);
  final titleSmall = theme.textTheme.titleSmall?.copyWith(
    fontWeight: FontWeight.w800,
  );
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final viewport = MediaQuery.sizeOf(dialogContext);
      final dialogWidth = math.max(300.0, math.min(420.0, viewport.width - 24));
      final dialogHeight = math.max(
        360.0,
        math.min(440.0, viewport.height * 0.82),
      );
      final gridColumns = dialogWidth < 360 ? 5 : 6;
      final optionSize = gridColumns == 5 ? 36.0 : 38.0;

      return Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'اختر تفاعلًا',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (sections.frequentTop.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Text('الأكثر استخدامًا', style: titleSmall),
                ),
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    scrollDirection: Axis.horizontal,
                    itemCount: sections.frequentTop.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 2),
                    itemBuilder: (context, i) {
                      final data = sections.frequentTop[i];
                      return SizedBox(
                        width: 60,
                        child: ChatAnimatedReactionOption(
                          data: data,
                          size: 46,
                          animateEmoji: true,
                          onTap: () async {
                            Navigator.of(dialogContext).pop();
                            await onReact(data.toUnicodeEmoji());
                          },
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                  child: Text('باقي التفاعلات', style: titleSmall),
                ),
              ],
              const Divider(height: 1),
              Expanded(
                child: GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    8,
                    sections.frequentTop.isEmpty ? 8 : 2,
                    8,
                    10,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: gridColumns,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                    childAspectRatio: 1,
                  ),
                  itemCount: sections.gridRest.length,
                  itemBuilder: (context, index) {
                    final data = sections.gridRest[index];
                    return ChatAnimatedReactionOption(
                      data: data,
                      size: optionSize,
                      onTap: () async {
                        Navigator.of(dialogContext).pop();
                        await onReact(data.toUnicodeEmoji());
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
