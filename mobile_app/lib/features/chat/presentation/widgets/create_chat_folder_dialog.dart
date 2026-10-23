import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat_models.dart';
import '../../providers/chat_folders_provider.dart';

Color resolveFolderColor(ChatFolder folder) {
  if (folder.icon != null && folder.icon!.contains(':')) {
    final parts = folder.icon!.split(':');
    if (parts.length > 1) {
      final hex = parts[1].replaceAll('#', '').trim();
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed != null) {
        return Color(0xFF000000 | parsed);
      }
    }
  }
  const colors = [
    Color(0xFF007AFF), // Apple Blue
    Color(0xFF5856D6), // Apple Indigo
    Color(0xFF34C759), // Apple Green
    Color(0xFFFF9500), // Apple Orange
    Color(0xFFFF2D55), // Apple Pink
    Color(0xFF00C7BE), // Apple Teal
    Color(0xFFFF3B30), // Apple Red
    Color(0xFF5AC8FA), // Light Blue
  ];
  return colors[folder.id.hashCode.abs() % colors.length];
}

IconData resolveFolderIcon(ChatFolder folder) {
  var iconKey = folder.icon ?? 'folder';
  if (iconKey.contains(':')) {
    iconKey = iconKey.split(':').first;
  }
  return getFolderIconData(iconKey);
}

IconData getFolderIconData(String? iconKey) {
  return switch (iconKey) {
    'work' => Icons.business_center_rounded,
    'star' => Icons.star_rounded,
    'group' => Icons.group_rounded,
    'chat' => Icons.chat_bubble_rounded,
    'pin' => Icons.push_pin_rounded,
    'archive' => Icons.archive_rounded,
    'bookmark' => Icons.bookmark_rounded,
    'tag' => Icons.label_rounded,
    'school' => Icons.school_rounded,
    'person' => Icons.person_rounded,
    _ => Icons.folder_rounded,
  };
}

class FolderIconOption {
  const FolderIconOption({
    required this.key,
    required this.icon,
    required this.label,
  });

  final String key;
  final IconData icon;
  final String label;
}

const List<FolderIconOption> kFolderIconOptions = [
  FolderIconOption(key: 'folder', icon: Icons.folder_rounded, label: 'عام'),
  FolderIconOption(
    key: 'work',
    icon: Icons.business_center_rounded,
    label: 'العمل',
  ),
  FolderIconOption(key: 'star', icon: Icons.star_rounded, label: 'مهم'),
  FolderIconOption(
    key: 'chat',
    icon: Icons.chat_bubble_rounded,
    label: 'محادثات',
  ),
  FolderIconOption(key: 'group', icon: Icons.group_rounded, label: 'فريق'),
  FolderIconOption(key: 'pin', icon: Icons.push_pin_rounded, label: 'مثبت'),
  FolderIconOption(key: 'archive', icon: Icons.archive_rounded, label: 'أرشيف'),
  FolderIconOption(
    key: 'bookmark',
    icon: Icons.bookmark_rounded,
    label: 'إشارة',
  ),
  FolderIconOption(key: 'person', icon: Icons.person_rounded, label: 'شخصي'),
  FolderIconOption(key: 'tag', icon: Icons.label_rounded, label: 'تصنيف'),
];

const List<Color> kFolderColorOptions = [
  Color(0xFF007AFF), // Apple Blue
  Color(0xFF5856D6), // Apple Indigo
  Color(0xFF00C7BE), // Apple Teal
  Color(0xFF34C759), // Apple Green
  Color(0xFFFF9500), // Apple Orange
  Color(0xFFFF2D55), // Apple Pink
  Color(0xFFFF3B30), // Apple Red
  Color(0xFF8E8E93), // Apple Slate Grey
];

Future<void> showCreateOrEditChatFolderDialog(
  BuildContext context, {
  ChatFolder? existingFolder,
  List<ChatConversation> availableConversations = const [],
  String? currentUserId,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => CreateChatFolderDialog(
      existingFolder: existingFolder,
      availableConversations: availableConversations,
      currentUserId: currentUserId,
    ),
  );
}

