import 'package:desktop_app/shared/models/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/providers.dart';
import '../../models/chat_models.dart';

class NewConversationDialog extends ConsumerStatefulWidget {
  const NewConversationDialog({
    super.key,
    required this.currentUser,
    required this.overview,
  });

  final AppUser currentUser;
  final ChatOverviewData overview;

  @override
  ConsumerState<NewConversationDialog> createState() =>
      _NewConversationDialogState();
}

class _NewConversationDialogState extends ConsumerState<NewConversationDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();
  final _selectedMembers = <String>{};
  final _selectedAdmins = <String>{};

  late String _selectedType;
  String? _selectedDirectUserId;
  String? _departmentId;
  String _searchQuery = '';

  late List<String> _availableTypes;

  @override
  void initState() {
    super.initState();
    _departmentId = widget.currentUser.departmentId;

    final canCreateRooms =
        widget.currentUser.role == 'admin' ||
        widget.currentUser.can('canCreateRooms');
    final canSendBroadcast =
        widget.currentUser.role == 'admin' ||
        widget.currentUser.can('canSendBroadcast');

    _availableTypes = <String>[
      'direct',
      'group',
      if (canCreateRooms) 'department',
      if (canSendBroadcast) 'broadcast',
    ];
    _selectedType = _availableTypes.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-fetch overview data if updated
    final currentOverview =
        ref.watch(chatOverviewControllerProvider).valueOrNull ??
        widget.overview;

    // Filter out current user from all users
    final allOtherUsers = currentOverview.users
        .where((entry) => entry.id != widget.currentUser.id)
        .toList();

    // Apply search filter
    final filteredUsers = allOtherUsers.where((user) {
      if (_searchQuery.isEmpty) return true;
      return user.displayName.toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ) ||
          user.username.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text('محادثة جديدة'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width - 48)
              .clamp(320.0, 520.0)
              .toDouble(),
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SizedBox(
          width: (MediaQuery.sizeOf(context).width - 48)
              .clamp(320.0, 520.0)
              .toDouble(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                value: _selectedType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'النوع'),
                items: _availableTypes
                    .map(
                      (type) => DropdownMenuItem<String>(
                        value: type,
                        child: Text(switch (type) {
                          'direct' => 'محادثة مباشرة',
                          'department' => 'غرفة القسم',
                          'broadcast' => 'قناة بث',
                          _ => 'مجموعة',
                        }),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedType = value ?? _selectedType;
                  });
                },
              ),
              const SizedBox(height: 12),

              if (_selectedType == 'direct') ...[
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'ابحث عن مستخدم...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredUsers.length,
                    itemBuilder: (context, index) {
                      final u = filteredUsers[index];
                      return RadioListTile<String>(
                        title: Text(u.displayName),
                        subtitle: Text(u.username),
                        value: u.id,
                        groupValue: _selectedDirectUserId,
                        onChanged: (value) =>
                            setState(() => _selectedDirectUserId = value),
                      );
                    },
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'اسم المحادثة'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'الوصف (اختياري)',
                  ),
                ),
                if (_selectedType == 'department') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _departmentId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'القسم'),
                    items: currentOverview.departments
                        .map(
                          (d) => DropdownMenuItem<String>(
                            value: d.id,
                            child: Text(d.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _departmentId = value),
                  ),
                ],
                if (_selectedType == 'group' ||
                    _selectedType == 'broadcast') ...[
                  const SizedBox(height: 14),
                  Text(
                    _selectedType == 'broadcast' ? 'المرسلون' : 'الأعضاء',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'ابحث عن مستخدم...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredUsers.length,
                      itemBuilder: (context, index) {
                        final u = filteredUsers[index];
                        return CheckboxListTile(
                          value: _selectedMembers.contains(u.id),
                          title: Text(u.displayName),
                          subtitle: Text(u.username),
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                _selectedMembers.add(u.id);
                              } else {
                                _selectedMembers.remove(u.id);
                                _selectedAdmins.remove(u.id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),

                  if (_selectedType == 'broadcast') ...[
                    const SizedBox(height: 10),
                    Text(
                      'المشرفون داخل البث',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 120,
                      child: ListView.builder(
                        itemCount: allOtherUsers
                            .where((u) => _selectedMembers.contains(u.id))
                            .length,
                        itemBuilder: (context, index) {
                          final selectedUsers = allOtherUsers
                              .where((u) => _selectedMembers.contains(u.id))
                              .toList();
                          final u = selectedUsers[index];
                          return CheckboxListTile(
                            value: _selectedAdmins.contains(u.id),
                            title: Text(u.displayName),
                            subtitle: Text(u.username),
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedAdmins.add(u.id);
                                } else {
                                  _selectedAdmins.remove(u.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () async {
            final controller = ref.read(
              chatOverviewControllerProvider.notifier,
            );
            ChatConversation conversation;
            if (_selectedType == 'direct') {
              if (_selectedDirectUserId == null ||
                  _selectedDirectUserId!.isEmpty) {
                return;
              }
              conversation = await controller.createDirectConversation(
                _selectedDirectUserId!,
              );
            } else {
              conversation = await controller.createConversation(
                type: _selectedType,
                name: _nameController.text.trim(),
                description: _descriptionController.text.trim(),
                memberIds: _selectedMembers.toList(),
                adminIds: _selectedAdmins.toList(),
                departmentId: _departmentId,
              );
            }
            if (!context.mounted) return;
            Navigator.of(context).pop(conversation);
          },
          child: const Text('إنشاء'),
        ),
      ],
    );
  }
}
