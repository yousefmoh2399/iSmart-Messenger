// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:intl/intl.dart';

// import '../../../../shared/models/app_user.dart';
// import '../../../../shared/providers/providers.dart';
// import '../../models/chat_models.dart';
// import 'chat_ui_helpers.dart';

// class RightPanel extends ConsumerWidget {
//   const RightPanel({
//     super.key,
//     required this.conversation,
//     required this.currentUser,
//     required this.onClose,
//     required this.onTogglePinned,
//     required this.onToggleMuted,
//     required this.onToggleArchived,
//     required this.onDeleteConversation,
//     required this.onOpenGroupManagement,
//   });

//   final ChatConversation conversation;
//   final AppUser? currentUser;
//   final VoidCallback onClose;
//   final VoidCallback onTogglePinned;
//   final VoidCallback onToggleMuted;
//   final VoidCallback onToggleArchived;
//   final VoidCallback onDeleteConversation;
//   final VoidCallback onOpenGroupManagement;

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final messages =
//         ref
//             .watch(conversationMessagesControllerProvider(conversation.id))
//             .valueOrNull
//             ?.messages ??
//         const <ChatMessage>[];
//     final sharedFiles = messages
//         .where((message) => message.hasAttachment && !message.isDeleted)
//         .toList()
//         .reversed
//         .take(10)
//         .toList();

//     final isOwner = conversation.createdBy == currentUser?.id;
//     final isConversationAdmin = conversation.admins.any(
//       (entry) => entry.id == currentUser?.id,
//     );
//     final canManage =
//         isOwner || isConversationAdmin || currentUser?.role == 'admin';