class CreateChatFolderDialog extends ConsumerStatefulWidget {
  const CreateChatFolderDialog({
    super.key,
    this.existingFolder,
    this.availableConversations = const [],
    this.currentUserId,
  });

  final ChatFolder? existingFolder;
  final List<ChatConversation> availableConversations;
  final String? currentUserId;

  @override
  ConsumerState<CreateChatFolderDialog> createState() =>
      _CreateChatFolderDialogState();
}

class _CreateChatFolderDialogState
    extends ConsumerState<CreateChatFolderDialog> {
  late final TextEditingController _nameController;
  late String _selectedIconKey;
  late Color _selectedColor;
  late final Set<String> _selectedConversationIds;
  bool _isSubmitting = false;
  String _conversationSearchQuery = '';

  @override
  void initState() {
    super.initState();
    final folder = widget.existingFolder;
    _nameController = TextEditingController(text: folder?.name ?? '');

    if (folder != null) {
      var iconKey = folder.icon ?? 'folder';
      if (iconKey.contains(':')) {
        iconKey = iconKey.split(':').first;
      }
      _selectedIconKey = iconKey;
      _selectedColor = resolveFolderColor(folder);
      _selectedConversationIds = Set<String>.from(folder.conversationIds);
    } else {
      _selectedIconKey = 'folder';
      _selectedColor = kFolderColorOptions[0];
      _selectedConversationIds = <String>{};
    }

    _nameController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _conversationTitle(ChatConversation conv) {
    if (conv.name.trim().isNotEmpty) return conv.name.trim();
    final currentId = widget.currentUserId ?? '';
    final others = conv.members.where((m) => m.id != currentId).toList();
    if (others.isNotEmpty) return others.first.displayName;
    if (conv.members.isNotEmpty) return conv.members.first.displayName;
    return 'محادثة';
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final hexColor = _selectedColor.toARGB32()
          .toRadixString(16)
          .padLeft(8, '0')
          .substring(2)
          .toUpperCase();
      final iconValue = '$_selectedIconKey:#$hexColor';

      if (widget.existingFolder != null) {
        await ref.read(chatFoldersProvider.notifier).updateFolder(
              widget.existingFolder!.id,
              name: name,
              icon: iconValue,
              conversationIds: _selectedConversationIds.toList(),
            );
      } else {
        await ref.read(chatFoldersProvider.notifier).createFolder(
              name,
              icon: iconValue,
              conversationIds: _selectedConversationIds.toList(),
            );
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حفظ المجلد: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEdit = widget.existingFolder != null;
    final folderName = _nameController.text.trim();
    final currentIconData = getFolderIconData(_selectedIconKey);

    final filteredConversations = widget.availableConversations.where((c) {
      if (_conversationSearchQuery.trim().isEmpty) return true;
      final q = _conversationSearchQuery.trim().toLowerCase();
      final title = _conversationTitle(c).toLowerCase();
      return title.contains(q);
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 440,
        constraints: const BoxConstraints(maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Top Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _selectedColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isEdit
                          ? Icons.edit_note_rounded
                          : Icons.create_new_folder_rounded,
                      color: _selectedColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEdit ? 'تعديل مجلد المحادثات' : 'إنشاء مجلد محادثات جديد',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'نظّم محادثاتك لسهولة الوصول والترتيب السريع',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.white60 : Colors.black45,
                      size: 20,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),

            const Divider(height: 1, thickness: 0.5),

            // ── Scrollable Body ──────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Live Folder Preview Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                        ),
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _selectedColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              currentIconData,
                              color: _selectedColor,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  folderName.isEmpty ? 'اسم المجلد' : folderName,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: folderName.isEmpty
                                        ? (isDark ? Colors.white38 : Colors.black38)
                                        : (isDark ? Colors.white : const Color(0xFF0F172A)),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _selectedColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'مجلد محادثات',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _selectedColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${_selectedConversationIds.length} محادثة محددة',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.white54 : Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 2. Folder Name Input
                    _buildSectionTitle(context, 'اسم المجلد', isDark),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      child: TextField(
                        controller: _nameController,
                        autofocus: true,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          hintText: 'مثال: محادثات الإدارة، العمل، العملاء...',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                          border: InputBorder.none,
                          prefixIcon: Icon(
                            Icons.drive_file_rename_outline_rounded,
                            size: 18,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 32),
                          suffixIcon: _nameController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 16),
                                  onPressed: () => _nameController.clear(),
                                  splashRadius: 14,
                                )
                              : null,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 3. Icon Selector
                    _buildSectionTitle(context, 'أيقونة المجلد', isDark),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kFolderIconOptions.map((opt) {
                        final isSelected = _selectedIconKey == opt.key;
                        return InkWell(
                          onTap: () => setState(() => _selectedIconKey = opt.key),
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _selectedColor.withValues(alpha: 0.14)
                                  : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7)),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? _selectedColor
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  opt.icon,
                                  size: 17,
                                  color: isSelected
                                      ? _selectedColor
                                      : (isDark ? Colors.white70 : Colors.black54),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  opt.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected
                                        ? _selectedColor
                                        : (isDark ? Colors.white70 : Colors.black87),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),

                    // 4. Color Palette
                    _buildSectionTitle(context, 'لون التمييز', isDark),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: kFolderColorOptions.map((c) {
                        final isSelected = _selectedColor.toARGB32() == c.toARGB32();
                        return GestureDetector(
                          onTap: () => setState(() => _selectedColor = c),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(color: Colors.white, width: 2.5)
                                  : null,
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: c.withValues(alpha: 0.5),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        );
                      }).toList(),
                    ),

                    // 5. Optional Initial Conversations Selector
                    if (widget.availableConversations.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildSectionTitle(context, 'محادثات المجلد (اختياري)', isDark),
                          if (_selectedConversationIds.isNotEmpty)
                            TextButton(
                              onPressed: () => setState(() => _selectedConversationIds.clear()),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('إلغاء التحديد', style: TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if (widget.availableConversations.length > 5) ...[
                        Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: TextField(
                            onChanged: (val) => setState(() => _conversationSearchQuery = val),
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                              hintText: 'بحث في المحادثات...',
                              hintStyle: TextStyle(fontSize: 12),
                              border: InputBorder.none,
                              prefixIcon: Icon(Icons.search_rounded, size: 16),
                              prefixIconConstraints: BoxConstraints(minWidth: 26),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      Container(
                        constraints: const BoxConstraints(maxHeight: 140),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: filteredConversations.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 48,
                            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                          ),
                          itemBuilder: (ctx, index) {
                            final conv = filteredConversations[index];
                            final isChecked = _selectedConversationIds.contains(conv.id);

                            return InkWell(
                              onTap: () {
                                setState(() {
                                  if (isChecked) {
                                    _selectedConversationIds.remove(conv.id);
                                  } else {
                                    _selectedConversationIds.add(conv.id);
                                  }
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isChecked
                                          ? Icons.check_box_rounded
                                          : Icons.check_box_outline_blank_rounded,
                                      size: 18,
                                      color: isChecked
                                          ? _selectedColor
                                          : (isDark ? Colors.white38 : Colors.black38),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _conversationTitle(conv),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isChecked ? FontWeight.w600 : FontWeight.w400,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(height: 1, thickness: 0.5),

            // ── Footer Buttons ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'إلغاء',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: folderName.isEmpty || _isSubmitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _selectedColor,
                      disabledBackgroundColor: _selectedColor.withValues(alpha: 0.4),
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            isEdit ? 'حفظ التعديلات' : 'إنشاء المجلد',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white70 : const Color(0xFF475569),
      ),
    );
  }
}
