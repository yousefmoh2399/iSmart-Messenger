const fs = require('fs');
let content = fs.readFileSync('desktop_app/lib/features/chat/presentation/widgets/message_bubble.dart', 'utf8');

// 1. Add final VoidCallback? onShowDetails;
content = content.replace('final VoidCallback? onPin;', 'final VoidCallback? onPin;\n  final VoidCallback? onShowDetails;');
content = content.replace('this.onPin,', 'this.onPin,\n    this.onShowDetails,');

// 2. Add showDetails to enum
content = content.replace('enum _BubbleMenuAction {\n  react,', 'enum _BubbleMenuAction {\n  react,\n  showDetails,');

// 3. Add to switch in _handleMenuAction
const switchReplacement =       case _BubbleMenuAction.showDetails:
        widget.onShowDetails?.call();
        break;
      case _BubbleMenuAction.react:;
content = content.replace('case _BubbleMenuAction.react:', switchReplacement);

// 4. Add PopupMenuItem
const menuItem =         if (widget.onShowDetails != null)
          const PopupMenuItem(
            value: _BubbleMenuAction.showDetails,
            child: _PopupActionRow(
              icon: Icons.info_outline_rounded,
              label: 'تفاصيل الرسالة',
              color: Color(0xFF3390EC),
            ),
          ),
        if (widget.onEdit != null);
content = content.replace('if (widget.onEdit != null)', menuItem);

fs.writeFileSync('desktop_app/lib/features/chat/presentation/widgets/message_bubble.dart', content, 'utf8');
