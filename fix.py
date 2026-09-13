import re

with open('mobile_app/lib/features/chat/presentation/chat_home_screen.dart', 'r', encoding='utf-8') as f:
    c = f.read()

replacement = '''return LongPressDraggable<ChatConversation>(
      data: conversation,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 300,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: accent.withValues(alpha: 0.2),
                child: Icon(Icons.forum, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: OpenContainer(
          transitionType: ContainerTransitionType.fade,
          transitionDuration: const Duration(milliseconds: 280),
          closedColor: Colors.transparent,
          openColor: colorScheme.surface,
          closedElevation: 0,
          openElevation: 0,
          openBuilder: (context, _) =>
              ConversationScreen(conversation: conversation),
          closedBuilder: (context, openContainer) => Material('''

c = re.sub(r'return OpenContainer\([\s\S]*?openBuilder: \(context, _\) =>\s*ConversationScreen\(conversation: conversation\),\s*closedBuilder: \(context, openContainer\) => Material\(', replacement, c)
c = re.sub(r'(\n    \);\n  }\n})$', r'\n        ),\n      ),\n    );\n  }\n}', c)

with open('mobile_app/lib/features/chat/presentation/chat_home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(c)
