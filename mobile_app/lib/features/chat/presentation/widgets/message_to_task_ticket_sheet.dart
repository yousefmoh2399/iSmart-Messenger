import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/utils/formatters.dart';
import '../../../tickets/presentation/tickets_screen.dart';
import '../../../workspace/models/workspace_doc.dart';
import '../../../workspace/presentation/workspace_controller.dart';
import '../../../workspace/presentation/workspace_doc_editor_screen.dart';
import '../../../workspace/presentation/workspace_home_screen.dart';
import '../../models/chat_models.dart';

/// Builds a rich, clean draft from a [ChatMessage] for converting to an IT
/// Support Ticket or a Workspace Task.
class ChatMessageActionDraft {
  const ChatMessageActionDraft({
    required this.suggestedTitle,
    required this.detailedDescription,
    required this.taskContent,
    required this.metadataSummary,
    this.attachmentLabel,
  });

  final String suggestedTitle;
  final String detailedDescription;
  final String taskContent;
  final String metadataSummary;
  final String? attachmentLabel;

  factory ChatMessageActionDraft.fromMessage({
    required ChatMessage message,
    required String conversationTitle,
  }) {
    final senderName = (message.sender?.displayName.trim().isNotEmpty == true)
        ? message.sender!.displayName.trim()
        : 'مرسل في المحادثة';
    final timeStr = DateFormat(
      'yyyy/MM/dd - hh:mm a',
      'ar',
    ).format(message.createdAt.toLocal());

    final rawText = message.content.trim();
    String? attachmentLabel;
    if (message.hasAttachment) {
      final fName = message.fileName?.trim() ?? '';
      final sizeStr =
          (message.fileSize != null && message.fileSize! > 0)
              ? ' (${formatFileSize(message.fileSize!)})'
              : '';
      if (message.isImageMessage) {
        attachmentLabel =
            fName.isNotEmpty ? 'صورة: $fName$sizeStr' : 'صورة مرفقة$sizeStr';
      } else if (message.isAudioMessage) {
        attachmentLabel = 'تسجيل صوتي مرفق$sizeStr';
      } else {
        attachmentLabel =
            fName.isNotEmpty ? 'ملف: $fName$sizeStr' : 'مرفق$sizeStr';
      }
    }

    // Build a concise suggested title (>= 4 chars)
    String suggestedTitle;
    if (rawText.isNotEmpty) {
      final firstLine = rawText.split('\n').first.trim();
      suggestedTitle = firstLine.length > 55
          ? '${firstLine.substring(0, 55)}...'
          : firstLine;
      if (suggestedTitle.length < 4) {
        suggestedTitle = 'بلاغ من المحادثة: $suggestedTitle';
      }
    } else if (message.isImageMessage) {
      suggestedTitle = 'بلاغ مصوّر من $senderName ($conversationTitle)';
    } else if (attachmentLabel != null) {
      suggestedTitle = 'مرفق للمتابعة من $senderName ($conversationTitle)';
    } else {
      suggestedTitle = 'متابعة رسالة من $senderName ($conversationTitle)';
    }

    // Build detailed description for Ticket
    final descBuffer = StringBuffer();
    if (rawText.isNotEmpty) {
      descBuffer.writeln(rawText);
      descBuffer.writeln();
    } else if (attachmentLabel != null) {
      descBuffer.writeln('تم تحويل هذا المرفق من المحادثة للمتابعة والدعم الفني.');
      descBuffer.writeln();
    }

    descBuffer.writeln('────────────────────');
    descBuffer.writeln('📌 بيانات الرسالة المحوّلة:');
    descBuffer.writeln('• المرسل: $senderName');
    descBuffer.writeln('• المحادثة: $conversationTitle');
    descBuffer.writeln('• وقت الرسالة: $timeStr');
    if (attachmentLabel != null) {
      descBuffer.writeln('• المرفق: $attachmentLabel');
      if (message.fileUrl != null && message.fileUrl!.trim().isNotEmpty) {
        descBuffer.writeln('• رابط المرفق: ${message.fileUrl!.trim()}');
      }
    }

    // Copy to clipboard automatically so user also has it on clipboard
    final fullDescription = descBuffer.toString().trim();

    final taskText = rawText.isNotEmpty
        ? rawText
        : (attachmentLabel ?? suggestedTitle);

    final metaSummary =
        'من: $senderName • المحادثة: $conversationTitle • $timeStr'
        '${attachmentLabel != null ? " • 📎 $attachmentLabel" : ""}';

    return ChatMessageActionDraft(
      suggestedTitle: suggestedTitle,
      detailedDescription: fullDescription,
      taskContent: taskText,
      metadataSummary: metaSummary,
      attachmentLabel: attachmentLabel,
    );
  }
}

