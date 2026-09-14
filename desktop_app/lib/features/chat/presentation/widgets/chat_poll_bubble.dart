import 'package:flutter/material.dart';

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

    final question = pollData['question']?.toString() ?? 'استبيان';
    final options = pollData['options'] as List<dynamic>? ?? [];
    final votes = pollData['votes'] as Map<String, dynamic>? ?? {};
    final isMultipleChoice = pollData['isMultipleChoice'] == true;
    final isClosed = pollData['isClosed'] == true;
    final isChecklist = pollData['isChecklist'] == true;

    final uniqueVoters = <String>{};

    votes.forEach((optId, voterList) {
      if (voterList is List) {
        for (var v in voterList) {
          final vid = v.toString();
          uniqueVoters.add(vid);
        }
      }
    });

    final totalVotes = uniqueVoters.length;
    final hasVoted = _selectedOptionIds.isNotEmpty;
    final showResults = (hasVoted || isClosed) && !isChecklist;

    final textColor = widget.isMine
        ? colorScheme.onPrimary
        : colorScheme.onSurface;
    final subTextColor = widget.isMine
        ? colorScheme.onPrimary.withValues(alpha: 0.7)
        : colorScheme.onSurfaceVariant;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isChecklist ? Icons.checklist_rounded : Icons.poll_rounded,
                color: textColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  question,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...options.map((opt) {
            final optId = opt['id'].toString();
            final optText = opt['text'].toString();
            final voterIds = (votes[optId] as List<dynamic>? ?? [])
                .map((e) => e.toString())
                .toList();
            final count = voterIds.length;
            final percentage = totalVotes > 0 ? count / totalVotes : 0.0;
            final isMyVote = _selectedOptionIds.contains(optId);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: isMyVote
                      ? colorScheme.primary.withValues(alpha: 0.10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isMyVote
                        ? colorScheme.primary.withValues(alpha: 0.35)
                        : Colors.transparent,
                  ),
                ),
                child: InkWell(
                  onTap:
                      (isClosed ||
                          (hasVoted && !isMultipleChoice && !isChecklist))
                      ? null
                      : () {
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
                                _selectedOptionIds = _selectedOptionsFrom(
                                  pollData,
                                );
                                _hasPendingVote = false;
                              });
                            }
                          }();
                        },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.transparent,
                    ),
                    child: Stack(
                      children: [
                        if (showResults)
                          Positioned.fill(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0, end: percentage),
                              duration: const Duration(milliseconds: 600),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) {
                                return FractionallySizedBox(
                                  alignment: AlignmentDirectional.centerStart,
                                  widthFactor: value,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: widget.isMine
                                          ? colorScheme.onPrimary.withValues(
                                              alpha: 0.15,
                                            )
                                          : colorScheme.primary.withValues(
                                              alpha: 0.15,
                                            ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 260),
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(scale: anim, child: child),
                                child: AnimatedScale(
                                  key: ValueKey(isMyVote),
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutBack,
                                  scale: isMyVote ? 1.12 : 1.0,
                                  child: Icon(
                                    isMyVote
                                        ? (isChecklist
                                              ? Icons.check_box_rounded
                                              : Icons.check_circle_rounded)
                                        : (isChecklist
                                              ? Icons
                                                    .check_box_outline_blank_rounded
                                              : Icons
                                                    .radio_button_unchecked_rounded),
                                    size: 20,
                                    color: isMyVote
                                        ? colorScheme.primary
                                        : subTextColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  optText,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 14,
                                    fontWeight: isMyVote
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (showResults && !isChecklist) ...[
                                const SizedBox(width: 12),
                                Text(
                                  '${(percentage * 100).toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$totalVotes تصويت',
                style: TextStyle(color: subTextColor, fontSize: 12),
              ),
              if (widget.isMine && totalVotes > 0)
                TextButton.icon(
                  onPressed: widget.onExport,
                  icon: Icon(
                    Icons.download_rounded,
                    size: 16,
                    color: widget.isMine
                        ? colorScheme.onPrimary
                        : colorScheme.primary,
                  ),
                  label: Text(
                    'تصدير',
                    style: TextStyle(
                      color: widget.isMine
                          ? colorScheme.onPrimary
                          : colorScheme.primary,
                      fontSize: 12,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 0,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