//     return Container(
//       color: Theme.of(context).colorScheme.surface,
//       child: Column(
//         children: [
//           Padding(
//             padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
//             child: Row(
//               children: [
//                 Expanded(
//                   child: Text(
//                     'Info',
//                     style: Theme.of(context).textTheme.titleMedium?.copyWith(
//                       fontWeight: FontWeight.w700,
//                     ),
//                   ),
//                 ),
//                 IconButton(
//                   tooltip: 'Close',
//                   onPressed: onClose,
//                   icon: const Icon(Icons.close_rounded),
//                 ),
//               ],
//             ),
//           ),
//           const Divider(height: 1),
//           Expanded(
//             child: ListView(
//               padding: const EdgeInsets.all(12),
//               children: [
//                 _SectionCard(
//                   title: conversation.displayTitle(currentUser?.id ?? ''),
//                   subtitle: conversation.description.isEmpty
//                       ? _conversationSubtitle(conversation.type)
//                       : conversation.description,
//                   trailing: CircleAvatar(
//                     radius: 18,
//                     backgroundColor: conversationTypeAccent(
//                       conversation.type,
//                     ).withValues(alpha: 0.18),
//                     child: Icon(
//                       conversationTypeIcon(conversation.type),
//                       color: conversationTypeAccent(conversation.type),
//                     ),
//                   ),
//                 ),
//                 const SizedBox(height: 12),
//                 _SectionTitle(
//                   title: 'Members (${conversation.members.length})',
//                   trailing: canManage && conversation.type == 'group'
//                       ? TextButton(
//                           onPressed: onOpenGroupManagement,
//                           child: const Text('Manage'),
//                         )
//                       : null,
//                 ),
//                 const SizedBox(height: 8),
//                 ...conversation.members.map(
//                   (member) => _MemberTile(member: member),
//                 ),
//                 const SizedBox(height: 14),
//                 _SectionTitle(title: 'Shared files'),
//                 const SizedBox(height: 8),
//                 if (sharedFiles.isEmpty)
//                   const Text('No files shared yet')
//                 else
//                   ...sharedFiles.map((message) => _FileTile(message: message)),
//                 if (canManage) ...[
//                   const SizedBox(height: 14),
//                   _SectionTitle(title: 'Conversation controls'),
//                   const SizedBox(height: 8),
//                   _ActionTile(
//                     icon: conversation.isPinned
//                         ? Icons.push_pin_rounded
//                         : Icons.push_pin_outlined,
//                     label: conversation.isPinned
//                         ? 'Unpin conversation'
//                         : 'Pin conversation',
//                     onTap: onTogglePinned,
//                   ),
//                   _ActionTile(
//                     icon: conversation.isMuted
//                         ? Icons.volume_up_outlined
//                         : Icons.volume_off_outlined,
//                     label: conversation.isMuted
//                         ? 'Unmute conversation'
//                         : 'Mute conversation',
//                     onTap: onToggleMuted,
//                   ),
//                   _ActionTile(
//                     icon: conversation.isArchived
//                         ? Icons.unarchive_outlined
//                         : Icons.archive_outlined,
//                     label: conversation.isArchived
//                         ? 'Unarchive conversation'
//                         : 'Archive conversation',
//                     onTap: onToggleArchived,
//                   ),
//                   _ActionTile(
//                     icon: Icons.delete_outline_rounded,
//                     label: 'Delete conversation',
//                     danger: true,
//                     onTap: onDeleteConversation,
//                   ),
//                 ],
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _SectionCard extends StatelessWidget {
//   const _SectionCard({
//     required this.title,
//     required this.subtitle,
//     required this.trailing,
//   });

//   final String title;
//   final String subtitle;
//   final Widget trailing;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.all(10),
//       decoration: BoxDecoration(
//         color: const Color(0xFFF6F9FC),
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(color: const Color(0xFFDDE5EE)),
//       ),
//       child: Row(
//         children: [
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   title,
//                   style: Theme.of(
//                     context,
//                   ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   subtitle,
//                   style: Theme.of(context).textTheme.bodySmall?.copyWith(
//                     color: Theme.of(context).colorScheme.onSurfaceVariant,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           const SizedBox(width: 10),
//           trailing,
//         ],
//       ),
//     );
//   }
// }

// class _SectionTitle extends StatelessWidget {
//   const _SectionTitle({required this.title, this.trailing});

//   final String title;
//   final Widget? trailing;

//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       children: [
//         Expanded(
//           child: Text(
//             title,
//             style: Theme.of(context).textTheme.labelLarge?.copyWith(
//               fontWeight: FontWeight.w700,
//               color: const Color(0xFF425466),
//             ),
//           ),
//         ),
//         if (trailing != null) trailing!,
//       ],
//     );
//   }
// }

// class _MemberTile extends StatelessWidget {
//   const _MemberTile({required this.member});

//   final ChatDirectoryUser member;

//   @override
//   Widget build(BuildContext context) {
//     return ListTile(
//       dense: true,
//       contentPadding: const EdgeInsets.symmetric(horizontal: 4),
//       leading: Stack(
//         children: [
//           CircleAvatar(
//             radius: 16,
//             backgroundColor: const Color(0xFFDDE8F5),
//             backgroundImage:
//                 member.avatarUrl != null && member.avatarUrl!.isNotEmpty
//                 ? NetworkImage(member.avatarUrl!)
//                 : null,
//             child: member.avatarUrl != null && member.avatarUrl!.isNotEmpty
//                 ? null
//                 : Text(_firstCharacter(member.displayName).toUpperCase()),
//           ),
//           Positioned(
//             bottom: 0,
//             left: 0,
//             child: Container(
//               width: 9,
//               height: 9,
//               decoration: BoxDecoration(
//                 color: presenceColor(member.presenceStatus),
//                 borderRadius: BorderRadius.circular(999),
//                 border: Border.all(color: Colors.white, width: 1.8),
//               ),
//             ),
//           ),
//         ],
//       ),
//       title: Text(
//         member.displayName,
//         maxLines: 1,
//         overflow: TextOverflow.ellipsis,
//       ),
//       subtitle: Text(
//         formatPresenceLabel(member),
//         maxLines: 1,
//         overflow: TextOverflow.ellipsis,
//       ),
//     );
//   }
// }

// String _firstCharacter(String value) {
//   final trimmed = value.trim();
//   if (trimmed.isEmpty) {
//     return '?';
//   }
//   return trimmed.substring(0, 1);
// }

// class _FileTile extends StatelessWidget {
//   const _FileTile({required this.message});

//   final ChatMessage message;

//   @override
//   Widget build(BuildContext context) {
//     final isPdf = message.messageType == 'pdf';
//     return ListTile(
//       dense: true,
//       contentPadding: const EdgeInsets.symmetric(horizontal: 4),
//       leading: Icon(
//         isPdf ? Icons.picture_as_pdf_outlined : Icons.attach_file_rounded,
//       ),
//       title: Text(
//         message.fileName ?? 'Attachment',
//         maxLines: 1,
//         overflow: TextOverflow.ellipsis,
//       ),
//       subtitle: Text(
//         DateFormat('dd/MM/yyyy HH:mm').format(message.createdAt.toLocal()),
//       ),
//     );
//   }
// }

// class _ActionTile extends StatelessWidget {
//   const _ActionTile({
//     required this.icon,
//     required this.label,
//     required this.onTap,
//     this.danger = false,
//   });

//   final IconData icon;
//   final String label;
//   final VoidCallback onTap;
//   final bool danger;

//   @override
//   Widget build(BuildContext context) {
//     final color = danger ? const Color(0xFFC0392B) : const Color(0xFF2D3E50);
//     return ListTile(
//       dense: true,
//       contentPadding: const EdgeInsets.symmetric(horizontal: 4),
//       leading: Icon(icon, color: color),
//       title: Text(label, style: TextStyle(color: color)),
//       onTap: onTap,
//     );
//   }
// }

// String _conversationSubtitle(String type) => switch (type) {
//   'direct' => 'Private conversation',
//   'group' => 'Group chat',
//   'department' => 'Department room',
//   'broadcast' => 'Announcement channel',
//   _ => 'Conversation',
// };
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:open_filex/open_filex.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/providers/providers.dart';
import '../../../../shared/widgets/safe_network_avatar.dart';
import '../../models/chat_models.dart';
import 'authenticated_attachment_image.dart';
import 'chat_ui_helpers.dart';

class RightPanel extends ConsumerWidget {
  const RightPanel({
    super.key,
    required this.conversation,
    required this.currentUser,
    required this.onClose,
    required this.onTogglePinned,
    required this.onToggleMuted,
    required this.onToggleArchived,
    required this.onDeleteConversation,
    required this.onOpenGroupManagement,
  });

  final ChatConversation conversation;
  final AppUser? currentUser;
  final VoidCallback onClose;
  final VoidCallback onTogglePinned;
  final VoidCallback onToggleMuted;
  final VoidCallback onToggleArchived;
  final VoidCallback onDeleteConversation;
  final VoidCallback onOpenGroupManagement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final messages =
        ref
            .watch(conversationMessagesControllerProvider(conversation.id))
            .valueOrNull
            ?.messages ??
        const <ChatMessage>[];
    final sharedImages = messages
        .where(
          (m) => m.hasAttachment && !m.isDeleted && m.messageType == 'image',
        )
        .toList()
        .reversed
        .take(12)
        .toList();

    final allSharedFiles = messages
        .where(
          (m) => m.hasAttachment && !m.isDeleted && m.messageType != 'image',
        )
        .toList()
        .reversed
        .toList();
    final sharedFiles = allSharedFiles.take(5).toList();

    final isOwner = conversation.createdBy == currentUser?.id;
    final isConversationAdmin = conversation.admins.any(
      (e) => e.id == currentUser?.id,
    );
    final canManage =
        isOwner || isConversationAdmin || currentUser?.role == 'admin';

    // ── Telegram right-panel colours ────────────────────────────────────────
    final panelBg = isDark ? const Color(0xFF212121) : Colors.white;
    final divColor = isDark ? const Color(0xFF2B2B2B) : const Color(0xFFE8EAED);

    return ColoredBox(
      color: panelBg,
      child: Column(
        children: [
          // ── Header ─────────────────────────────────────────────────────────
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: panelBg,
              border: Border(bottom: BorderSide(color: divColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'معلومات المحادثة',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isDark ? Colors.white : const Color(0xFF1C2B3A),
                    ),
                  ),
                ),
                _TgIconBtn(
                  icon: Icons.close_rounded,
                  tooltip: 'إغلاق',
                  isDark: isDark,
                  onPressed: onClose,
                ),
              ],
            ),
          ),

          // ── Body ───────────────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                // ── Conversation identity card ──────────────────────────────
                _IdentityCard(
                  conversation: conversation,
                  currentUser: currentUser,
                  isDark: isDark,
                ),

                _Divider(isDark: isDark),

                // ── Members ─────────────────────────────────────────────────
                _SectionHeader(
                  label: 'الأعضاء (${conversation.members.length})',
                  isDark: isDark,
                  action: canManage && conversation.type == 'group'
                      ? _TgTextButton(
                          label: 'إدارة',
                          onPressed: onOpenGroupManagement,
                        )
                      : null,
                ),
                ...conversation.members.map(
                  (member) => _MemberTile(member: member, isDark: isDark),
                ),

                _Divider(isDark: isDark),

                _SectionHeader(label: 'المعرض', isDark: isDark),
                if (sharedImages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text(
                      'لا توجد صور مشتركة بعد',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.white38
                            : const Color(0xFFADB5BD),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: sharedImages.length,
                      itemBuilder: (context, index) {
                        final message = sharedImages[index];
                        return InkWell(
                          onTap: () => _showImagePreview(context, ref, message),
                          borderRadius: BorderRadius.circular(14),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                AuthenticatedAttachmentImage(
                                  message: message,
                                  fit: BoxFit.cover,
                                ),
                                PositionedDirectional(
                                  top: 6,
                                  end: 6,
                                  child: message.attachmentDownloadAllowed
                                      ? IconButton.filledTonal(
                                          onPressed: () =>
                                              _downloadAttachmentFromPanel(
                                                context,
                                                ref,
                                                message,
                                              ),
                                          icon: const Icon(
                                            Icons.download_rounded,
                                            size: 16,
                                          ),
                                          style: IconButton.styleFrom(
                                            backgroundColor: Colors.black
                                                .withValues(alpha: 0.42),
                                            foregroundColor: Colors.white,
                                            minimumSize: const Size(30, 30),
                                            padding: EdgeInsets.zero,
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                _Divider(isDark: isDark),

                // ── Shared files ────────────────────────────────────────────
                _SectionHeader(
                  label: 'الملفات المشتركة',
                  isDark: isDark,
                  action: allSharedFiles.length > sharedFiles.length
                      ? _TgTextButton(
                          label: 'المزيد',
                          onPressed: () => _showSharedFilesGallery(
                            context,
                            ref,
                            allSharedFiles,
                            isDark,
                          ),
                        )
                      : null,
                ),
                if (sharedFiles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text(
                      'لا توجد ملفات مشتركة بعد',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.white38
                            : const Color(0xFFADB5BD),
                      ),
                    ),
                  )
                else
                  ...sharedFiles.map(
                    (m) => _FileTile(
                      message: m,
                      isDark: isDark,
                      allowDownload: m.attachmentDownloadAllowed,
                      onTap: () {
                        if (!m.attachmentDownloadAllowed) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('هذا الملف للعرض فقط داخل الشات.'),
                            ),
                          );
                          return;
                        }
                        _downloadAttachmentFromPanel(
                          context,
                          ref,
                          m,
                          openAfterDownload: true,
                        );
                      },
                      onDownload: () =>
                          _downloadAttachmentFromPanel(context, ref, m),
                    ),
                  ),
                if (allSharedFiles.length > sharedFiles.length)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'يعرض ${sharedFiles.length} من أصل ${allSharedFiles.length} ملفًا.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white38
                              : const Color(0xFF7A8896),
                        ),
                      ),
                    ),
                  ),

                // ── Controls ────────────────────────────────────────────────
                if (canManage) ...[
                  _Divider(isDark: isDark),
                  _SectionHeader(label: 'إعدادات المحادثة', isDark: isDark),
                  _ActionTile(
                    icon: conversation.isPinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    label: conversation.isPinned
                        ? 'إلغاء التثبيت'
                        : 'تثبيت المحادثة',
                    isDark: isDark,
                    onTap: onTogglePinned,
                  ),
                  _ActionTile(
                    icon: conversation.isMuted
                        ? Icons.volume_up_outlined
                        : Icons.volume_off_outlined,
                    label: conversation.isMuted
                        ? 'تفعيل الإشعارات'
                        : 'كتم الإشعارات',
                    isDark: isDark,
                    onTap: onToggleMuted,
                  ),
                  _ActionTile(
                    icon: conversation.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    label: conversation.isArchived
                        ? 'إلغاء الأرشفة'
                        : 'أرشفة المحادثة',
                    isDark: isDark,
                    onTap: onToggleArchived,
                  ),
                  _ActionTile(
                    icon: Icons.delete_outline_rounded,
                    label: 'حذف المحادثة',
                    isDark: isDark,
                    danger: true,
                    onTap: onDeleteConversation,
                  ),
                ],

                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showImagePreview(
  BuildContext context,
  WidgetRef ref,
  ChatMessage message,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              child: AuthenticatedAttachmentImage(
                message: message,
                fit: BoxFit.contain,
              ),
            ),
          ),
          PositionedDirectional(
            top: 18,
            start: 18,
            child: IconButton.filledTonal(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          PositionedDirectional(
            top: 18,
            end: 18,
            child: message.attachmentDownloadAllowed
                ? IconButton.filledTonal(
                    onPressed: () =>
                        _downloadAttachmentFromPanel(context, ref, message),
                    icon: const Icon(Icons.download_rounded),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    ),
  );
}

Future<void> _downloadAttachmentFromPanel(
  BuildContext context,
  WidgetRef ref,
  ChatMessage message, {
  bool openAfterDownload = false,
}) async {
  if (!message.attachmentDownloadAllowed) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('هذا المرفق للعرض فقط. المرسل منع التحميل.'),
      ),
    );
    return;
  }
  try {
    final localPath = await ref
        .read(chatRepositoryProvider)
        .downloadAttachment(message);

    if (!context.mounted) {
      return;
    }

    if (openAfterDownload) {
      await OpenFilex.open(localPath);
      return;
    }

    final suggestedName = p.basename(message.fileName ?? 'attachment');
    final destinationPath = await FilePicker.platform.saveFile(
      dialogTitle: 'حفظ الملف',
      fileName: suggestedName,
      lockParentWindow: true,
    );

    if (destinationPath == null || destinationPath.trim().isEmpty) {
      return;
    }

    await File(localPath).copy(destinationPath);

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ ${message.fileName ?? 'المرفق'} بنجاح')),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }
}