/// Navigates directly to [TicketsScreen] and opens the Create Ticket dialog
/// pre-populated with the message content, sender info, and attachment details,
/// while also copying the full text to the clipboard for convenience.
Future<void> openMessageToTicketFlow({
  required BuildContext context,
  required ChatMessage message,
  required String conversationTitle,
}) async {
  HapticFeedback.mediumImpact();
  final draft = ChatMessageActionDraft.fromMessage(
    message: message,
    conversationTitle: conversationTitle,
  );

  await Clipboard.setData(ClipboardData(text: draft.detailedDescription));

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TicketsScreen(
        initialTab: TicketTab.tickets,
        autoOpenCreateDialog: true,
        initialDraftTitle: draft.suggestedTitle,
        initialDraftDescription: draft.detailedDescription,
        initialDraftPriority: message.isImageMessage ? 'high' : 'normal',
        initialAttachmentInfo: draft.attachmentLabel,
      ),
    ),
  );
}

/// Opens an Apple-style bottom sheet to convert a [ChatMessage] into a task
/// inside the user's Workspace (`WorkspaceHomeScreen` / `WorkspaceDocEditorScreen`),
/// allowing the user to customize the task text, add notes, and choose whether
/// to add it to an existing Workspace page or create a new task page.
Future<void> showAddMessageToWorkspaceTaskSheet({
  required BuildContext context,
  required WidgetRef ref,
  required ChatMessage message,
  required String conversationTitle,
}) async {
  HapticFeedback.mediumImpact();
  final draft = ChatMessageActionDraft.fromMessage(
    message: message,
    conversationTitle: conversationTitle,
  );

  await Clipboard.setData(ClipboardData(text: draft.taskContent));

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MessageToWorkspaceTaskSheet(
      draft: draft,
      conversationTitle: conversationTitle,
    ),
  );
}

class _MessageToWorkspaceTaskSheet extends ConsumerStatefulWidget {
  const _MessageToWorkspaceTaskSheet({
    required this.draft,
    required this.conversationTitle,
  });

  final ChatMessageActionDraft draft;
  final String conversationTitle;

  @override
  ConsumerState<_MessageToWorkspaceTaskSheet> createState() =>
      _MessageToWorkspaceTaskSheetState();
}

