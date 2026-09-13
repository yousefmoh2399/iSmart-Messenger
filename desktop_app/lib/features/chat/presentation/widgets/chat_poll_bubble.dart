import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/chat_models.dart';
import '../../../../shared/providers/providers.dart';

class ChatPollBubble extends ConsumerStatefulWidget {
  const ChatPollBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.onVote,
    required this.onExport,
  });

  final ChatMessage message;
  final bool isMine;
  final void Function(List<String> optionIds) onVote;
  final VoidCallback onExport;

  @override
  ConsumerState<ChatPollBubble> createState() => _ChatPollBubbleState();
}

class _ChatPollBubbleState extends ConsumerState<ChatPollBubble> {
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final metadata = widget.message.metadata ?? {};
    final question = metadata['question'] as String? ?? '??????? ???';
    final options = (metadata['options'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().toList();
    final votes = metadata['votes'] as Map<String, dynamic>? ?? {};
    final isMultipleChoice = metadata['isMultipleChoice'] == true;
    final isAnonymous = metadata['isAnonymous'] == true;
    final isClosed = metadata['isClosed'] == true;

    final authUser = ref.watch(authControllerProvider).user;
    final myId = authUser?.id.toString();

    // Calculate totals
    int totalVotes = 0;
    final myVotedOptionIds = <String>{};
    for (final entry in votes.entries) {
      final voterIds = (entry.value as List<dynamic>? ?? []).map((e) => e.toString()).toList();
      totalVotes += voterIds.length;
      if (myId != null && voterIds.contains(myId)) {
        myVotedOptionIds.add(entry.key);
      }
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textColor = widget.isMine ? colorScheme.onPrimary : colorScheme.onSurface;
    final subTextColor = widget.isMine ? colorScheme.onPrimary.withValues(alpha: 0.8) : colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.isMine ? Colors.transparent : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.poll_rounded, color: textColor, size: 20),
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
            final voterIds = (votes[optId] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
            final count = voterIds.length;
            final percentage = totalVotes > 0 ? count / totalVotes : 0.0;
            final isMyVote = myVotedOptionIds.contains(optId);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: isClosed ? null : () {
                  if (isMultipleChoice) {
                    final newVotes = Set<String>.from(myVotedOptionIds);
                    if (isMyVote) {
                      newVotes.remove(optId);
                    } else {
                      newVotes.add(optId);
                    }
                    widget.onVote(newVotes.toList());
                  } else {
                    widget.onVote([optId]);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isMyVote ? colorScheme.primary : (widget.isMine ? colorScheme.onPrimary.withValues(alpha: 0.3) : colorScheme.outlineVariant),
                      width: isMyVote ? 2 : 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: FractionallySizedBox(
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: percentage,
                          child: Container(
                            color: widget.isMine ? colorScheme.onPrimary.withValues(alpha: 0.15) : colorScheme.primary.withValues(alpha: 0.15),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            if (isMultipleChoice)
                              Icon(
                                isMyVote ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                size: 18,
                                color: isMyVote ? colorScheme.primary : subTextColor,
                              )
                            else
                              Icon(
                                isMyVote ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                size: 18,
                                color: isMyVote ? colorScheme.primary : subTextColor,
                              ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                optText,
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: isMyVote ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (totalVotes > 0)
                              Text(
                                '${(percentage * 100).toStringAsFixed(0)}%',
                                style: TextStyle(
                                  color: subTextColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
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
                '$totalVotes ??? • ${isAnonymous ? '?????' : '????'}',
                style: TextStyle(
                  color: subTextColor,
                  fontSize: 12,
                ),
              ),
              if (widget.isMine || authUser?.role == 'admin')
                TextButton.icon(
                  onPressed: _isExporting ? null : () async {
                    setState(() => _isExporting = true);
                    try {
                      widget.onExport();
                    } finally {
                      if (mounted) {
                        setState(() => _isExporting = false);
                      }
                    }
                  },
                  icon: _isExporting 
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_rounded, size: 14),
                  label: const Text('?????', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: widget.isMine ? colorScheme.onPrimary : colorScheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
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
