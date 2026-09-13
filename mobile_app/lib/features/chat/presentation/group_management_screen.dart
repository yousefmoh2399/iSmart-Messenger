import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import 'widgets/chat_avatar.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../models/chat_models.dart';

class GroupManagementScreen extends ConsumerStatefulWidget {
  const GroupManagementScreen({super.key, required this.conversation});

  final ChatConversation conversation;

  @override
  ConsumerState<GroupManagementScreen> createState() =>
      _GroupManagementScreenState();
}

class _GroupManagementScreenState extends ConsumerState<GroupManagementScreen> {
  late ChatConversation _conversation;
  final Set<String> _selectedToAdd = <String>{};
  bool _busy = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isAdmin(String userId) =>
      _conversation.admins.any((entry) => entry.id == userId);

  Future<void> _run(Future<ChatConversation> Function() task) async {
    setState(() => _busy = true);
    try {
      final updated = await task();
      if (!mounted) return;
      setState(() => _conversation = updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upsertPinnedMessage({required bool edit}) async {
    final currentText = _conversation.pinnedMessage?.content ?? '';
    final controller = TextEditingController(text: edit ? currentText : '');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(edit ? 'تعديل الرسالة المثبتة' : 'إضافة رسالة مثبتة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          minLines: 2,
          decoration: const InputDecoration(
            hintText: 'اكتب الرسالة التي ستظهر لكل أعضاء المجموعة',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (!mounted || value == null || value.isEmpty) {
      return;
    }

    await _run(
      () => ref
          .read(chatOverviewControllerProvider.notifier)
          .setGroupPinnedMessage(
            conversationId: _conversation.id,
            content: value,
          ),
    );
  }

  Future<void> _removePinnedMessage() async {
    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('حذف الرسالة المثبتة'),
            content: const Text('هل تريد حذف الرسالة المثبتة الحالية؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('حذف'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) {
      return;
    }

    await _run(
      () => ref
          .read(chatOverviewControllerProvider.notifier)
          .clearGroupPinnedMessage(conversationId: _conversation.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(chatOverviewControllerProvider).valueOrNull;
    final currentUserId = ref.watch(authControllerProvider).valueOrNull?.id;
    final ownerId = _conversation.createdBy;
    final colorScheme = Theme.of(context).colorScheme;
    if (currentUserId == null || ownerId != currentUserId) {
      return const Scaffold(
        body: Center(child: Text('غير مصرح لك بإدارة هذه المجموعة')),
      );
    }

    final memberIds = _conversation.members.map((entry) => entry.id).toSet();
    final blockedIds = _conversation.blockedMemberIds.toSet();
    final allUsers = overview?.users ?? const <ChatDirectoryUser>[];

    final addableUsers = allUsers.where((user) {
      final isEligible =
          !memberIds.contains(user.id) && !blockedIds.contains(user.id);
      if (!isEligible) return false;
      if (_searchQuery.isEmpty) return true;
      return user.displayName.toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ) ||
          user.username.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    final blockedUsers = _conversation.blockedMembers;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: colorScheme.surfaceContainerLowest,
        appBar: AppBar(
          title: const Text('إدارة المجموعة'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'الأعضاء'),
              Tab(text: 'إضافة'),
              Tab(text: 'المحظورون'),
            ],
          ),
        ),
        body: Stack(
          children: [
            Column(
              children: [
                // Info Header & Pinned Message
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.42),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _conversation.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InfoChip(
                            label: ' عضو',
                            color: const Color(0xFF3390EC),
                          ),
                          _InfoChip(
                            label: ' أدمن',
                            color: const Color(0xFF19A974),
                          ),
                          _InfoChip(
                            label: ' محظور',
                            color: const Color(0xFFF59E0B),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.push_pin_rounded, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'الرسالة المثبتة',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _conversation.pinnedMessage?.content.isNotEmpty ==
                                      true
                                  ? _conversation.pinnedMessage!.content
                                  : 'لا توجد رسالة مثبتة حالياً.',
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: () => _upsertPinnedMessage(
                                    edit:
                                        _conversation.pinnedMessage != null &&
                                        _conversation
                                            .pinnedMessage!
                                            .content
                                            .isNotEmpty,
                                  ),
                                  icon: const Icon(Icons.edit_note_rounded),
                                  label: Text(
                                    _conversation.pinnedMessage == null
                                        ? 'إضافة'
                                        : 'تعديل',
                                  ),
                                ),
                                if (_conversation.pinnedMessage != null)
                                  OutlinedButton.icon(
                                    onPressed: _removePinnedMessage,
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('حذف'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Tabs Content
                Expanded(
                  child: TabBarView(
                    children: [
                      // Current Members Tab
                      ListView.builder(
                        itemCount: _conversation.members.length,
                        itemBuilder: (context, index) {
                          final member = _conversation.members[index];
                          final isOwner = member.id == ownerId;
                          final isAdmin = _isAdmin(member.id);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            leading: CircleAvatar(
                              child: Text(member.displayName.substring(0, 1)),
                            ),
                            title: Text(member.displayName),
                            subtitle: Text(
                              isOwner
                                  ? 'مالك المجموعة'
                                  : (isAdmin ? 'أدمن' : 'عضو'),
                            ),
                            trailing: isOwner
                                ? null
                                : PopupMenuButton<String>(
                                    onSelected: (value) {
                                      switch (value) {
                                        case 'promote':
                                        case 'demote':
                                          _run(
                                            () => isAdmin
                                                ? ref
                                                      .read(
                                                        chatOverviewControllerProvider
                                                            .notifier,
                                                      )
                                                      .demoteGroupAdmin(
                                                        conversationId:
                                                            _conversation.id,
                                                        userId: member.id,
                                                      )
                                                : ref
                                                      .read(
                                                        chatOverviewControllerProvider
                                                            .notifier,
                                                      )
                                                      .promoteGroupAdmin(
                                                        conversationId:
                                                            _conversation.id,
                                                        userId: member.id,
                                                      ),
                                          );
                                          break;
                                        case 'remove':
                                          _run(
                                            () => ref
                                                .read(
                                                  chatOverviewControllerProvider
                                                      .notifier,
                                                )
                                                .removeGroupMember(
                                                  conversationId:
                                                      _conversation.id,
                                                  userId: member.id,
                                                ),
                                          );
                                          break;
                                        case 'block':
                                          _run(
                                            () => ref
                                                .read(
                                                  chatOverviewControllerProvider
                                                      .notifier,
                                                )
                                                .blockGroupMember(
                                                  conversationId:
                                                      _conversation.id,
                                                  userId: member.id,
                                                ),
                                          );
                                          break;
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
                                        value: isAdmin ? 'demote' : 'promote',
                                        child: Text(
                                          isAdmin
                                              ? 'إزالة من الأدمن'
                                              : 'ترقية لأدمن',
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'remove',
                                        child: Text('حذف من المجموعة'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'block',
                                        child: Text('حظر'),
                                      ),
                                    ],
                                  ),
                          );
                        },
                      ),

                      // Add Members Tab
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: TextField(
                              controller: _searchController,
                              decoration: const InputDecoration(
                                hintText: 'ابحث عن جهة اتصال...',
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _searchQuery = val;
                                });
                              },
                            ),
                          ),
                          Expanded(
                            child: addableUsers.isEmpty
                                ? const Center(
                                    child: Text('لا يوجد أشخاص متاحين للإضافة'),
                                  )
                                : ListView.builder(
                                    itemCount: addableUsers.length,
                                    itemBuilder: (context, index) {
                                      final user = addableUsers[index];
                                      return CheckboxListTile(
                                        value: _selectedToAdd.contains(user.id),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 16,
                                            ),
                                        secondary: ChatAvatar(
                                          radius: 20,
                                          backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                                          avatarUrl: user.avatarUrl,
                                          fallback: Text(
                                            user.displayName.isNotEmpty
                                                ? user.displayName.substring(0, 1)
                                                : '',
                                          ),
                                        ),
                                        title: Text(user.displayName),
                                        subtitle: Text(user.username),
                                        onChanged: (value) {
                                          setState(() {
                                            if (value == true) {
                                              _selectedToAdd.add(user.id);
                                            } else {
                                              _selectedToAdd.remove(user.id);
                                            }
                                          });
                                        },
                                      );
                                    },
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: FilledButton.icon(
                              onPressed: _selectedToAdd.isEmpty
                                  ? null
                                  : () =>
                                        _run(
                                          () => ref
                                              .read(
                                                chatOverviewControllerProvider
                                                    .notifier,
                                              )
                                              .addGroupMembers(
                                                conversationId:
                                                    _conversation.id,
                                                userIds: _selectedToAdd
                                                    .toList(),
                                              ),
                                        ).then((_) {
                                          if (mounted) {
                                            setState(() {
                                              _selectedToAdd.clear();
                                              _searchController.clear();
                                              _searchQuery = '';
                                            });
                                          }
                                        }),
                              icon: const Icon(Icons.person_add_alt_1),
                              label: Text('إضافة المحددين ()'),
                            ),
                          ),
                        ],
                      ),

                      // Blocked Tab
                      blockedUsers.isEmpty
                          ? const Center(child: Text('لا يوجد محظورون'))
                          : ListView.builder(
                              itemCount: blockedUsers.length,
                              itemBuilder: (context, index) {
                                final user = blockedUsers[index];
                                return ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.block_outlined),
                                  ),
                                  title: Text(user.displayName),
                                  subtitle: Text(user.username),
                                  trailing: TextButton(
                                    onPressed: () => _run(
                                      () => ref
                                          .read(
                                            chatOverviewControllerProvider
                                                .notifier,
                                          )
                                          .unblockGroupMember(
                                            conversationId: _conversation.id,
                                            userId: user.id,
                                          ),
                                    ),
                                    child: const Text('فك الحظر'),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ],
            ),
            if (_busy) const Center(child: AppLoadingIndicator(size: 28)),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