class _MessageToWorkspaceTaskSheetState
    extends ConsumerState<_MessageToWorkspaceTaskSheet> {
  late final TextEditingController _taskTitleController;
  late final TextEditingController _noteController;
  String? _selectedDocId; // null => Add to default "مهام المتابعة من المحادثات" or create new
  bool _createNewPage = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _taskTitleController = TextEditingController(text: widget.draft.taskContent);
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _taskTitleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _saveTask({required bool openEditorAfter}) async {
    final taskText = _taskTitleController.text.trim();
    if (taskText.isEmpty) return;

    setState(() => _saving = true);
    HapticFeedback.mediumImpact();

    final notifier = ref.read(workspaceDocsProvider.notifier);
    final docs = ref.read(workspaceDocsProvider).valueOrNull ?? <WorkspaceDoc>[];
    final extraNote = _noteController.text.trim();

    final newTodoBlock = WorkspaceBlock(
      type: WorkspaceBlockType.todo,
      content: taskText,
      isChecked: false,
    );
    final metaCalloutBlock = WorkspaceBlock(
      type: WorkspaceBlockType.callout,
      calloutIcon: widget.draft.attachmentLabel != null ? '📎' : '💬',
      content: [
        widget.draft.metadataSummary,
        if (extraNote.isNotEmpty) 'ملاحظة: $extraNote',
      ].join('\n'),
    );

    WorkspaceDoc targetDoc;

    if (_createNewPage) {
      final pageTitle = taskText.split('\n').first.trim();
      targetDoc = await notifier.createDoc(
        title: pageTitle.length > 42
            ? '${pageTitle.substring(0, 42)}...'
            : pageTitle,
        icon: '✅',
        coverColor: '0xFFDCFCE7',
        category: 'مهام الفرع',
        blocks: [
          WorkspaceBlock(
            type: WorkspaceBlockType.heading2,
            content: 'مهمة محوّلة من المحادثة',
          ),
          newTodoBlock,
          metaCalloutBlock,
          WorkspaceBlock(
            type: WorkspaceBlockType.text,
            content: '',
          ),
        ],
      );
    } else {
      WorkspaceDoc? existing;
      if (_selectedDocId != null) {
        existing = docs.where((d) => d.id == _selectedDocId).firstOrNull;
      } else {
        existing = docs
            .where((d) => d.title == 'مهام المتابعة من المحادثات')
            .firstOrNull;
      }

      if (existing != null) {
        existing.blocks.insertAll(0, [
          newTodoBlock,
          metaCalloutBlock,
        ]);
        await notifier.updateDoc(existing);
        targetDoc = existing;
      } else {
        targetDoc = await notifier.createDoc(
          title: 'مهام المتابعة من المحادثات',
          icon: '📋',
          coverColor: '0xFFE0F2FE',
          category: 'مهام الفرع',
          blocks: [
            newTodoBlock,
            metaCalloutBlock,
          ],
        );
      }
    }

    if (!mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    navigator.pop();

    if (openEditorAfter) {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => WorkspaceDocEditorScreen(doc: targetDoc),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('تمت إضافة المهمة إلى "${targetDoc.title}" بنجاح'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'فتح مساحة العمل',
            onPressed: () {
              navigator.push(
                MaterialPageRoute(
                  builder: (_) => const WorkspaceHomeScreen(),
                ),
              );
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? Colors.white60 : const Color(0xFF64748B);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final docs = ref.watch(workspaceDocsProvider).valueOrNull ?? <WorkspaceDoc>[];

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black26,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF34C759).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        CupertinoIcons.checkmark_rectangle_fill,
                        color: Color(0xFF34C759),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إضافة إلى مهامي في مساحة العمل',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'تم نسخ النص والمرفق تلقائياً — عدّل أو أضف تفاصيلك',
                            style: TextStyle(
                              fontSize: 12,
                              color: subColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Source metadata badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.chat_bubble_text_fill,
                        size: 16,
                        color: Color(0xFF007AFF),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.draft.metadataSummary,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? const Color(0xFF93C5FD)
                                : const Color(0xFF1E40AF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Task content field
                Text(
                  'عنوان وتفاصيل المهمة',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: subColor,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: TextField(
                    controller: _taskTitleController,
                    minLines: 2,
                    maxLines: 5,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: 'اكتب نص المهمة...',
                      hintStyle: TextStyle(color: subColor, fontSize: 13),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Extra note
                Text(
                  'ملاحظة إضافية أو خطوة مطلوبة (اختياري)',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: subColor,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _noteController,
                    style: TextStyle(fontSize: 13.5, color: textColor),
                    decoration: InputDecoration(
                      hintText: 'مثال: التواصل مع العميل أو مراجعة الفرع...',
                      hintStyle: TextStyle(color: subColor, fontSize: 12.5),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Destination selector
                Text(
                  'مكان الحفظ في مساحة العمل',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: subColor,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _createNewPage = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: !_createNewPage
                                ? const Color(0xFF34C759).withValues(alpha: 0.14)
                                : cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: !_createNewPage
                                  ? const Color(0xFF34C759)
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.list_bullet_below_rectangle,
                                size: 16,
                                color: !_createNewPage
                                    ? const Color(0xFF34C759)
                                    : subColor,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'قائمة مهامي الحالية',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: !_createNewPage
                                        ? const Color(0xFF34C759)
                                        : textColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _createNewPage = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _createNewPage
                                ? const Color(0xFF007AFF).withValues(alpha: 0.14)
                                : cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _createNewPage
                                  ? const Color(0xFF007AFF)
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.doc_append,
                                size: 16,
                                color: _createNewPage
                                    ? const Color(0xFF007AFF)
                                    : subColor,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'صفحة مشروع جديدة',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: _createNewPage
                                        ? const Color(0xFF007AFF)
                                        : textColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                if (!_createNewPage && docs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _selectedDocId,
                        isExpanded: true,
                        dropdownColor: cardColor,
                        hint: Text(
                          '📋 مهام المتابعة من المحادثات (افتراضي)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              '📋 مهام المتابعة من المحادثات (تلقائي)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                              ),
                            ),
                          ),
                          ...docs.map(
                            (doc) => DropdownMenuItem<String?>(
                              value: doc.id,
                              child: Text(
                                '${doc.icon} ${doc.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: textColor,
                                ),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (val) => setState(() => _selectedDocId = val),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _saveTask(openEditorAfter: false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        icon: const Icon(
                          CupertinoIcons.checkmark_alt,
                          size: 17,
                        ),
                        label: const Text(
                          'حفظ سريع',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _saveTask(openEditorAfter: true),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF34C759),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        icon: const Icon(
                          CupertinoIcons.arrow_up_left_square_fill,
                          size: 17,
                        ),
                        label: const Text(
                          'حفظ وفتح في مساحة العمل',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
