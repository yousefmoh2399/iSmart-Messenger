import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ChatPollBubble extends StatefulWidget {
  final Map<String, dynamic> poll;
  final bool isMine;
  final String currentUserId;
  final Future<void> Function(List<String>) onVote;
  final VoidCallback onExport;

  const ChatPollBubble({
    super.key,
    required this.poll,
    required this.isMine,
    required this.currentUserId,
    required this.onVote,
    required this.onExport,
  });

  @override
  State<ChatPollBubble> createState() => _ChatPollBubbleState();
}

class _ChatPollBubbleState extends State<ChatPollBubble>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> pollData;
  Set<String> _selectedOptionIds = <String>{};
  bool _hasPendingVote = false;

  @override
  void initState() {
    super.initState();
    pollData = widget.poll;
    _selectedOptionIds = _selectedOptionsFrom(widget.poll);
  }

  @override
  void didUpdateWidget(ChatPollBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    pollData = widget.poll;
    final serverSelection = _selectedOptionsFrom(widget.poll);
    final oldServerSelection = _selectedOptionsFrom(oldWidget.poll);
    final serverChanged =
        !serverSelection.containsAll(oldServerSelection) ||
        !oldServerSelection.containsAll(serverSelection);
    if (!_hasPendingVote || serverChanged) {
      _selectedOptionIds = serverSelection;
      _hasPendingVote = false;
    }
  }

  Set<String> _selectedOptionsFrom(Map<String, dynamic> data) {
    final votes = data['votes'] as Map<String, dynamic>? ?? {};
    final selected = <String>{};
    votes.forEach((optionId, voterList) {
      if (voterList is List &&
          voterList.any((voter) => voter.toString() == widget.currentUserId)) {
        selected.add(optionId);
      }
    });
    return selected;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final question = pollData['question']?.toString() ?? 'استبيان';
    final options = pollData['options'] as List<dynamic>? ?? [];
    final votes = pollData['votes'] as Map<String, dynamic>? ?? {};
    final isMultipleChoice = pollData['isMultipleChoice'] == true;
    final isClosed = pollData['isClosed'] == true;
    final isChecklist = pollData['isChecklist'] == true;
    final isAnonymous = pollData['isAnonymous'] == true;

    final uniqueVoters = <String>{};
    votes.forEach((optId, voterList) {
      if (voterList is List) {
        for (final v in voterList) {
          final vid = v.toString();
          uniqueVoters.add(vid);
        }
      }
    });

    final totalVotes = uniqueVoters.length;
    final hasVoted = _selectedOptionIds.isNotEmpty;
    final showResults = (hasVoted || isClosed) && !isChecklist;

    // Design Tokens
    final primaryAccent = isChecklist
        ? const Color(0xFF10B981) // Emerald Green
        : (widget.isMine ? colorScheme.primary : const Color(0xFF6366F1));

    final textColor = widget.isMine
        ? colorScheme.onPrimary
        : (isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A));

    final subTextColor = widget.isMine
        ? colorScheme.onPrimary.withValues(alpha: 0.72)
        : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B));

    // Progress computation for Checklist
    final completedTasksCount = options.where((opt) {
      final optId = opt['id'].toString();
      final voterList = votes[optId] as List<dynamic>? ?? [];
      return voterList.isNotEmpty;
    }).length;
    final totalTasksCount = options.length;
    final taskProgress = totalTasksCount > 0 ? completedTasksCount / totalTasksCount : 0.0;
    final isAllTasksCompleted = totalTasksCount > 0 && completedTasksCount == totalTasksCount;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minWidth: 260),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row
          Row(
            children: [
              // Main Category Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: primaryAccent.withValues(alpha: widget.isMine ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: primaryAccent.withValues(alpha: widget.isMine ? 0.4 : 0.25),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isChecklist
                          ? Icons.task_alt_rounded
                          : (isAnonymous ? Icons.visibility_off_outlined : Icons.poll_rounded),
                      color: widget.isMine ? textColor : primaryAccent,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isChecklist
                          ? 'قائمة مهام'
                          : (isAnonymous ? 'استطلاع سري' : 'استطلاع رأي'),
                      style: TextStyle(
                        color: widget.isMine ? textColor : primaryAccent,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // Checklist progress badge OR Poll status badge
              if (isChecklist) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAllTasksCompleted
                        ? const Color(0xFF10B981).withValues(alpha: widget.isMine ? 0.3 : 0.16)
                        : (widget.isMine
                            ? Colors.white.withValues(alpha: 0.12)
                            : (isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.05))),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$completedTasksCount من $totalTasksCount مكتملة',
                    style: TextStyle(
                      color: isAllTasksCompleted
                          ? (widget.isMine ? textColor : const Color(0xFF10B981))
                          : subTextColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.isMine
                        ? Colors.white.withValues(alpha: 0.12)
                        : (isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.05)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isMultipleChoice ? 'خيارات متعددة' : 'خيار واحد',
                    style: TextStyle(
                      color: subTextColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isClosed
                        ? Colors.orange.withValues(alpha: 0.15)
                        : const Color(0xFF22C55E).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isClosed ? Colors.orange : const Color(0xFF22C55E),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isClosed ? 'مغلق' : 'نشط',
                        style: TextStyle(
                          color: isClosed ? Colors.orange : const Color(0xFF22C55E),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Question / Checklist title
          Text(
            question,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              height: 1.35,
            ),
          ),

          // Checklist Linear Progress Bar
          if (isChecklist) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: taskProgress),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                builder: (context, val, _) {
                  return LinearProgressIndicator(
                    value: val,
                    minHeight: 5,
                    backgroundColor: widget.isMine
                        ? Colors.white.withValues(alpha: 0.15)
                        : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isAllTasksCompleted ? const Color(0xFF10B981) : primaryAccent,
                    ),
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Option / Task Items
          ...options.map((opt) {
            final optId = opt['id'].toString();
            final optText = opt['text'].toString();
            final voterIds = (votes[optId] as List<dynamic>? ?? [])
                .map((e) => e.toString())
                .toList();
            final count = voterIds.length;
            final percentage = totalVotes > 0 ? count / totalVotes : 0.0;
            final isMyVote = _selectedOptionIds.contains(optId);
            final isTaskDone = isChecklist && count > 0;

            final isOptionActive = isChecklist ? isTaskDone : isMyVote;

            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: isOptionActive
                      ? (widget.isMine
                          ? Colors.white.withValues(alpha: 0.16)
                          : primaryAccent.withValues(alpha: isDark ? 0.14 : 0.08))
                      : (widget.isMine
                          ? Colors.black.withValues(alpha: 0.06)
                          : (isDark
                              ? const Color(0xFF242428)
                              : const Color(0xFFF6F7F9))),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isOptionActive
                        ? (widget.isMine
                            ? Colors.white.withValues(alpha: 0.35)
                            : primaryAccent.withValues(alpha: 0.4))
                        : (widget.isMine
                            ? Colors.white.withValues(alpha: 0.1)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.05))),
                    width: isOptionActive ? 1.2 : 0.9,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: (isClosed || (hasVoted && !isMultipleChoice && !isChecklist))
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            final newVotes = Set<String>.from(_selectedOptionIds);
                            if (isMultipleChoice || isChecklist) {
                              if (isMyVote) {
                                newVotes.remove(optId);
                              } else {
                                newVotes.add(optId);
                              }
                            } else {
                              newVotes
                                ..clear()
                                ..add(optId);
                            }
                            setState(() {
                              _selectedOptionIds = newVotes;
                              _hasPendingVote = true;
                            });
                            () async {
                              try {
                                await widget.onVote(newVotes.toList());
                              } catch (_) {
                                if (!mounted) return;
                                setState(() {
                                  _selectedOptionIds = _selectedOptionsFrom(pollData);
                                  _hasPendingVote = false;
                                });
                              }
                            }();
                          },
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        // Animated progress fill (Only for Poll results)
                        if (showResults)
                          Positioned.fill(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0, end: percentage),
                              duration: const Duration(milliseconds: 550),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) {
                                return FractionallySizedBox(
                                  alignment: AlignmentDirectional.centerStart,
                                  widthFactor: value,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: widget.isMine
                                          ? Colors.white.withValues(alpha: isMyVote ? 0.22 : 0.12)
                                          : primaryAccent.withValues(alpha: isMyVote ? 0.22 : 0.12),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                        // Option Row Content
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              // Checkbox or Radio Icon with spring animation
                              AnimatedScale(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutBack,
                                scale: isOptionActive ? 1.08 : 1.0,
                                child: Icon(
                                  isChecklist
                                      ? (isTaskDone
                                          ? Icons.check_box_rounded
                                          : Icons.check_box_outline_blank_rounded)
                                      : (isMyVote
                                          ? (isMultipleChoice
                                              ? Icons.check_box_rounded
                                              : Icons.check_circle_rounded)
                                          : (isMultipleChoice
                                              ? Icons.check_box_outline_blank_rounded
                                              : Icons.radio_button_unchecked_rounded)),
                                  size: 21,
                                  color: isOptionActive
                                      ? (widget.isMine ? textColor : primaryAccent)
                                      : subTextColor.withValues(alpha: 0.7),
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Text + completion attribution
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      optText,
                                      style: TextStyle(
                                        color: isTaskDone
                                            ? subTextColor
                                            : textColor,
                                        fontSize: 13.5,
                                        fontWeight: isOptionActive
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        decoration: isTaskDone
                                            ? TextDecoration.lineThrough
                                            : null,
                                        decorationColor: subTextColor,
                                      ),
                                    ),
                                    if (isTaskDone) ...[
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.done_all_rounded,
                                            size: 13,
                                            color: widget.isMine
                                                ? textColor.withValues(alpha: 0.8)
                                                : const Color(0xFF10B981),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isMyVote
                                                ? (voterIds.length > 1
                                                    ? 'أنجزتها أنت و${voterIds.length - 1} آخرين'
                                                    : 'أنجزتها أنت')
                                                : (voterIds.length > 1
                                                    ? 'أنجزها ${voterIds.length} أعضاء'
                                                    : 'أنجزها عضو واحد'),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: widget.isMine
                                                  ? textColor.withValues(alpha: 0.8)
                                                  : const Color(0xFF10B981),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              // Percentages and vote count for Polls
                              if (showResults) ...[
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${(percentage * 100).toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        color: textColor,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (!isAnonymous && count > 0)
                                      Text(
                                        '$count ${count == 1 ? "صوت" : "أصوات"}',
                                        style: TextStyle(
                                          color: subTextColor,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 4),

          // Footer Status & Export Button
          if (isChecklist && isAllTasksCompleted) ...[
            Container(
              margin: const EdgeInsets.only(top: 4, bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: widget.isMine ? 0.25 : 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.celebration_rounded,
                    size: 16,
                    color: Color(0xFF10B981),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'اكتملت جميع مهام القائمة بنجاح! 🎉',
                    style: TextStyle(
                      color: widget.isMine ? textColor : const Color(0xFF10B981),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isChecklist
                      ? (completedTasksCount == 0
                          ? 'اضغط على أي مهمة لتحديد إنجازها'
                          : '$completedTasksCount من أصل $totalTasksCount مهام مكتملة')
                      : (isClosed
                          ? 'انتهى الاستطلاع • $totalVotes ${totalVotes == 1 ? "تصويت" : "تصويتات"}'
                          : (totalVotes == 0
                              ? 'لا توجد تصويتات بعد'
                              : '$totalVotes ${totalVotes == 1 ? "تصويت" : "تصويتات"}')),
                  style: TextStyle(
                    color: subTextColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (widget.isMine && totalVotes > 0 && !isChecklist)
                  TextButton.icon(
                    onPressed: widget.onExport,
                    icon: Icon(
                      Icons.file_download_outlined,
                      size: 15,
                      color: widget.isMine ? textColor : primaryAccent,
                    ),
                    label: Text(
                      'تصدير النتائج',
                      style: TextStyle(
                        color: widget.isMine ? textColor : primaryAccent,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