Future<void> _showSharedFilesGallery(
  BuildContext context,
  WidgetRef ref,
  List<ChatMessage> files,
  bool isDark,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'معرض الملفات المشتركة',
                          style: Theme.of(dialogContext).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${files.length} ملفًا داخل هذه المحادثة',
                          style: Theme.of(dialogContext).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  dialogContext,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: files.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final message = files[index];
                  return _FileTile(
                    message: message,
                    isDark: isDark,
                    allowDownload: message.attachmentDownloadAllowed,
                    onTap: () {
                      if (!message.attachmentDownloadAllowed) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content: Text('هذا الملف للعرض فقط داخل الشات.'),
                          ),
                        );
                        return;
                      }
                      _downloadAttachmentFromPanel(
                        dialogContext,
                        ref,
                        message,
                        openAfterDownload: true,
                      );
                    },
                    onDownload: () => _downloadAttachmentFromPanel(
                      dialogContext,
                      ref,
                      message,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Identity card ──────────────────────────────────────────────────────────────
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.conversation,
    required this.currentUser,
    required this.isDark,
  });

  final ChatConversation conversation;
  final AppUser? currentUser;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final title = conversation.displayTitle(currentUser?.id ?? '');
    final subtitle = conversation.description.isEmpty
        ? _conversationSubtitle(conversation.type)
        : conversation.description;
    final accent = conversationTypeAccent(conversation.type);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          // Telegram-style large avatar for info panel
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent.withValues(alpha: 0.9), accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              conversationTypeIcon(conversation.type),
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isDark ? Colors.white : const Color(0xFF1C2B3A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : const Color(0xFF708499),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.isDark,
    this.action,
  });

  final String label;
  final bool isDark;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3390EC),
                letterSpacing: 0.4,
              ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

