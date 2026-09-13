
const fs = require('fs');
let file = 'mobile_app/lib/features/chat/presentation/chat_home_screen.dart';
let c = fs.readFileSync(file, 'utf8');

const targetRegex = /return OpenContainer\([\s\S]*?openBuilder: \(context, _\) =>\s*ConversationScreen\(conversation: conversation\),\s*closedBuilder: \(context, openContainer\) => Material\(/;
const replacement = \eturn LongPressDraggable<ChatConversation>(
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
          closedBuilder: (context, openContainer) => Material(\;

c = c.replace(targetRegex, replacement);
c = c.replace(/(\n    \);\n  }\n})$/, '\n        ),\n      ),\n    );\n  }\n}');

fs.writeFileSync(file, c, 'utf8');

