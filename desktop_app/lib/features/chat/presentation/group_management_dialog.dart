import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../models/chat_models.dart';

class GroupManagementDialog extends ConsumerStatefulWidget {
  const GroupManagementDialog({super.key, required this.conversation});

  final ChatConversation conversation;

  @override
  ConsumerState<GroupManagementDialog> createState() =>
      _GroupManagementDialogState();
}

class _GroupManagementDialogState extends ConsumerState<GroupManagementDialog> {
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
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'اكتب رسالة تظهر لجميع أعضاء المجموعة',
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

  Future<void> _clearPinnedMessage() async {
    final shouldDelete =
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
    if (!shouldDelete) {
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
      child: AlertDialog(
        title: const Text('إدارة المجموعة'),
        content: SizedBox(
          width: 760,
          height: 600,
          child: currentUserId != ownerId
              ? const Center(child: Text('غير مصرح لك بإدارة هذه المجموعة'))
              : Stack(
                  children: [
                    Column(
                      children: [
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _conversation
                                            .pinnedMessage
                                            ?.content
                                            .isNotEmpty ==
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
                                      onPressed: _clearPinnedMessage,
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('حذف'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const TabBar(
                          tabs: [
                            Tab(text: 'الأعضاء'),
                            Tab(text: 'إضافة'),
                            Tab(text: 'المحظورون'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: TabBarView(
                            children: [
                              // Members Tab
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
                                    title: Text(member.displayName),
                                    subtitle: Text(
                                      isOwner
                                          ? 'مالك المجموعة'
                                          : (isAdmin ? 'أدمن' : 'عضو'),
                                    ),
                                    trailing: isOwner
                                        ? null
                                        : Wrap(
                                            spacing: 8,
                                            children: [
                                              OutlinedButton(
                                                onPressed: () => _run(
                                                  () => isAdmin
                                                      ? ref
                                                            .read(
                                                              chatOverviewControllerProvider
                                                                  .notifier,
                                                            )
                                                            .demoteGroupAdmin(
                                                              conversationId:
                                                                  _conversation
                                                                      .id,
                                                              userId: member.id,
                                                            )
                                                      : ref
                                                            .read(
                                                              chatOverviewControllerProvider
                                                                  .notifier,
                                                            )
                                                            .promoteGroupAdmin(
                                                              conversationId:
                                                                  _conversation
                                                                      .id,
                                                              userId: member.id,
                                                            ),
                                                ),
                                                child: Text(
                                                  isAdmin
                                                      ? 'إزالة أدمن'
                                                      : 'جعله أدمن',
                                                ),
                                              ),
                                              OutlinedButton(
                                                onPressed: () => _run(
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
                                                ),
                                                child: const Text('حذف'),
                                              ),
                                              FilledButton.tonal(
                                                onPressed: () => _run(
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
                                                ),
                                                child: const Text('حظر'),
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
                                    child: ListView.builder(
                                      itemCount: addableUsers.length,
                                      itemBuilder: (context, index) {
                                        final user = addableUsers[index];
                                        return CheckboxListTile(
                                          value: _selectedToAdd.contains(
                                            user.id,
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
                              ListView.builder(
                                itemCount: blockedUsers.length,
                                itemBuilder: (context, index) {
                                  final user = blockedUsers[index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
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
                    if (_busy)
                      const Center(child: AppLoadingIndicator(size: 28)),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _conversation),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