// ── Member tile ────────────────────────────────────────────────────────────────
class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.isDark});

  final ChatDirectoryUser member;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final nameColor = isDark ? Colors.white : const Color(0xFF1C2B3A);
    final subColor = isDark ? Colors.white38 : const Color(0xFF708499);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          hoverColor: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : const Color(0xFF3390EC).withValues(alpha: 0.05),
          leading: Stack(
            children: [
              SafeNetworkAvatar(
                radius: 17,
                backgroundColor: const Color(0xFF3390EC).withValues(alpha: 0.2),
                imageUrl: member.avatarUrl,
                fallbackText: _firstCharacter(member.displayName).toUpperCase(),
                fallbackTextStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3390EC),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: presenceColor(member.presenceStatus),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? const Color(0xFF212121) : Colors.white,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
          title: Text(
            member.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: nameColor,
            ),
          ),
          subtitle: Text(
            formatPresenceLabel(member),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: subColor),
          ),
        ),
      ),
    );
  }
}

// ── File tile ──────────────────────────────────────────────────────────────────
class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.message,
    required this.isDark,
    required this.allowDownload,
    required this.onTap,
    required this.onDownload,
  });

  final ChatMessage message;
  final bool isDark;
  final bool allowDownload;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final isPdf = message.messageType == 'pdf';
    final isImage = message.messageType == 'image';
    final iconColor = isPdf
        ? const Color(0xFFE53935)
        : (isImage ? const Color(0xFF8B5CF6) : const Color(0xFF3390EC));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          hoverColor: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : const Color(0xFF3390EC).withValues(alpha: 0.05),
          leading:
              isImage && message.fileUrl != null && message.fileUrl!.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AuthenticatedAttachmentImage(
                    message: message,
                    width: 34,
                    height: 34,
                    fit: BoxFit.cover,
                  ),
                )
              : Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isPdf
                        ? Icons.picture_as_pdf_outlined
                        : (isImage
                              ? Icons.image_outlined
                              : Icons.insert_drive_file_outlined),
                    color: iconColor,
                    size: 18,
                  ),
                ),
          title: Text(
            message.fileName ?? 'مرفق',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : const Color(0xFF1C2B3A),
            ),
          ),
          subtitle: Text(
            DateFormat(
              'dd/MM/yyyy • HH:mm',
            ).format(message.createdAt.toLocal()),
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : const Color(0xFFADB5BD),
            ),
          ),
          trailing: IconButton(
            onPressed: allowDownload ? onDownload : null,
            tooltip: allowDownload ? 'تنزيل' : 'عرض فقط',
            icon: Icon(
              allowDownload ? Icons.download_rounded : Icons.lock_rounded,
              size: 18,
              color: isDark ? Colors.white38 : const Color(0xFF708499),
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

// ── Action tile ────────────────────────────────────────────────────────────────
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? const Color(0xFFE53935)
        : (isDark ? Colors.white70 : const Color(0xFF2D3E50));
    final hoverBg = danger
        ? const Color(0xFFE53935).withValues(alpha: 0.06)
        : (isDark
              ? Colors.white.withValues(alpha: 0.04)
              : const Color(0xFF3390EC).withValues(alpha: 0.05));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          hoverColor: hoverBg,
          leading: Icon(icon, color: color, size: 20),
          title: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

// ── Divider ────────────────────────────────────────────────────────────────────
class _Divider extends StatelessWidget {
  const _Divider({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: isDark ? const Color(0xFF2B2B2B) : const Color(0xFFE8EAED),
    );
  }
}

// ── Text button ────────────────────────────────────────────────────────────────
class _TgTextButton extends StatelessWidget {
  const _TgTextButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF3390EC),
        ),
      ),
    );
  }
}

// ── Icon button ────────────────────────────────────────────────────────────────
class _TgIconBtn extends StatelessWidget {
  const _TgIconBtn({
    required this.icon,
    required this.onPressed,
    required this.isDark,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool isDark;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(
            icon,
            size: 20,
            color: isDark ? Colors.white60 : const Color(0xFF708499),
          ),
        ),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────
String _firstCharacter(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '؟';
  return trimmed.substring(0, 1);
}

String _conversationSubtitle(String type) => switch (type) {
  'direct' => 'محادثة خاصة',
  'group' => 'محادثة جماعية',
  'department' => 'غرفة القسم',
  'broadcast' => 'قناة إعلانات',
  _ => 'محادثة',
};
