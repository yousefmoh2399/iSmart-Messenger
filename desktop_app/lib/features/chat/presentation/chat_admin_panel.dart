// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:intl/intl.dart';
// import 'package:open_filex/open_filex.dart';

// import '../../../core/utils/formatters.dart';
// import '../../../shared/models/admin_announcement.dart';
// import '../../../shared/models/managed_user.dart';
// import '../../../shared/models/remote_document.dart';
// import '../../../shared/providers/providers.dart';
// import '../../admin/presentation/backup_screen.dart';
// import '../../admin/presentation/update_management_screen.dart';
// import '../models/chat_models.dart';

// class ChatAdminPanel extends ConsumerStatefulWidget {
//   const ChatAdminPanel({
//     super.key,
//     required this.departments,
//     required this.manageableConversations,
//     required this.users,
//     required this.roles,
//     required this.usersState,
//   });

//   final List<DepartmentSummary> departments;
//   final List<ChatConversation> manageableConversations;
//   final List<ChatDirectoryUser> users;
//   final List<ChatRole> roles;
//   final AsyncValue<List<ManagedUser>> usersState;

//   @override
//   ConsumerState<ChatAdminPanel> createState() => _ChatAdminPanelState();
// }

// class _ChatAdminPanelState extends ConsumerState<ChatAdminPanel> {
//   late Future<_AdminLoadResult<ChatAuditLog>> _auditLogsFuture;
//   late Future<_AdminLoadResult<ChatSystemError>> _systemErrorsFuture;

//   @override
//   void initState() {
//     super.initState();
//     _reloadLogs();
//   }

//   void _reloadLogs() {
//     final controller = ref.read(chatOverviewControllerProvider.notifier);
//     _auditLogsFuture = _safeLoad(
//       () => controller.fetchAuditLogs(limit: 200),
//       emptyMessage: 'لا توجد أحداث إدارية مسجلة',
//     );
//     _systemErrorsFuture = _safeLoad(
//       () => controller.fetchSystemErrors(limit: 200),
//       emptyMessage: 'لا توجد أخطاء نظامية مسجلة',
//     );
//   }

//   Future<_AdminLoadResult<T>> _safeLoad<T>(
//     Future<List<T>> Function() loader, {
//     required String emptyMessage,
//   }) async {
//     try {
//       final items = await loader();
//       return _AdminLoadResult(items: items, emptyMessage: emptyMessage);
//     } catch (error) {
//       return _AdminLoadResult(
//         items: const [],
//         emptyMessage: emptyMessage,
//         errorMessage: error.toString(),
//       );
//     }
//   }

//   Future<void> _refreshAll() async {
//     await ref.read(chatOverviewControllerProvider.notifier).refresh();
//     await ref.read(usersControllerProvider.notifier).refresh();
//     await ref.read(adminAnnouncementsControllerProvider.notifier).refresh();
//     await ref.read(adminDocumentsControllerProvider.notifier).refresh();
//     if (mounted) {
//       setState(_reloadLogs);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return DefaultTabController(
//       length: 10,
//       child: Column(
//         children: [
//           Row(
//             children: [
//               const Expanded(
//                 child: TabBar(
//                   isScrollable: true,
//                   tabs: [
//                     Tab(text: 'الإعلانات'),
//                     Tab(text: 'المستخدمون'),
//                     Tab(text: 'الملفات'),
//                     Tab(text: 'الأقسام'),
//                     Tab(text: 'الغرف'),
//                     Tab(text: 'الصلاحيات'),
//                     Tab(text: 'السجل'),
//                     Tab(text: 'الأخطاء'),
//                     Tab(text: 'التحديث'),
//                     Tab(text: 'النسخ الاحتياطي'),

//                   ],
//                 ),
//               ),
//               IconButton(
//                 onPressed: _refreshAll,
//                 icon: const Icon(Icons.refresh),
//               ),
//             ],
//           ),
//           const SizedBox(height: 12),
//           Expanded(
//             child: TabBarView(
//               children: [
//                 _AnnouncementsAdminTab(
//                   announcementsState: ref.watch(
//                     adminAnnouncementsControllerProvider,
//                   ),
//                 ),
//                 _UsersAdminTab(
//                   departments: widget.departments,
//                   usersState: widget.usersState,
//                 ),
//                 _AdminDocumentsTab(
//                   documentsState: ref.watch(adminDocumentsControllerProvider),
//                 ),
//                 _DepartmentsAdminTab(
//                   departments: widget.departments,
//                   users: widget.users,
//                 ),
//                 _RoomsAdminTab(
//                   conversations: widget.manageableConversations,
//                   users: widget.users,
//                 ),
//                 _RolesAdminTab(roles: widget.roles),
//                 _AuditLogsTab(logsFuture: _auditLogsFuture),
//                 _SystemErrorsTab(errorsFuture: _systemErrorsFuture),
//                 const UpdateManagementScreen(),
//                 const BackupScreen(),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _AdminLoadResult<T> {
//   const _AdminLoadResult({
//     required this.items,
//     required this.emptyMessage,
//     this.errorMessage,
//   });

//   final List<T> items;
//   final String emptyMessage;
//   final String? errorMessage;

//   bool get hasError => errorMessage != null && errorMessage!.trim().isNotEmpty;
// }

// class _AdminDocumentsTab extends ConsumerStatefulWidget {
//   const _AdminDocumentsTab({required this.documentsState});

//   final AsyncValue<List<RemoteDocument>> documentsState;

//   @override
//   ConsumerState<_AdminDocumentsTab> createState() => _AdminDocumentsTabState();
// }

// class _AdminDocumentsTabState extends ConsumerState<_AdminDocumentsTab> {
//   final _searchController = TextEditingController();

//   @override
//   void dispose() {
//     _searchController.dispose();
//     super.dispose();
//   }

//   List<RemoteDocument> _filter(List<RemoteDocument> documents) {
//     final query = _searchController.text.trim().toLowerCase();
//     if (query.isEmpty) return documents;
//     return documents.where((document) {
//       final owner =
//           '${document.ownerFullName ?? ''} ${document.ownerUsername ?? ''}'
//               .toLowerCase();
//       return document.fileName.toLowerCase().contains(query) ||
//           owner.contains(query);
//     }).toList();
//   }

//   Future<void> _downloadAndOpen(RemoteDocument document) async {
//     try {
//       final localPath = await ref
//           .read(documentRepositoryProvider)
//           .downloadDocument(document);
//       await OpenFilex.open(localPath);
//     } catch (error) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text(error.toString())));
//     }
//   }

//   Future<void> _renameDocument(RemoteDocument document) async {
//     final controller = TextEditingController(text: document.fileName);
//     final result = await showDialog<String>(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('إعادة تسمية الملف'),
//         content: TextField(
//           controller: controller,
//           autofocus: true,
//           decoration: const InputDecoration(labelText: 'اسم الملف'),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text('إلغاء'),
//           ),
//           FilledButton(
//             onPressed: () => Navigator.pop(context, controller.text.trim()),
//             child: const Text('حفظ'),
//           ),
//         ],
//       ),
//     );

//     if (result == null || result.isEmpty) return;

//     try {
//       await ref
//           .read(documentRepositoryProvider)
//           .renameDocument(document.id, result);
//       await ref.read(adminDocumentsControllerProvider.notifier).refresh();
//       if (!mounted) return;
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(const SnackBar(content: Text('تم تحديث اسم الملف')));
//     } catch (error) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text(error.toString())));
//     }
//   }

//   Future<void> _deleteDocument(RemoteDocument document) async {
//     final shouldDelete =
//         await showDialog<bool>(
//           context: context,
//           builder: (context) => AlertDialog(
//             title: const Text('حذف الملف'),
//             content: Text('هل تريد حذف "${document.fileName}" نهائيًا؟'),
//             actions: [
//               TextButton(
//                 onPressed: () => Navigator.pop(context, false),
//                 child: const Text('إلغاء'),
//               ),
//               FilledButton(
//                 onPressed: () => Navigator.pop(context, true),
//                 child: const Text('حذف'),
//               ),
//             ],
//           ),
//         ) ??
//         false;

//     if (!shouldDelete) return;

//     try {
//       await ref.read(documentRepositoryProvider).deleteDocument(document.id);
//       await ref.read(adminDocumentsControllerProvider.notifier).refresh();
//       if (!mounted) return;
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(const SnackBar(content: Text('تم حذف الملف')));
//     } catch (error) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text(error.toString())));
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.all(16),
//       child: Column(
//         children: [
//           Row(
//             children: [
//               Expanded(
//                 child: TextField(
//                   controller: _searchController,
//                   onChanged: (_) => setState(() {}),
//                   decoration: const InputDecoration(
//                     hintText: 'ابحث باسم الملف أو صاحبه',
//                     prefixIcon: Icon(Icons.search),
//                   ),
//                 ),
//               ),
//               const SizedBox(width: 12),
//               IconButton(
//                 onPressed: () => ref
//                     .read(adminDocumentsControllerProvider.notifier)
//                     .refresh(),
//                 icon: const Icon(Icons.refresh),
//               ),
//             ],
//           ),
//           const SizedBox(height: 16),
//           Expanded(
//             child: widget.documentsState.when(
//               loading: () =>
//                   const Center(child: CircularProgressIndicator.adaptive()),
//               error: (error, stackTrace) =>
//                   Center(child: Text(error.toString())),
//               data: (documents) {
//                 final filtered = _filter(documents);
//                 return SingleChildScrollView(
//                   scrollDirection: Axis.horizontal,
//                   child: DataTable(
//                     columns: const [
//                       DataColumn(label: Text('اسم الملف')),
//                       DataColumn(label: Text('المالك')),
//                       DataColumn(label: Text('الصفحات')),
//                       DataColumn(label: Text('الحجم')),
//                       DataColumn(label: Text('التاريخ')),
//                       DataColumn(label: Text('إجراءات')),
//                     ],
//                     rows: filtered
//                         .map(
//                           (document) => DataRow(
//                             cells: [
//                               DataCell(
//                                 SizedBox(
//                                   width: 240,
//                                   child: Text(
//                                     document.fileName,
//                                     overflow: TextOverflow.ellipsis,
//                                   ),
//                                 ),
//                               ),
//                               DataCell(
//                                 Text(
//                                   document.ownerFullName?.trim().isNotEmpty ==
//                                           true
//                                       ? document.ownerFullName!
//                                       : (document.ownerUsername ?? 'غير معروف'),
//                                 ),
//                               ),
//                               DataCell(Text('${document.pageCount}')),
//                               DataCell(Text(formatFileSize(document.fileSize))),
//                               DataCell(Text(formatDate(document.createdAt))),
//                               DataCell(
//                                 Wrap(
//                                   spacing: 4,
//                                   children: [
//                                     IconButton(
//                                       tooltip: 'فتح',
//                                       onPressed: () =>
//                                           _downloadAndOpen(document),
//                                       icon: const Icon(Icons.open_in_new),
//                                     ),
//                                     IconButton(
//                                       tooltip: 'تنزيل',
//                                       onPressed: () =>
//                                           _downloadAndOpen(document),
//                                       icon: const Icon(Icons.download_outlined),
//                                     ),
//                                     IconButton(
//                                       tooltip: 'إعادة تسمية',
//                                       onPressed: () =>
//                                           _renameDocument(document),
//                                       icon: const Icon(
//                                         Icons.drive_file_rename_outline,
//                                       ),
//                                     ),
//                                     IconButton(
//                                       tooltip: 'حذف',
//                                       onPressed: () =>
//                                           _deleteDocument(document),
//                                       icon: const Icon(Icons.delete_outline),
//                                     ),
//                                   ],
//                                 ),
//                               ),
//                             ],
//                           ),
//                         )
//                         .toList(),
//                   ),
//                 );
//               },
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// String _departmentName(List<DepartmentSummary> departments, String? id) {
//   if (id == null) return 'بدون قسم';
//   return departments
//           .where((department) => department.id == id)
//           .map((department) => department.name)
//           .firstOrNull ??
//       'بدون قسم';
// }

// class _UsersAdminTab extends ConsumerWidget {
//   const _UsersAdminTab({required this.departments, required this.usersState});

//   final List<DepartmentSummary> departments;
//   final AsyncValue<List<ManagedUser>> usersState;

//   Future<void> _showResetPasswordDialog(
//     BuildContext context,
//     WidgetRef ref,
//     ManagedUser user,
//   ) async {
//     final userRepository = ref.read(userManagementRepositoryProvider);
//     final passwordController = TextEditingController(text: '123456');
//     var isSaving = false;
//     String? errorText;

//     await showDialog<void>(
//       context: context,
//       builder: (context) => StatefulBuilder(
//         builder: (context, setLocalState) => AlertDialog(
//           title: Text(
//             'إعادة تعيين كلمة المرور لـ ${user.fullName.isEmpty ? user.username : user.fullName}',
//           ),
//           content: SizedBox(
//             width: 420,
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 TextField(
//                   controller: passwordController,
//                   enabled: !isSaving,
//                   decoration: const InputDecoration(
//                     labelText: 'كلمة المرور الجديدة',
//                   ),
//                 ),
//                 if (errorText != null) ...[
//                   const SizedBox(height: 12),
//                   Align(
//                     alignment: Alignment.centerRight,
//                     child: Text(
//                       errorText!,
//                       style: const TextStyle(color: Color(0xFFB91C1C)),
//                     ),
//                   ),
//                 ],
//               ],
//             ),
//           ),
//           actions: [
//             TextButton(
//               onPressed: isSaving ? null : () => Navigator.pop(context),
//               child: const Text('إلغاء'),
//             ),
//             FilledButton.icon(
//               onPressed: isSaving
//                   ? null
//                   : () async {
//                       final password = passwordController.text.trim();
//                       if (password.length < 6) {
//                         setLocalState(() {
//                           errorText =
//                               'كلمة المرور يجب أن تكون 6 أحرف على الأقل.';
//                         });
//                         return;
//                       }
//                       setLocalState(() {
//                         isSaving = true;
//                         errorText = null;
//                       });
//                       try {
//                         await userRepository.resetPassword(
//                           userId: user.id,
//                           password: password,
//                         );
//                         if (!context.mounted) return;
//                         Navigator.pop(context);
//                         ScaffoldMessenger.of(context).showSnackBar(
//                           const SnackBar(
//                             content: Text('تمت إعادة تعيين كلمة المرور بنجاح'),
//                           ),
//                         );
//                       } catch (error) {
//                         setLocalState(() {
//                           isSaving = false;
//                           errorText = error.toString();
//                         });
//                       }
//                     },
//               icon: const Icon(Icons.lock_reset_outlined),
//               label: isSaving
//                   ? const Text('جار الحفظ...')
//                   : const Text('إعادة التعيين'),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Future<void> _showUserDialog(
//     BuildContext context,
//     WidgetRef ref, {
//     ManagedUser? user,
//   }) async {
//     final userRepository = ref.read(userManagementRepositoryProvider);
//     final usersController = ref.read(usersControllerProvider.notifier);
//     final overviewController = ref.read(
//       chatOverviewControllerProvider.notifier,
//     );
//     final usernameController = TextEditingController(
//       text: user?.username ?? '',
//     );
//     final fullNameController = TextEditingController(
//       text: user?.fullName ?? '',
//     );
//     final passwordController = TextEditingController();
//     var role = user?.role ?? 'user';
//     String? departmentId = user?.departmentId;
//     var isSaving = false;
//     String? errorText;

//     final saved = await showDialog<bool>(
//       context: context,
//       builder: (context) => StatefulBuilder(
//         builder: (context, setLocalState) => AlertDialog(
//           title: Text(user == null ? 'إضافة مستخدم' : 'تعديل مستخدم'),
//           content: SizedBox(
//             width: 460,
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 TextField(
//                   controller: usernameController,
//                   enabled: !isSaving,
//                   decoration: const InputDecoration(labelText: 'اسم المستخدم'),
//                 ),
//                 const SizedBox(height: 12),
//                 TextField(
//                   controller: fullNameController,
//                   enabled: !isSaving,
//                   decoration: const InputDecoration(labelText: 'الاسم الكامل'),
//                 ),
//                 const SizedBox(height: 12),
//                 DropdownButtonFormField<String>(
//                   initialValue: role,
//                   decoration: const InputDecoration(labelText: 'الدور'),
//                   items: const [
//                     DropdownMenuItem(value: 'user', child: Text('user')),
//                     DropdownMenuItem(value: 'manager', child: Text('manager')),
//                     DropdownMenuItem(value: 'admin', child: Text('admin')),
//                   ],
//                   onChanged: isSaving ? null : (value) => role = value ?? role,
//                 ),
//                 const SizedBox(height: 12),
//                 DropdownButtonFormField<String?>(
//                   initialValue: departmentId,
//                   decoration: const InputDecoration(labelText: 'القسم'),
//                   items: [
//                     const DropdownMenuItem<String?>(
//                       value: null,
//                       child: Text('بدون قسم'),
//                     ),
//                     ...departments.map(
//                       (department) => DropdownMenuItem<String?>(
//                         value: department.id,
//                         child: Text(department.name),
//                       ),
//                     ),
//                   ],
//                   onChanged: isSaving ? null : (value) => departmentId = value,
//                 ),
//                 const SizedBox(height: 12),
//                 TextField(
//                   controller: passwordController,
//                   enabled: !isSaving,
//                   decoration: InputDecoration(
//                     labelText: user == null
//                         ? 'كلمة المرور'
//                         : 'كلمة مرور جديدة أو إعادة تعيينها',
//                     helperText: user == null
//                         ? 'اتركها فارغة لاستخدام 123456 أو اكتب 6 أحرف على الأقل'
//                         : 'اتركها فارغة لو لن تغيّر كلمة المرور',
//                   ),
//                 ),
//                 if (errorText != null) ...[
//                   const SizedBox(height: 12),
//                   Align(
//                     alignment: Alignment.centerRight,
//                     child: Text(
//                       errorText!,
//                       style: const TextStyle(color: Color(0xFFB91C1C)),
//                     ),
//                   ),
//                 ],
//               ],
//             ),
//           ),
//           actions: [
//             TextButton(
//               onPressed: isSaving ? null : () => Navigator.pop(context),
//               child: const Text('إلغاء'),
//             ),
//             FilledButton(
//               onPressed: isSaving
//                   ? null
//                   : () async {
//                       final username = usernameController.text.trim();
//                       final fullName = fullNameController.text.trim();
//                       final password = passwordController.text.trim();
//                       if (username.isEmpty) {
//                         setLocalState(() {
//                           errorText = 'اسم المستخدم مطلوب.';
//                         });
//                         return;
//                       }
//                       if (fullName.isEmpty) {
//                         setLocalState(() {
//                           errorText = 'الاسم الكامل مطلوب.';
//                         });
//                         return;
//                       }
//                       if (password.isNotEmpty && password.length < 6) {
//                         setLocalState(() {
//                           errorText =
//                               'كلمة المرور يجب أن تكون 6 أحرف على الأقل.';
//                         });
//                         return;
//                       }
//                       setLocalState(() {
//                         isSaving = true;
//                         errorText = null;
//                       });
//                       try {
//                         if (user == null) {
//                           await userRepository.createUser(
//                             username: username,
//                             fullName: fullName,
//                             password: password.isEmpty ? '123456' : password,
//                             role: role,
//                             departmentId: departmentId,
//                           );
//                         } else {
//                           await userRepository.updateUser(
//                             userId: user.id,
//                             username: username,
//                             fullName: fullName,
//                             password: password,
//                             role: role,
//                             departmentId: departmentId,
//                           );
//                         }
//                         if (context.mounted) {
//                           Navigator.pop(context, true);
//                         }
//                       } catch (error) {
//                         setLocalState(() {
//                           isSaving = false;
//                           errorText = error.toString();
//                         });
//                       }
//                     },
//               child: isSaving
//                   ? const SizedBox(
//                       width: 18,
//                       height: 18,
//                       child: CircularProgressIndicator(strokeWidth: 2),
//                     )
//                   : const Text('حفظ'),
//             ),
//           ],
//         ),
//       ),
//     );

//     if (saved == true && context.mounted) {
//       await usersController.refresh();
//       await overviewController.refresh();
//     }
//   }

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     return Padding(
//       padding: const EdgeInsets.all(16),
//       child: Column(
//         children: [
//           Row(
//             children: [
//               FilledButton.icon(
//                 onPressed: () => _showUserDialog(context, ref),
//                 icon: const Icon(Icons.person_add_alt_1),
//                 label: const Text('إضافة مستخدم'),
//               ),
//               const Spacer(),
//               IconButton(
//                 onPressed: () =>
//                     ref.read(usersControllerProvider.notifier).refresh(),
//                 icon: const Icon(Icons.refresh),
//               ),
//             ],
//           ),
//           const SizedBox(height: 16),
//           Expanded(
//             child: usersState.when(
//               loading: () =>
//                   const Center(child: CircularProgressIndicator.adaptive()),
//               error: (error, stackTrace) =>
//                   Center(child: Text(error.toString())),
//               data: (users) => SingleChildScrollView(
//                 scrollDirection: Axis.horizontal,
//                 child: DataTable(
//                   columns: const [
//                     DataColumn(label: Text('اسم المستخدم')),
//                     DataColumn(label: Text('الاسم الكامل')),
//                     DataColumn(label: Text('الدور')),
//                     DataColumn(label: Text('القسم')),
//                     DataColumn(label: Text('الحالة')),
//                     DataColumn(label: Text('إجراءات')),
//                   ],
//                   rows: users
//                       .map(
//                         (user) => DataRow(
//                           cells: [
//                             DataCell(Text(user.username)),
//                             DataCell(Text(user.fullName)),
//                             DataCell(Text(user.role)),
//                             DataCell(
//                               Text(
//                                 _departmentName(departments, user.departmentId),
//                               ),
//                             ),
//                             DataCell(Text(user.isActive ? 'نشط' : 'موقوف')),
//                             DataCell(
//                               Row(
//                                 spacing: 8,
//                                 children: [
//                                   IconButton(
//                                     tooltip: 'Reset Password',
//                                     onPressed: () => _showResetPasswordDialog(
//                                       context,
//                                       ref,
//                                       user,
//                                     ),
//                                     icon: const Icon(Icons.lock_reset_outlined),
//                                   ),
//                                   IconButton(
//                                     onPressed: () => _showUserDialog(
//                                       context,
//                                       ref,
//                                       user: user,
//                                     ),
//                                     icon: const Icon(Icons.edit_outlined),
//                                   ),
//                                   _ManagedUserStatusSwitch(
//                                     userId: user.id,
//                                     isActive: user.isActive,
//                                   ),
//                                 ],
//                               ),
//                             ),
//                           ],
//                         ),
//                       )
//                       .toList(),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _ManagedUserStatusSwitch extends ConsumerStatefulWidget {
//   const _ManagedUserStatusSwitch({
//     required this.userId,
//     required this.isActive,
//   });

//   final String userId;
//   final bool isActive;

//   @override
//   ConsumerState<_ManagedUserStatusSwitch> createState() =>
//       _ManagedUserStatusSwitchState();
// }

// class _ManagedUserStatusSwitchState
//     extends ConsumerState<_ManagedUserStatusSwitch> {
//   late bool _isActive = widget.isActive;
//   var _isSaving = false;

//   @override
//   void didUpdateWidget(covariant _ManagedUserStatusSwitch oldWidget) {
//     super.didUpdateWidget(oldWidget);
//     if (!_isSaving && oldWidget.isActive != widget.isActive) {
//       _isActive = widget.isActive;
//     }
//   }

//   Future<void> _updateStatus(bool value) async {
//     setState(() {
//       _isSaving = true;
//       _isActive = value;
//     });
//     try {
//       await ref
//           .read(userManagementRepositoryProvider)
//           .updateUserStatus(userId: widget.userId, isActive: value);
//       await ref.read(usersControllerProvider.notifier).refresh();
//       await ref.read(chatOverviewControllerProvider.notifier).refresh();
//     } catch (error) {
//       if (!mounted) return;
//       setState(() {
//         _isActive = !_isActive;
//       });
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text(error.toString())));
//     } finally {
//       if (mounted) {
//         setState(() {
//           _isSaving = false;
//         });
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (_isSaving) {
//       return const SizedBox(
//         width: 28,
//         height: 28,
//         child: Padding(
//           padding: EdgeInsets.all(4),
//           child: CircularProgressIndicator(strokeWidth: 2),
//         ),
//       );
//     }

//     return Switch(value: _isActive, onChanged: _updateStatus);
//   }
// }

// class _AnnouncementsAdminTab extends ConsumerWidget {
//   const _AnnouncementsAdminTab({required this.announcementsState});

//   final AsyncValue<List<AdminAnnouncement>> announcementsState;

//   Color _toneColor(BuildContext context, String tone) {
//     final scheme = Theme.of(context).colorScheme;
//     return switch (tone) {
//       'success' => const Color(0xFF166534),
//       'warning' => const Color(0xFFD97706),
//       'critical' => scheme.error,
//       _ => scheme.primary,
//     };
//   }

//   String _toneLabel(String tone) {
//     return switch (tone) {
//       'success' => 'نجاح',
//       'warning' => 'تنبيه',
//       'critical' => 'عاجل',
//       _ => 'معلومة',
//     };
//   }

//   Future<void> _showAnnouncementDialog(
//     BuildContext context,
//     WidgetRef ref, {
//     AdminAnnouncement? announcement,
//   }) async {
//     final announcementRepository = ref.read(announcementRepositoryProvider);
//     final adminAnnouncementsController = ref.read(
//       adminAnnouncementsControllerProvider.notifier,
//     );
//     final announcementsController = ref.read(
//       announcementsControllerProvider.notifier,
//     );
//     final titleController = TextEditingController(
//       text: announcement?.title ?? '',
//     );
//     final messageController = TextEditingController(
//       text: announcement?.message ?? '',
//     );
//     var tone = announcement?.tone ?? 'info';
//     var isPinned = announcement?.isPinned == true;
//     var isActive = announcement?.isActive != false;
//     var isSaving = false;
//     String? errorText;

//     final saved = await showDialog<bool>(
//       context: context,
//       builder: (context) => StatefulBuilder(
//         builder: (context, setLocalState) => AlertDialog(
//           title: Text(announcement == null ? 'إضافة إعلان' : 'تعديل إعلان'),
//           content: SizedBox(
//             width: 520,
//             child: SingleChildScrollView(
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   TextField(
//                     controller: titleController,
//                     enabled: !isSaving,
//                     decoration: const InputDecoration(labelText: 'العنوان'),
//                   ),
//                   const SizedBox(height: 12),
//                   TextField(
//                     controller: messageController,
//                     enabled: !isSaving,
//                     minLines: 3,
//                     maxLines: 5,
//                     decoration: const InputDecoration(labelText: 'نص الإعلان'),
//                   ),
//                   const SizedBox(height: 12),
//                   DropdownButtonFormField<String>(
//                     initialValue: tone,
//                     decoration: const InputDecoration(labelText: 'النوع'),
//                     items: const [
//                       DropdownMenuItem(value: 'info', child: Text('معلومة')),
//                       DropdownMenuItem(value: 'success', child: Text('نجاح')),
//                       DropdownMenuItem(value: 'warning', child: Text('تنبيه')),
//                       DropdownMenuItem(value: 'critical', child: Text('عاجل')),
//                     ],
//                     onChanged: isSaving
//                         ? null
//                         : (value) => tone = value ?? tone,
//                   ),
//                   const SizedBox(height: 12),
//                   SwitchListTile(
//                     value: isPinned,
//                     onChanged: isSaving
//                         ? null
//                         : (value) => setLocalState(() => isPinned = value),
//                     title: const Text('تثبيت في البداية'),
//                     contentPadding: EdgeInsets.zero,
//                   ),
//                   SwitchListTile(
//                     value: isActive,
//                     onChanged: isSaving
//                         ? null
//                         : (value) => setLocalState(() => isActive = value),
//                     title: const Text('نشط'),
//                     contentPadding: EdgeInsets.zero,
//                   ),
//                   if (errorText != null) ...[
//                     const SizedBox(height: 12),
//                     Align(
//                       alignment: Alignment.centerRight,
//                       child: Text(
//                         errorText!,
//                         style: const TextStyle(color: Color(0xFFB91C1C)),
//                       ),
//                     ),
//                   ],
//                 ],
//               ),
//             ),
//           ),
//           actions: [
//             TextButton(
//               onPressed: isSaving ? null : () => Navigator.pop(context),
//               child: const Text('إلغاء'),
//             ),
//             FilledButton(
//               onPressed: isSaving
//                   ? null
//                   : () async {
//                       final title = titleController.text.trim();
//                       final message = messageController.text.trim();
//                       if (title.length < 2) {
//                         setLocalState(() {
//                           errorText = 'العنوان يجب أن يكون حرفين على الأقل.';
//                         });
//                         return;
//                       }
//                       if (message.length < 4) {
//                         setLocalState(() {
//                           errorText = 'نص الإعلان قصير جدًا.';
//                         });
//                         return;
//                       }
//                       setLocalState(() {
//                         isSaving = true;
//                         errorText = null;
//                       });
//                       try {
//                         if (announcement == null) {
//                           await announcementRepository.createAnnouncement(
//                             title: title,
//                             message: message,
//                             tone: tone,
//                             isPinned: isPinned,
//                             isActive: isActive,
//                           );
//                         } else {
//                           await announcementRepository.updateAnnouncement(
//                             announcementId: announcement.id,
//                             title: title,
//                             message: message,
//                             tone: tone,
//                             isPinned: isPinned,
//                             isActive: isActive,
//                           );
//                         }
//                         if (!context.mounted) return;
//                         Navigator.pop(context, true);
//                       } catch (error) {
//                         setLocalState(() {
//                           isSaving = false;
//                           errorText = error.toString();
//                         });
//                       }
//                     },
//               child: isSaving
//                   ? const SizedBox(
//                       width: 18,
//                       height: 18,
//                       child: CircularProgressIndicator(strokeWidth: 2),
//                     )
//                   : const Text('حفظ'),
//             ),
//           ],
//         ),
//       ),
//     );

//     if (saved == true && context.mounted) {
//       await adminAnnouncementsController.refresh();
//       await announcementsController.refresh();
//     }
//   }

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     return Padding(
//       padding: const EdgeInsets.all(16),
//       child: Column(
//         children: [
//           Row(
//             children: [
//               FilledButton.icon(
//                 onPressed: () => _showAnnouncementDialog(context, ref),
//                 icon: const Icon(Icons.campaign_outlined),
//                 label: const Text('إضافة إعلان'),
//               ),
//               const Spacer(),
//               IconButton(
//                 onPressed: () => ref
//                     .read(adminAnnouncementsControllerProvider.notifier)
//                     .refresh(),
//                 icon: const Icon(Icons.refresh),
//               ),
//             ],
//           ),
//           const SizedBox(height: 16),
//           Expanded(
//             child: announcementsState.when(
//               loading: () =>
//                   const Center(child: CircularProgressIndicator.adaptive()),
//               error: (error, stackTrace) =>
//                   Center(child: Text(error.toString())),
//               data: (announcements) => ListView.separated(
//                 itemCount: announcements.length,
//                 separatorBuilder: (_, __) => const SizedBox(height: 12),
//                 itemBuilder: (context, index) {
//                   final announcement = announcements[index];
//                   return Card(
//                     elevation: 0,
//                     child: Padding(
//                       padding: const EdgeInsets.all(16),
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Row(
//                             children: [
//                               Expanded(
//                                 child: Text(
//                                   announcement.title,
//                                   style: Theme.of(context).textTheme.titleMedium
//                                       ?.copyWith(fontWeight: FontWeight.w800),
//                                 ),
//                               ),
//                               Switch(
//                                 value: announcement.isActive,
//                                 onChanged: (value) async {
//                                   await ref
//                                       .read(announcementRepositoryProvider)
//                                       .updateAnnouncementStatus(
//                                         announcementId: announcement.id,
//                                         isActive: value,
//                                       );
//                                   await ref
//                                       .read(
//                                         adminAnnouncementsControllerProvider
//                                             .notifier,
//                                       )
//                                       .refresh();
//                                   await ref
//                                       .read(
//                                         announcementsControllerProvider
//                                             .notifier,
//                                       )
//                                       .refresh();
//                                 },
//                               ),
//                             ],
//                           ),
//                           const SizedBox(height: 8),
//                           Text(announcement.message),
//                           const SizedBox(height: 12),
//                           Wrap(
//                             spacing: 8,
//                             runSpacing: 8,
//                             children: [
//                               Chip(
//                                 label: Text(_toneLabel(announcement.tone)),
//                                 backgroundColor: _toneColor(
//                                   context,
//                                   announcement.tone,
//                                 ).withValues(alpha: 0.12),
//                               ),
//                               if (announcement.isPinned)
//                                 const Chip(label: Text('مثبت')),
//                               Chip(
//                                 label: Text(
//                                   announcement.isActive ? 'نشط' : 'متوقف',
//                                 ),
//                               ),
//                               Chip(
//                                 label: Text(
//                                   DateFormat(
//                                     'yyyy/MM/dd • hh:mm a',
//                                   ).format(announcement.updatedAt),
//                                 ),
//                               ),
//                             ],
//                           ),
//                           const SizedBox(height: 8),
//                           Row(
//                             children: [
//                               TextButton.icon(
//                                 onPressed: () => _showAnnouncementDialog(
//                                   context,
//                                   ref,
//                                   announcement: announcement,
//                                 ),
//                                 icon: const Icon(Icons.edit_outlined),
//                                 label: const Text('تعديل'),
//                               ),
//                               TextButton.icon(
//                                 onPressed: () async {
//                                   await ref
//                                       .read(announcementRepositoryProvider)
//                                       .deleteAnnouncement(announcement.id);
//                                   await ref
//                                       .read(
//                                         adminAnnouncementsControllerProvider
//                                             .notifier,
//                                       )
//                                       .refresh();
//                                   await ref
//                                       .read(
//                                         announcementsControllerProvider
//                                             .notifier,
//                                       )
//                                       .refresh();
//                                 },
//                                 icon: const Icon(Icons.delete_outline),
//                                 label: const Text('حذف'),
//                               ),
//                             ],
//                           ),
//                         ],
//                       ),
//                     ),
//                   );
//                 },
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _DepartmentsAdminTab extends ConsumerWidget {
//   const _DepartmentsAdminTab({required this.departments, required this.users});

//   final List<DepartmentSummary> departments;
//   final List<ChatDirectoryUser> users;

//   Future<void> _showDepartmentDialog(
//     BuildContext context,
//     WidgetRef ref, {
//     DepartmentSummary? department,
//   }) async {
//     final container = ProviderScope.containerOf(context, listen: false);
//     final overviewController = container.read(
//       chatOverviewControllerProvider.notifier,
//     );
//     final nameController = TextEditingController(text: department?.name ?? '');
//     final codeController = TextEditingController(text: department?.code ?? '');
//     final descriptionController = TextEditingController(
//       text: department?.description ?? '',
//     );
//     final selectedManagers = <String>{
//       ...department?.managers ?? const <String>[],
//     };
//     var isSaving = false;
//     String? errorText;

//     final saved = await showDialog<bool>(
//       context: context,
//       builder: (context) => StatefulBuilder(
//         builder: (context, setLocalState) => AlertDialog(
//           title: Text(department == null ? 'إضافة قسم' : 'تعديل قسم'),
//           content: SizedBox(
//             width: 520,
//             child: SingleChildScrollView(
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   TextField(
//                     controller: nameController,
//                     enabled: !isSaving,
//                     decoration: const InputDecoration(labelText: 'اسم القسم'),
//                   ),
//                   const SizedBox(height: 12),
//                   TextField(
//                     controller: codeController,
//                     enabled: !isSaving,
//                     decoration: const InputDecoration(labelText: 'الكود'),
//                   ),
//                   const SizedBox(height: 12),
//                   TextField(
//                     controller: descriptionController,
//                     enabled: !isSaving,
//                     decoration: const InputDecoration(labelText: 'الوصف'),
//                   ),
//                   const SizedBox(height: 14),
//                   Align(
//                     alignment: Alignment.centerRight,
//                     child: Text(
//                       'المديرون',
//                       style: Theme.of(context).textTheme.titleMedium,
//                     ),
//                   ),
//                   const SizedBox(height: 8),
//                   ...users
//                       .where(
//                         (entry) =>
//                             entry.role == 'manager' || entry.role == 'admin',
//                       )
//                       .map(
//                         (entry) => CheckboxListTile(
//                           value: selectedManagers.contains(entry.id),
//                           title: Text(entry.displayName),
//                           subtitle: Text(entry.username),
//                           onChanged: isSaving
//                               ? null
//                               : (value) {
//                                   setLocalState(() {
//                                     if (value == true) {
//                                       selectedManagers.add(entry.id);
//                                     } else {
//                                       selectedManagers.remove(entry.id);
//                                     }
//                                   });
//                                 },
//                         ),
//                       ),
//                   if (errorText != null) ...[
//                     const SizedBox(height: 12),
//                     Align(
//                       alignment: Alignment.centerRight,
//                       child: Text(
//                         errorText!,
//                         style: const TextStyle(color: Color(0xFFB91C1C)),
//                       ),
//                     ),
//                   ],
//                 ],
//               ),
//             ),
//           ),
//           actions: [
//             TextButton(
//               onPressed: isSaving ? null : () => Navigator.pop(context),
//               child: const Text('إلغاء'),
//             ),
//             FilledButton(
//               onPressed: isSaving
//                   ? null
//                   : () async {
//                       final name = nameController.text.trim();
//                       final code = codeController.text.trim();
//                       if (name.isEmpty) {
//                         setLocalState(() {
//                           errorText = 'اسم القسم مطلوب.';
//                         });
//                         return;
//                       }
//                       if (code.isEmpty) {
//                         setLocalState(() {
//                           errorText = 'كود القسم مطلوب.';
//                         });
//                         return;
//                       }
//                       setLocalState(() {
//                         isSaving = true;
//                         errorText = null;
//                       });
//                       try {
//                         if (department == null) {
//                           await overviewController.createDepartment(
//                             name: name,
//                             code: code,
//                             description: descriptionController.text.trim(),
//                           );
//                         } else {
//                           await overviewController.updateDepartment(
//                             departmentId: department.id,
//                             name: name,
//                             code: code,
//                             description: descriptionController.text.trim(),
//                             managers: selectedManagers.toList(),
//                           );
//                         }
//                         if (context.mounted) {
//                           Navigator.pop(context, true);
//                         }
//                       } catch (error) {
//                         setLocalState(() {
//                           isSaving = false;
//                           errorText = error.toString();
//                         });
//                       }
//                     },
//               child: isSaving
//                   ? const SizedBox(
//                       width: 18,
//                       height: 18,
//                       child: CircularProgressIndicator(strokeWidth: 2),
//                     )
//                   : const Text('حفظ'),
//             ),
//           ],
//         ),
//       ),
//     );

//     if (saved == true && context.mounted) {
//       await overviewController.refresh();
//     }
//   }

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     return Padding(
//       padding: const EdgeInsets.all(16),
//       child: Column(
//         children: [
//           Row(
//             children: [
//               FilledButton.icon(
//                 onPressed: () => _showDepartmentDialog(context, ref),
//                 icon: const Icon(Icons.add_business_outlined),
//                 label: const Text('إضافة قسم'),
//               ),
//             ],
//           ),
//           const SizedBox(height: 16),
//           Expanded(
//             child: ListView.separated(
//               itemCount: departments.length,
//               separatorBuilder: (_, __) => const SizedBox(height: 10),
//               itemBuilder: (context, index) {
//                 final department = departments[index];
//                 return Card(
//                   child: ListTile(
//                     title: Text(department.name),
//                     subtitle: Text(
//                       '${department.code} • ${department.description} • الأعضاء: ${department.membersCount}',
//                     ),
//                     trailing: Wrap(
//                       spacing: 4,
//                       children: [
//                         IconButton(
//                           onPressed: () => _showDepartmentDialog(
//                             context,
//                             ref,
//                             department: department,
//                           ),
//                           icon: const Icon(Icons.edit_outlined),
//                         ),
//                         IconButton(
//                           onPressed: () async {
//                             try {
//                               await ref
//                                   .read(chatOverviewControllerProvider.notifier)
//                                   .deleteDepartment(department.id);
//                               if (!context.mounted) return;
//                               ScaffoldMessenger.of(context).showSnackBar(
//                                 const SnackBar(content: Text('تم حذف القسم')),
//                               );
//                             } catch (error) {
//                               if (!context.mounted) return;
//                               ScaffoldMessenger.of(context).showSnackBar(
//                                 SnackBar(content: Text(error.toString())),
//                               );
//                             }
//                           },
//                           icon: const Icon(Icons.delete_outline),
//                         ),
//                       ],
//                     ),
//                   ),
//                 );
//               },
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _RoomsAdminTab extends ConsumerWidget {
//   const _RoomsAdminTab({required this.conversations, required this.users});

//   final List<ChatConversation> conversations;
//   final List<ChatDirectoryUser> users;

//   Future<void> _showCreateBroadcastDialog(
//     BuildContext context,
//     WidgetRef ref,
//   ) async {
//     final overviewController = ref.read(chatOverviewControllerProvider.notifier);
//     final nameController = TextEditingController();
//     final descriptionController = TextEditingController();
//     final selectedPublishers = <String>{};
//     final selectedAdmins = <String>{};
//     var isSaving = false;
//     String? errorText;

//     final created = await showDialog<bool>(
//       context: context,
//       builder: (context) => StatefulBuilder(
//         builder: (context, setLocalState) => AlertDialog(
//           title: const Text('إنشاء قناة بث'),
//           content: SizedBox(
//             width: 560,
//             child: SingleChildScrollView(
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   TextField(
//                     controller: nameController,
//                     enabled: !isSaving,
//                     decoration: const InputDecoration(labelText: 'اسم القناة'),
//                   ),
//                   const SizedBox(height: 12),
//                   TextField(
//                     controller: descriptionController,
//                     enabled: !isSaving,
//                     minLines: 1,
//                     maxLines: 3,
//                     decoration: const InputDecoration(labelText: 'الوصف'),
//                   ),
//                   const SizedBox(height: 12),
//                   Align(
//                     alignment: Alignment.centerRight,
//                     child: Text(
//                       'المرسلون',
//                       style: Theme.of(context).textTheme.titleMedium,
//                     ),
//                   ),
//                   const SizedBox(height: 8),
//                   ...users.map(
//                     (user) => CheckboxListTile(
//                       value: selectedPublishers.contains(user.id),
//                       title: Text(user.displayName),
//                       subtitle: Text(user.username),
//                       onChanged: isSaving
//                           ? null
//                           : (value) {
//                               setLocalState(() {
//                                 if (value == true) {
//                                   selectedPublishers.add(user.id);
//                                 } else {
//                                   selectedPublishers.remove(user.id);
//                                   selectedAdmins.remove(user.id);
//                                 }
//                               });
//                             },
//                     ),
//                   ),
//                   const SizedBox(height: 10),
//                   Align(
//                     alignment: Alignment.centerRight,
//                     child: Text(
//                       'مشرفو البث',
//                       style: Theme.of(context).textTheme.titleMedium,
//                     ),
//                   ),
//                   const SizedBox(height: 8),
//                   ...users
//                       .where((user) => selectedPublishers.contains(user.id))
//                       .map(
//                         (user) => CheckboxListTile(
//                           value: selectedAdmins.contains(user.id),
//                           title: Text(user.displayName),
//                           subtitle: Text(user.username),
//                           onChanged: isSaving
//                               ? null
//                               : (value) {
//                                   setLocalState(() {
//                                     if (value == true) {
//                                       selectedAdmins.add(user.id);
//                                     } else {
//                                       selectedAdmins.remove(user.id);
//                                     }
//                                   });
//                                 },
//                         ),
//                       ),
//                   const SizedBox(height: 8),
//                   const Align(
//                     alignment: Alignment.centerRight,
//                     child: Text(
//                       'ملاحظة: المرسل يحدد الأقسام المستهدفة عند إرسال الرسالة.',
//                     ),
//                   ),
//                   if (errorText != null) ...[
//                     const SizedBox(height: 12),
//                     Align(
//                       alignment: Alignment.centerRight,
//                       child: Text(
//                         errorText!,
//                         style: const TextStyle(color: Color(0xFFB91C1C)),
//                       ),
//                     ),
//                   ],
//                 ],
//               ),
//             ),
//           ),
//           actions: [
//             TextButton(
//               onPressed: isSaving ? null : () => Navigator.pop(context),
//               child: const Text('إلغاء'),
//             ),
//             FilledButton(
//               onPressed: isSaving
//                   ? null
//                   : () async {
//                       final name = nameController.text.trim();
//                       if (name.isEmpty) {
//                         setLocalState(() {
//                           errorText = 'اسم القناة مطلوب.';
//                         });
//                         return;
//                       }
//                       setLocalState(() {
//                         isSaving = true;
//                         errorText = null;
//                       });
//                       try {
//                         await overviewController.createConversation(
//                           type: 'broadcast',
//                           name: name,
//                           description: descriptionController.text.trim(),
//                           memberIds: selectedPublishers.toList(),
//                           adminIds: selectedAdmins.toList(),
//                         );
//                         if (context.mounted) {
//                           Navigator.pop(context, true);
//                         }
//                       } catch (error) {
//                         setLocalState(() {
//                           isSaving = false;
//                           errorText = error.toString();
//                         });
//                       }
//                     },
//               child: isSaving
//                   ? const SizedBox(
//                       width: 18,
//                       height: 18,
//                       child: CircularProgressIndicator(strokeWidth: 2),
//                     )
//                   : const Text('إنشاء'),
//             ),
//           ],
//         ),
//       ),
//     );

//     if (created == true && context.mounted) {
//       await overviewController.refresh();
//       if (context.mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('تم إنشاء قناة البث بنجاح')),
//         );
//       }
//     }
//   }

//   Future<void> _showRoomDialog(
//     BuildContext context,
//     WidgetRef ref, {
//     required ChatConversation conversation,
//   }) async {
//     final overviewController = ref.read(
//       chatOverviewControllerProvider.notifier,
//     );
//     final nameController = TextEditingController(text: conversation.name);
//     final descriptionController = TextEditingController(
//       text: conversation.description,
//     );
//     final isBroadcast = conversation.type == 'broadcast';
//     final selectedMembers = <String>{
//       ...(isBroadcast
//           ? conversation.broadcastPublisherIds
//           : conversation.members.map((entry) => entry.id)),
//     };
//     final selectedAdmins = <String>{
//       ...conversation.admins.map((entry) => entry.id),
//     };
//     var isArchived = conversation.isArchived;
//     var isActive = conversation.isActive;
//     var isSaving = false;
//     String? errorText;

//     final saved = await showDialog<bool>(
//       context: context,
//       builder: (context) => StatefulBuilder(
//         builder: (context, setLocalState) => AlertDialog(
//           title: const Text('إدارة الغرفة'),
//           content: SizedBox(
//             width: 560,
//             child: SingleChildScrollView(
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   TextField(
//                     controller: nameController,
//                     enabled: !isSaving,
//                     decoration: const InputDecoration(labelText: 'الاسم'),
//                   ),
//                   const SizedBox(height: 12),
//                   TextField(
//                     controller: descriptionController,
//                     enabled: !isSaving,
//                     decoration: const InputDecoration(labelText: 'الوصف'),
//                   ),
//                   SwitchListTile(
//                     value: isArchived,
//                     title: const Text('مؤرشفة'),
//                     onChanged: isSaving
//                         ? null
//                         : (value) => setLocalState(() => isArchived = value),
//                   ),
//                   SwitchListTile(
//                     value: isActive,
//                     title: const Text('نشطة'),
//                     onChanged: isSaving
//                         ? null
//                         : (value) => setLocalState(() => isActive = value),
//                   ),
//                   const Divider(height: 28),
//                   Align(
//                     alignment: Alignment.centerRight,
//                     child: Text(
//                       isBroadcast ? 'المرسلون' : 'الأعضاء',
//                       style: Theme.of(context).textTheme.titleMedium,
//                     ),
//                   ),
//                   ...users.map(
//                     (user) => CheckboxListTile(
//                       value: selectedMembers.contains(user.id),
//                       title: Text(user.displayName),
//                       subtitle: Text(user.username),
//                       onChanged: isSaving
//                           ? null
//                           : (value) {
//                               setLocalState(() {
//                                 if (value == true) {
//                                   selectedMembers.add(user.id);
//                                 } else {
//                                   selectedMembers.remove(user.id);
//                                   selectedAdmins.remove(user.id);
//                                 }
//                               });
//                             },
//                     ),
//                   ),
//                   const Divider(height: 28),
//                   Align(
//                     alignment: Alignment.centerRight,
//                     child: Text(
//                       isBroadcast ? 'مشرفو البث' : 'المشرفون',
//                       style: Theme.of(context).textTheme.titleMedium,
//                     ),
//                   ),
//                   ...users
//                       .where((user) => selectedMembers.contains(user.id))
//                       .map(
//                         (user) => CheckboxListTile(
//                           value: selectedAdmins.contains(user.id),
//                           title: Text(user.displayName),
//                           subtitle: Text(user.username),
//                           onChanged: isSaving
//                               ? null
//                               : (value) {
//                                   setLocalState(() {
//                                     if (value == true) {
//                                       selectedAdmins.add(user.id);
//                                     } else {
//                                       selectedAdmins.remove(user.id);
//                                     }
//                                   });
//                                 },
//                         ),
//                       ),
//                   if (errorText != null) ...[
//                     const SizedBox(height: 12),
//                     Align(
//                       alignment: Alignment.centerRight,
//                       child: Text(
//                         errorText!,
//                         style: const TextStyle(color: Color(0xFFB91C1C)),
//                       ),
//                     ),
//                   ],
//                 ],
//               ),
//             ),
//           ),
//           actions: [
//             TextButton(
//               onPressed: () => Navigator.pop(context),
//               child: const Text('إلغاء'),
//             ),
//             FilledButton(
//               onPressed: isSaving
//                   ? null
//                   : () async {
//                       if (nameController.text.trim().isEmpty) {
//                         setLocalState(() {
//                           errorText = 'اسم الغرفة مطلوب.';
//                         });
//                         return;
//                       }
//                       setLocalState(() {
//                         isSaving = true;
//                         errorText = null;
//                       });
//                       try {
//                         await overviewController.updateManagedConversation(
//                           conversationId: conversation.id,
//                           name: nameController.text.trim(),
//                           description: descriptionController.text.trim(),
//                           memberIds: selectedMembers.toList(),
//                           adminIds: selectedAdmins.toList(),
//                           isArchived: isArchived,
//                           isActive: isActive,
//                         );
//                         if (context.mounted) {
//                           Navigator.pop(context, true);
//                         }
//                       } catch (error) {
//                         setLocalState(() {
//                           isSaving = false;
//                           errorText = error.toString();
//                         });
//                       }
//                     },
//               child: isSaving
//                   ? const SizedBox(
//                       width: 18,
//                       height: 18,
//                       child: CircularProgressIndicator(strokeWidth: 2),
//                     )
//                   : const Text('حفظ'),
//             ),
//           ],
//         ),
//       ),
//     );

//     if (saved == true && context.mounted) {
//       await overviewController.refresh();
//     }
//   }

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final authUser = ref.watch(authControllerProvider).valueOrNull;
//     final canSendBroadcast =
//         authUser?.role == 'admin' || authUser?.can('canSendBroadcast') == true;

//     final roomsView = conversations.isEmpty
//         ? const Center(child: Text('لا توجد غرف قابلة للإدارة'))
//         : Padding(
//             padding: const EdgeInsets.all(16),
//             child: ListView.separated(
//               itemCount: conversations.length,
//               separatorBuilder: (_, __) => const SizedBox(height: 10),
//               itemBuilder: (context, index) {
//                 final conversation = conversations[index];
//                 return Card(
//                   child: ListTile(
//                     title: Text(conversation.displayTitle('')),
//                     subtitle: Text(
//                       '${conversation.type} • ${conversation.isActive ? 'نشطة' : 'معطلة'} • أعضاء: ${conversation.members.length} • مشرفون: ${conversation.admins.length}',
//                     ),
//                     trailing: Wrap(
//                       spacing: 4,
//                       children: [
//                         IconButton(
//                           onPressed: () => _showRoomDialog(
//                             context,
//                             ref,
//                             conversation: conversation,
//                           ),
//                           icon: const Icon(Icons.tune_outlined),
//                         ),
//                         IconButton(
//                           onPressed: () async {
//                             try {
//                               await ref
//                                   .read(chatOverviewControllerProvider.notifier)
//                                   .deleteManagedConversation(conversation.id);
//                               if (!context.mounted) return;
//                               ScaffoldMessenger.of(context).showSnackBar(
//                                 const SnackBar(content: Text('تم حذف الغرفة')),
//                               );
//                             } catch (error) {
//                               if (!context.mounted) return;
//                               ScaffoldMessenger.of(context).showSnackBar(
//                                 SnackBar(content: Text(error.toString())),
//                               );
//                             }
//                           },
//                           icon: const Icon(Icons.delete_outline),
//                         ),
//                       ],
//                     ),
//                   ),
//                 );
//               },
//             ),
//           );

//     return Column(
//       children: [
//         Padding(
//           padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
//           child: Row(
//             children: [
//               Text(
//                 'إدارة الغرف والقنوات',
//                 style: Theme.of(context).textTheme.titleMedium?.copyWith(
//                       fontWeight: FontWeight.w700,
//                     ),
//               ),
//               const Spacer(),
//               if (canSendBroadcast)
//                 FilledButton.icon(
//                   onPressed: () => _showCreateBroadcastDialog(context, ref),
//                   icon: const Icon(Icons.campaign_outlined),
//                   label: const Text('إنشاء قناة بث'),
//                 ),
//             ],
//           ),
//         ),
//         Expanded(child: roomsView),
//       ],
//     );
//   }
// }

// class _RolesAdminTab extends ConsumerStatefulWidget {
//   const _RolesAdminTab({required this.roles});

//   final List<ChatRole> roles;

//   @override
//   ConsumerState<_RolesAdminTab> createState() => _RolesAdminTabState();
// }

// class _RolesAdminTabState extends ConsumerState<_RolesAdminTab> {
//   late Map<String, ChatPermissionSet> _draftPermissions;

//   @override
//   void initState() {
//     super.initState();
//     _draftPermissions = {
//       for (final role in widget.roles) role.id: role.permissions,
//     };
//   }

//   @override
//   void didUpdateWidget(covariant _RolesAdminTab oldWidget) {
//     super.didUpdateWidget(oldWidget);
//     _draftPermissions = {
//       for (final role in widget.roles) role.id: role.permissions,
//     };
//   }

//   ChatPermissionSet _updatePermission(
//     ChatPermissionSet source,
//     String key,
//     bool value,
//   ) {
//     return ChatPermissionSet(
//       canCreateUsers: key == 'canCreateUsers' ? value : source.canCreateUsers,
//       canCreateDepartments: key == 'canCreateDepartments'
//           ? value
//           : source.canCreateDepartments,
//       canCreateRooms: key == 'canCreateRooms' ? value : source.canCreateRooms,
//       canSendBroadcast: key == 'canSendBroadcast'
//           ? value
//           : source.canSendBroadcast,
//       canDeleteMessages: key == 'canDeleteMessages'
//           ? value
//           : source.canDeleteMessages,
//       canUploadFiles: key == 'canUploadFiles' ? value : source.canUploadFiles,
//       canModerateDepartment: key == 'canModerateDepartment'
//           ? value
//           : source.canModerateDepartment,
//       canViewDepartmentLogs: key == 'canViewDepartmentLogs'
//           ? value
//           : source.canViewDepartmentLogs,
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return ListView.separated(
//       padding: const EdgeInsets.all(16),
//       itemCount: widget.roles.length,
//       separatorBuilder: (_, __) => const SizedBox(height: 12),
//       itemBuilder: (context, index) {
//         final role = widget.roles[index];
//         final draft = _draftPermissions[role.id] ?? role.permissions;

//         Widget permissionSwitch(String key, String label, bool currentValue) {
//           return SwitchListTile(
//             contentPadding: EdgeInsets.zero,
//             title: Text(label),
//             value: currentValue,
//             onChanged: (value) {
//               setState(() {
//                 _draftPermissions[role.id] = _updatePermission(
//                   draft,
//                   key,
//                   value,
//                 );
//               });
//             },
//           );
//         }

//         return Card(
//           child: Padding(
//             padding: const EdgeInsets.all(16),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   role.roleName,
//                   style: Theme.of(context).textTheme.titleMedium?.copyWith(
//                     fontWeight: FontWeight.w700,
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 permissionSwitch(
//                   'canCreateUsers',
//                   'إنشاء مستخدمين',
//                   draft.canCreateUsers,
//                 ),
//                 permissionSwitch(
//                   'canCreateDepartments',
//                   'إنشاء أقسام',
//                   draft.canCreateDepartments,
//                 ),
//                 permissionSwitch(
//                   'canCreateRooms',
//                   'إنشاء غرف',
//                   draft.canCreateRooms,
//                 ),
//                 permissionSwitch(
//                   'canSendBroadcast',
//                   'إرسال إعلانات',
//                   draft.canSendBroadcast,
//                 ),
//                 permissionSwitch(
//                   'canDeleteMessages',
//                   'حذف الرسائل',
//                   draft.canDeleteMessages,
//                 ),
//                 permissionSwitch(
//                   'canUploadFiles',
//                   'رفع الملفات',
//                   draft.canUploadFiles,
//                 ),
//                 permissionSwitch(
//                   'canModerateDepartment',
//                   'إدارة محادثات القسم',
//                   draft.canModerateDepartment,
//                 ),
//                 permissionSwitch(
//                   'canViewDepartmentLogs',
//                   'عرض السجل الإداري',
//                   draft.canViewDepartmentLogs,
//                 ),
//                 const SizedBox(height: 12),
//                 FilledButton(
//                   onPressed: () async {
//                     await ref
//                         .read(chatOverviewControllerProvider.notifier)
//                         .updateRole(
//                           roleId: role.id,
//                           permissions:
//                               _draftPermissions[role.id] ?? role.permissions,
//                         );
//                   },
//                   child: const Text('حفظ الصلاحيات'),
//                 ),
//               ],
//             ),
//           ),
//         );
//       },
//     );
//   }
// }

// class _AuditLogsTab extends StatelessWidget {
//   const _AuditLogsTab({required this.logsFuture});

//   final Future<_AdminLoadResult<ChatAuditLog>> logsFuture;

//   @override
//   Widget build(BuildContext context) {
//     return FutureBuilder<_AdminLoadResult<ChatAuditLog>>(
//       future: logsFuture,
//       builder: (context, snapshot) {
//         if (!snapshot.hasData &&
//             snapshot.connectionState != ConnectionState.done) {
//           return const Center(child: CircularProgressIndicator.adaptive());
//         }
//         final result = snapshot.data;
//         if (result == null) {
//           return const Center(child: Text('تعذر تحميل السجل الآن'));
//         }
//         if (result.hasError) {
//           return _AdminLoadErrorState(
//             message: result.errorMessage!,
//             hint:
//                 'يمكنك تحديث اللوحة لاحقًا أو التحقق من اتصال الخادم إذا استمر التأخير.',
//           );
//         }
//         final logs = result.items;
//         if (logs.isEmpty) {
//           return Center(child: Text(result.emptyMessage));
//         }
//         return ListView.separated(
//           padding: const EdgeInsets.all(16),
//           itemCount: logs.length,
//           separatorBuilder: (_, __) => const SizedBox(height: 10),
//           itemBuilder: (context, index) {
//             final log = logs[index];
//             return Card(
//               child: ListTile(
//                 title: Text(log.action),
//                 subtitle: Text('${log.entityType} • ${log.entityId}'),
//                 trailing: Text(
//                   DateFormat(
//                     'yyyy/MM/dd HH:mm',
//                   ).format(log.createdAt.toLocal()),
//                 ),
//               ),
//             );
//           },
//         );
//       },
//     );
//   }
// }

// class _SystemErrorsTab extends StatelessWidget {
//   const _SystemErrorsTab({required this.errorsFuture});

//   final Future<_AdminLoadResult<ChatSystemError>> errorsFuture;

//   @override
//   Widget build(BuildContext context) {
//     return FutureBuilder<_AdminLoadResult<ChatSystemError>>(
//       future: errorsFuture,
//       builder: (context, snapshot) {
//         if (!snapshot.hasData &&
//             snapshot.connectionState != ConnectionState.done) {
//           return const Center(child: CircularProgressIndicator.adaptive());
//         }
//         final result = snapshot.data;
//         if (result == null) {
//           return const Center(child: Text('تعذر تحميل الأخطاء الآن'));
//         }
//         if (result.hasError) {
//           return _AdminLoadErrorState(
//             message: result.errorMessage!,
//             hint:
//                 'لو استمر هذا التأخير فالأقرب أن الخادم بطيء أو أن سجل الأخطاء كبير جدًا.',
//           );
//         }
//         final errors = result.items;
//         if (errors.isEmpty) {
//           return Center(child: Text(result.emptyMessage));
//         }
//         return ListView.separated(
//           padding: const EdgeInsets.all(16),
//           itemCount: errors.length,
//           separatorBuilder: (_, __) => const SizedBox(height: 10),
//           itemBuilder: (context, index) {
//             final error = errors[index];
//             return Card(
//               child: ExpansionTile(
//                 title: Text('${error.statusCode} • ${error.errorName}'),
//                 subtitle: Text(error.path),
//                 childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
//                 children: [
//                   Align(
//                     alignment: Alignment.centerRight,
//                     child: Text(error.message),
//                   ),
//                   const SizedBox(height: 8),
//                   Align(
//                     alignment: Alignment.centerRight,
//                     child: Text(
//                       '${error.method} • ${DateFormat('yyyy/MM/dd HH:mm').format(error.createdAt.toLocal())}',
//                     ),
//                   ),
//                   if (error.stack != null && error.stack!.isNotEmpty) ...[
//                     const SizedBox(height: 12),
//                     Container(
//                       width: double.infinity,
//                       padding: const EdgeInsets.all(12),
//                       decoration: BoxDecoration(
//                         color: Theme.of(
//                           context,
//                         ).colorScheme.surfaceContainerHighest,
//                         borderRadius: BorderRadius.circular(14),
//                       ),
//                       child: SelectableText(error.stack!),
//                     ),
//                   ],
//                 ],
//               ),
//             );
//           },
//         );
//       },
//     );
//   }
// }

// class _AdminLoadErrorState extends StatelessWidget {
//   const _AdminLoadErrorState({required this.message, required this.hint});

//   final String message;
//   final String hint;

//   @override
//   Widget build(BuildContext context) {
//     final scheme = Theme.of(context).colorScheme;
//     return Center(
//       child: ConstrainedBox(
//         constraints: const BoxConstraints(maxWidth: 520),
//         child: Card(
//           elevation: 0,
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(24),
//             side: BorderSide(color: scheme.error.withValues(alpha: 0.18)),
//           ),
//           child: Padding(
//             padding: const EdgeInsets.all(22),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Icon(Icons.error_outline, color: scheme.error, size: 36),
//                 const SizedBox(height: 12),
//                 Text(
//                   message,
//                   textAlign: TextAlign.center,
//                   style: Theme.of(context).textTheme.titleMedium?.copyWith(
//                     color: scheme.error,
//                     fontWeight: FontWeight.w700,
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 Text(
//                   hint,
//                   textAlign: TextAlign.center,
//                   style: Theme.of(context).textTheme.bodyMedium,
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/admin_announcement.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/managed_user.dart';
import '../../../shared/models/remote_document.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/button_loading_indicator.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../../admin/presentation/backup_screen.dart';
import '../../admin/presentation/update_management_screen.dart';
import '../../admin/presentation/server_settings_screen.dart';
import '../models/chat_models.dart';

class ChatAdminPanel extends ConsumerStatefulWidget {
  const ChatAdminPanel({
    super.key,
    required this.departments,
    required this.branches,
    required this.manageableConversations,
    required this.users,
    required this.roles,
    required this.usersState,
    required this.currentUser,
    this.initialTabIndex = 0,
    this.onTabChanged,
  });

  final List<DepartmentSummary> departments;
  final List<BranchSummary> branches;
  final List<ChatConversation> manageableConversations;
  final List<ChatDirectoryUser> users;
  final List<ChatRole> roles;
  final AsyncValue<List<ManagedUser>> usersState;
  final AppUser currentUser;
  final int initialTabIndex;
  final ValueChanged<int>? onTabChanged;

  @override
  ConsumerState<ChatAdminPanel> createState() => _ChatAdminPanelState();
}

class _ChatAdminPanelState extends ConsumerState<ChatAdminPanel>
    with SingleTickerProviderStateMixin {
  late Future<_AdminLoadResult<ChatAuditLog>> _auditLogsFuture;
  late Future<_AdminLoadResult<ChatSystemError>> _systemErrorsFuture;
  late TabController _tabController;
  List<String> _visibleTabKeys = const <String>[];

  @override
  void initState() {
    super.initState();
    _rebuildTabController(preferredIndex: widget.initialTabIndex);
    _reloadLogs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureUsersLoaded();
    });
  }

  Future<void> _ensureUsersLoaded() async {
    if (!widget.currentUser.isAdmin &&
        !widget.currentUser.can('canCreateUsers')) {
      return;
    }
    final usersState = ref.read(usersControllerProvider);
    if (usersState.hasError ||
        usersState.isLoading ||
        usersState.valueOrNull == null) {
      await ref.read(usersControllerProvider.notifier).refresh();
    }
  }

  @override
  void didUpdateWidget(covariant ChatAdminPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextTabs = _allowedTabKeys();
    if (_visibleTabKeys.length != nextTabs.length ||
        !_sameTabLabels(_visibleTabKeys, nextTabs)) {
      _rebuildTabController();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reloadLogs() {
    final controller = ref.read(chatOverviewControllerProvider.notifier);
    _auditLogsFuture = _safeLoad(
      () => controller.fetchAuditLogs(limit: 200),
      emptyMessage: 'لا توجد أحداث إدارية مسجلة',
    );
    _systemErrorsFuture = _safeLoad(
      () => controller.fetchSystemErrors(limit: 200),
      emptyMessage: 'لا توجد أخطاء نظامية مسجلة',
    );
  }

  Future<_AdminLoadResult<T>> _safeLoad<T>(
    Future<List<T>> Function() loader, {
    required String emptyMessage,
  }) async {
    try {
      final items = await loader();
      return _AdminLoadResult(items: items, emptyMessage: emptyMessage);
    } catch (error) {
      return _AdminLoadResult(
        items: const [],
        emptyMessage: emptyMessage,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> _refreshAll() async {
    await ref.read(chatOverviewControllerProvider.notifier).refresh();
    await ref.read(usersControllerProvider.notifier).refresh();
    await ref.read(adminAnnouncementsControllerProvider.notifier).refresh();
    await ref.read(adminDocumentsControllerProvider.notifier).refresh();
    if (mounted) {
      setState(_reloadLogs);
    }
  }

  bool _can(String permission) =>
      widget.currentUser.isAdmin || widget.currentUser.can(permission);

  bool _sameTabLabels(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  List<String> _allowedTabKeys() {
    final tabs = <String>[
      if (_can('canManageAnnouncements')) 'announcements',
      if (_can('canCreateUsers')) 'users',
      if (_can('canManageFiles')) 'files',
      if (_can('canCreateDepartments')) 'departments',
      if (_can('canManageBranches')) 'branches',
      if (_can('canCreateRooms') || _can('canSendBroadcast')) 'rooms',
      if (_can('canManageRoles')) 'roles',
      if (_can('canViewDepartmentLogs')) 'audit',
      if (_can('canManageSystem')) 'errors',
      if (_can('canManageSystem')) 'server',
      if (_can('canManageUpdates')) 'updates',
      if (_can('canManageBackups')) 'backups',
    ];
    return tabs.isEmpty ? const <String>['blocked'] : tabs;
  }

  List<_AdminPanelTabData> _buildVisibleTabs({
    required AsyncValue<List<AdminAnnouncement>> announcementsState,
    required AsyncValue<List<RemoteDocument>> documentsState,
  }) {
    final tabs = <_AdminPanelTabData>[
      if (_visibleTabKeys.contains('announcements'))
        _AdminPanelTabData(
          label: 'الإعلانات',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign),
            label: Text('الإعلانات'),
          ),
          mobileTab: const Tab(text: 'الإعلانات'),
          child: _AnnouncementsAdminTab(announcementsState: announcementsState),
        ),
      if (_visibleTabKeys.contains('users'))
        _AdminPanelTabData(
          label: 'المستخدمون',
          destination: const NavigationRailDestination(
            icon: Icon(Iconsax.people),
            selectedIcon: Icon(Iconsax.people5),
            label: Text('المستخدمون'),
          ),
          mobileTab: const Tab(text: 'المستخدمون'),
          child: _UsersAdminTab(
            departments: widget.departments,
            branches: widget.branches,
            usersState: widget.usersState,
          ),
        ),
      if (_visibleTabKeys.contains('files'))
        _AdminPanelTabData(
          label: 'الملفات',
          destination: const NavigationRailDestination(
            icon: Icon(Iconsax.folder),
            selectedIcon: Icon(Iconsax.folder5),
            label: Text('الملفات'),
          ),
          mobileTab: const Tab(text: 'الملفات'),
          child: _AdminDocumentsTab(documentsState: documentsState),
        ),
      if (_visibleTabKeys.contains('departments'))
        _AdminPanelTabData(
          label: 'الأقسام',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.domain_add),
            selectedIcon: Icon(Icons.domain_add_outlined),
            label: Text('الأقسام'),
          ),
          mobileTab: const Tab(text: 'الأقسام'),
          child: _DepartmentsAdminTab(
            departments: widget.departments,
            users: widget.users,
          ),
        ),
      if (_visibleTabKeys.contains('branches'))
        _AdminPanelTabData(
          label: 'الفروع',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.account_tree_outlined),
            selectedIcon: Icon(Icons.account_tree),
            label: Text('الفروع'),
          ),
          mobileTab: const Tab(text: 'الفروع'),
          child: _BranchesAdminTab(branches: widget.branches),
        ),
      if (_visibleTabKeys.contains('rooms'))
        _AdminPanelTabData(
          label: 'الغرف',
          destination: const NavigationRailDestination(
            icon: Icon(Iconsax.message),
            selectedIcon: Icon(Iconsax.message5),
            label: Text('الغرف'),
          ),
          mobileTab: const Tab(text: 'الغرف'),
          child: _RoomsAdminTab(
            conversations: widget.manageableConversations,
            users: widget.users,
          ),
        ),
      if (_visibleTabKeys.contains('roles'))
        _AdminPanelTabData(
          label: 'الصلاحيات',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(Icons.admin_panel_settings),
            label: Text('الصلاحيات'),
          ),
          mobileTab: const Tab(text: 'الصلاحيات'),
          child: _RolesAdminTab(roles: widget.roles),
        ),
      if (_visibleTabKeys.contains('audit'))
        _AdminPanelTabData(
          label: 'السجل',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: Text('السجل'),
          ),
          mobileTab: const Tab(text: 'السجل'),
          child: _AuditLogsTab(logsFuture: _auditLogsFuture),
        ),
      if (_visibleTabKeys.contains('errors'))
        _AdminPanelTabData(
          label: 'الأخطاء',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.error_outline),
            selectedIcon: Icon(Icons.error),
            label: Text('الأخطاء'),
          ),
          mobileTab: const Tab(text: 'الأخطاء'),
          child: _SystemErrorsTab(errorsFuture: _systemErrorsFuture),
        ),
      if (_visibleTabKeys.contains('server'))
        _AdminPanelTabData(
          label: 'الخادم',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.settings_ethernet_outlined),
            selectedIcon: Icon(Icons.settings_ethernet),
            label: Text('الخادم'),
          ),
          mobileTab: const Tab(text: 'الخادم'),
          child: const ServerSettingsScreen(),
        ),
      if (_visibleTabKeys.contains('updates'))
        _AdminPanelTabData(
          label: 'التحديث',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.update_outlined),
            selectedIcon: Icon(Icons.update),
            label: Text('التحديث'),
          ),
          mobileTab: const Tab(text: 'التحديث'),
          child: const UpdateManagementScreen(),
        ),
      if (_visibleTabKeys.contains('backups'))
        _AdminPanelTabData(
          label: 'النسخ الاحتياطي',
          destination: const NavigationRailDestination(
            icon: Icon(Icons.backup_outlined),
            selectedIcon: Icon(Icons.backup),
            label: Text('النسخ الاحتياطي'),
          ),
          mobileTab: const Tab(text: 'نسخ احتياطي'),
          child: const BackupScreen(),
        ),
    ];

    if (tabs.isNotEmpty) {
      return tabs;
    }

    return const <_AdminPanelTabData>[
      _AdminPanelTabData(
        label: 'غير متاح',
        destination: NavigationRailDestination(
          icon: Icon(Icons.block_outlined),
          selectedIcon: Icon(Icons.block),
          label: Text('غير متاح'),
        ),
        mobileTab: Tab(text: 'غير متاح'),
        child: _PermissionDeniedTab(),
      ),
    ];
  }

  void _handleTabChanged() {
    if (!_tabController.indexIsChanging) {
      widget.onTabChanged?.call(_tabController.index);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _rebuildTabController({int? preferredIndex}) {
    final nextTabs = _allowedTabKeys();
    final nextIndex = (preferredIndex ?? _tabControllerOrNull?.index ?? 0)
        .clamp(0, nextTabs.length - 1);
    final previous = _tabControllerOrNull;
    previous?.removeListener(_handleTabChanged);
    _tabController = TabController(
      length: nextTabs.length,
      vsync: this,
      initialIndex: nextIndex,
    );
    _tabController.addListener(_handleTabChanged);
    _visibleTabKeys = nextTabs;
    previous?.dispose();
  }

  TabController? get _tabControllerOrNull {
    try {
      return _tabController;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width >= 1100;
    final isTablet = size.width >= 800;
    final visibleTabs = _buildVisibleTabs(
      announcementsState: ref.watch(adminAnnouncementsControllerProvider),
      documentsState: ref.watch(adminDocumentsControllerProvider),
    );
    final navDestinations = visibleTabs
        .map((entry) => entry.destination)
        .toList();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Row(
        children: [
          if (isTablet)
            NavigationRail(
              extended: isDesktop,
              selectedIndex: _tabController.index,
              onDestinationSelected: (index) => _tabController.animateTo(index),
              destinations: navDestinations,
              backgroundColor: theme.colorScheme.surfaceContainerLow,
              selectedLabelTextStyle: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelTextStyle: theme.textTheme.labelLarge,
            ),
          if (isTablet)
            VerticalDivider(
              thickness: 1,
              width: 1,
              color: theme.dividerColor.withOpacity(0.2),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    border: Border(
                      bottom: BorderSide(
                        color: theme.dividerColor.withOpacity(0.2),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (!isTablet)
                        Expanded(
                          child: TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            dividerColor: Colors.transparent,
                            tabs: visibleTabs
                                .map((entry) => entry.mobileTab)
                                .toList(),
                          ),
                        )
                      else
                        Expanded(
                          child: Text(
                            (navDestinations[_tabController.index].label
                                        as Text)
                                    .data ??
                                'لوحة الإدارة',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      const SizedBox(width: 16),
                      FilledButton.tonalIcon(
                        onPressed: _refreshAll,
                        icon: const Icon(Iconsax.refresh),
                        label: const Text('تحديث'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    physics: isTablet
                        ? const NeverScrollableScrollPhysics()
                        : const ScrollPhysics(),
                    children: visibleTabs.map((entry) => entry.child).toList(),
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

class _AdminLoadResult<T> {
  const _AdminLoadResult({
    required this.items,
    required this.emptyMessage,
    this.errorMessage,
  });

  final List<T> items;
  final String emptyMessage;
  final String? errorMessage;

  bool get hasError => errorMessage != null && errorMessage!.trim().isNotEmpty;
}

class _AdminPanelTabData {
  const _AdminPanelTabData({
    required this.label,
    required this.destination,
    required this.mobileTab,
    required this.child,
  });

  final String label;
  final NavigationRailDestination destination;
  final Tab mobileTab;
  final Widget child;
}

class _PermissionDeniedTab extends StatelessWidget {
  const _PermissionDeniedTab();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('ليس لديك صلاحية لفتح هذه الصفحة'));
  }
}

// ---------------- Helper for consistent TextFields in Dialogs ----------------
InputDecoration _dialogInputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    filled: true,
  );
}

// ---------------- Admin Documents Tab ----------------

class _AdminDocumentsTab extends ConsumerStatefulWidget {
  const _AdminDocumentsTab({required this.documentsState});

  final AsyncValue<List<RemoteDocument>> documentsState;

  @override
  ConsumerState<_AdminDocumentsTab> createState() => _AdminDocumentsTabState();
}

class _AdminDocumentsTabState extends ConsumerState<_AdminDocumentsTab> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RemoteDocument> _filter(List<RemoteDocument> documents) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return documents;
    return documents.where((document) {
      final owner =
          '${document.ownerFullName ?? ''} ${document.ownerUsername ?? ''}'
              .toLowerCase();
      return document.fileName.toLowerCase().contains(query) ||
          owner.contains(query);
    }).toList();
  }

  Future<void> _downloadAndOpen(RemoteDocument document) async {
    try {
      final localPath = await ref
          .read(documentRepositoryProvider)
          .downloadDocument(document);
      await OpenFilex.open(localPath);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _renameDocument(RemoteDocument document) async {
    final controller = TextEditingController(text: document.fileName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعادة تسمية الملف'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: _dialogInputDecoration('اسم الملف'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;
    try {
      await ref
          .read(documentRepositoryProvider)
          .renameDocument(document.id, result);
      await ref.read(adminDocumentsControllerProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تحديث اسم الملف')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteDocument(RemoteDocument document) async {
    final shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('حذف الملف'),
            content: Text('هل تريد حذف "${document.fileName}" نهائيًا؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حذف'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldDelete) return;

    try {
      await ref.read(documentRepositoryProvider).deleteDocument(document.id);
      await ref.read(adminDocumentsControllerProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حذف الملف')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: _dialogInputDecoration(
                    'ابحث باسم الملف أو صاحبه',
                  ).copyWith(prefixIcon: const Icon(Iconsax.search_normal)),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: () => ref
                    .read(adminDocumentsControllerProvider.notifier)
                    .refresh(),
                icon: const Icon(Iconsax.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: widget.documentsState.when(
              loading: () => const _AdminTableLoadingShimmer(),
              error: (error, stackTrace) =>
                  Center(child: Text(error.toString())),
              data: (documents) {
                final filtered = _filter(documents);
                return Card(
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).dividerColor.withOpacity(0.5),
                    ),
                  ),
                  child: ListView.separated(
                    itemCount: filtered.length + 1,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Theme.of(context).dividerColor.withOpacity(0.3),
                    ),
                    itemBuilder: (context, index) {
                      if (index == filtered.length) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: OutlinedButton.icon(
                            onPressed: () => ref
                                .read(adminDocumentsControllerProvider.notifier)
                                .loadMore(),
                            icon: const Icon(Icons.expand_more_rounded),
                            label: const Text('تحميل المزيد'),
                          ),
                        );
                      }
                      final document = filtered[index];
                      final owner =
                          document.ownerFullName?.trim().isNotEmpty == true
                          ? document.ownerFullName!
                          : (document.ownerUsername ?? 'غير معروف');
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        title: Text(
                          document.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '$owner • ${document.pageCount} صفحة • ${formatFileSize(document.fileSize)} • ${formatDate(document.createdAt)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'فتح',
                              onPressed: () => _downloadAndOpen(document),
                              icon: const Icon(Iconsax.folder_open5),
                            ),
                            IconButton(
                              tooltip: 'إعادة تسمية',
                              onPressed: () => _renameDocument(document),
                              icon: const Icon(Iconsax.edit),
                            ),
                            IconButton(
                              tooltip: 'حذف',
                              onPressed: () => _deleteDocument(document),
                              icon: Icon(
                                Iconsax.note_remove5,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Users Admin Tab ----------------

String _departmentName(List<DepartmentSummary> departments, String? id) {
  if (id == null) return 'بدون قسم';
  return departments
          .where((department) => department.id == id)
          .map((department) => department.name)
          .firstOrNull ??
      'بدون قسم';
}

List<String> _managedUserDepartmentIds(ManagedUser user) {
  if (user.departmentIds.isNotEmpty) {
    return user.departmentIds;
  }
  return [if (user.departmentId != null) user.departmentId!];
}

String _managedUserDepartmentNames(
  List<DepartmentSummary> departments,
  ManagedUser user,
) {
  final ids = _managedUserDepartmentIds(user);
  if (ids.isEmpty) {
    return _departmentName(departments, null);
  }
  final names = ids
      .map((id) => _departmentName(departments, id))
      .where((name) => name.trim().isNotEmpty)
      .toSet()
      .toList();
  return names.isEmpty ? _departmentName(departments, null) : names.join('، ');
}

String _branchName(List<BranchSummary> branches, String? id) {
  if (id == null) return 'بدون فرع';
  return branches
          .where((branch) => branch.id == id)
          .map((branch) => branch.name)
          .firstOrNull ??
      'بدون فرع';
}

class _UsersAdminTab extends ConsumerStatefulWidget {
  const _UsersAdminTab({
    required this.departments,
    required this.branches,
    required this.usersState,
  });

  final List<DepartmentSummary> departments;
  final List<BranchSummary> branches;
  final AsyncValue<List<ManagedUser>> usersState;

  @override
  ConsumerState<_UsersAdminTab> createState() => _UsersAdminTabState();
}

class _UsersAdminTabState extends ConsumerState<_UsersAdminTab> {
  final _searchController = TextEditingController();
  String? _departmentFilter;
  String? _branchFilter;
  String? _roleFilter;
  String _statusFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ManagedUser> _filterUsers(List<ManagedUser> users) {
    final query = _searchController.text.trim().toLowerCase();
    return users.where((user) {
      final departmentName = _managedUserDepartmentNames(
        widget.departments,
        user,
      ).toLowerCase();
      final branchName = _branchName(
        widget.branches,
        user.branchId,
      ).toLowerCase();
      final searchable =
          '${user.username} ${user.fullName} ${user.branchCode} $departmentName $branchName'
              .toLowerCase();
      if (query.isNotEmpty && !searchable.contains(query)) return false;
      if (_departmentFilter != null &&
          !_managedUserDepartmentIds(user).contains(_departmentFilter)) {
        return false;
      }
      if (_branchFilter != null && user.branchId != _branchFilter) {
        return false;
      }
      if (_roleFilter != null && user.role != _roleFilter) return false;
      if (_statusFilter == 'active' && !user.isActive) return false;
      if (_statusFilter == 'inactive' && user.isActive) return false;
      return true;
    }).toList();
  }

  Future<void> _deleteUser(BuildContext context, ManagedUser user) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المستخدم'),
        content: Text(
          'هل تريد حذف ${user.fullName.isEmpty ? user.username : user.fullName} نهائيا؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await ref.read(userManagementRepositoryProvider).deleteUser(user.id);
      await ref.read(usersControllerProvider.notifier).refresh();
      await ref.read(chatOverviewControllerProvider.notifier).refresh();
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('تم حذف المستخدم بنجاح')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _forceLogoutAll(BuildContext context, ManagedUser user) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل خروج من كل الأجهزة'),
        content: Text(
          'هل تريد فرض تسجيل الخروج لـ ${user.fullName.isEmpty ? user.username : user.fullName} من جميع الأجهزة النشطة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await ref
          .read(userManagementRepositoryProvider)
          .forceLogoutAllDevices(user.id);
      await ref.read(usersControllerProvider.notifier).refresh();
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('تم تسجيل خروج المستخدم من جميع الأجهزة بنجاح'),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showResetPasswordDialog(
    BuildContext context,
    WidgetRef ref,
    ManagedUser user,
  ) async {
    final userRepository = ref.read(userManagementRepositoryProvider);
    final passwordController = TextEditingController(text: '123456');
    var isSaving = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(
            'إعادة تعيين كلمة المرور لـ ${user.fullName.isEmpty ? user.username : user.fullName}',
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: passwordController,
                  enabled: !isSaving,
                  decoration: _dialogInputDecoration('كلمة المرور الجديدة'),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: isSaving
                  ? null
                  : () async {
                      final password = passwordController.text.trim();
                      if (password.length < 6) {
                        setLocalState(() {
                          errorText =
                              'كلمة المرور يجب أن تكون 6 أحرف على الأقل.';
                        });
                        return;
                      }
                      setLocalState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        await userRepository.resetPassword(
                          userId: user.id,
                          password: password,
                        );
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تمت إعادة تعيين كلمة المرور بنجاح'),
                          ),
                        );
                      } catch (error) {
                        setLocalState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              icon: const Icon(Icons.lock_reset_outlined),
              label: isSaving
                  ? const Text('جار الحفظ...')
                  : const Text('إعادة التعيين'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUserDialog(
    BuildContext context,
    WidgetRef ref, {
    ManagedUser? user,
  }) async {
    final userRepository = ref.read(userManagementRepositoryProvider);
    final usersController = ref.read(usersControllerProvider.notifier);
    final overviewController = ref.read(
      chatOverviewControllerProvider.notifier,
    );

    final usernameController = TextEditingController(
      text: user?.username ?? '',
    );
    final fullNameController = TextEditingController(
      text: user?.fullName ?? '',
    );
    final passwordController = TextEditingController();
    var role = user?.role ?? 'user';
    String? departmentId = user?.departmentId;
    String? branchId = user?.branchId;
    final permissions = Map<String, bool>.from(user?.permissions ?? const {});
    const permissionLabels = <String, String>{
      'canCreateUsers': 'إدارة المستخدمين',
      'canCreateDepartments': 'إدارة الأقسام',
      'canManageBranches': 'إدارة الفروع',
      'canCreateRooms': 'إنشاء غرف',
      'canSendBroadcast': 'إرسال بث',
      'canDeleteMessages': 'حذف رسائل',
      'canUploadFiles': 'رفع ملفات',
      'canModerateDepartment': 'إدارة محادثات القسم',
      'canViewDepartmentLogs': 'عرض السجل',
      'canManageAnnouncements': 'إدارة الإعلانات',
      'canManageFiles': 'إدارة الملفات',
      'canManageRoles': 'إدارة الصلاحيات',
      'canManageSystem': 'إعدادات الخادم',
      'canManageUpdates': 'إدارة التحديثات',
      'canManageBackups': 'النسخ الاحتياطي',
      'canManageTickets': 'إدارة التذاكر',
      'canViewPrinters': 'عرض صفحة الطابعات',
      'canManagePrinters': 'إدارة فروع الطابعات',
      'canSyncPrinters': 'مزامنة الطابعات',
      'canExportPrinterReports': 'تصدير تقارير الطابعات',
      'canViewItAssets': 'عرض صفحة إدارة أصول IT',
      'canManageItAssets': 'إضافة وتعديل الأجهزة وقطع الغيار',
      'canExecuteItAssets': 'إنشاء وتنفيذ الحركات والصيانة والجرد',
      'canAuditItAssets': 'مراجعة واعتماد حركات أصول IT',
      'canManageItInventory': 'إنشاء وإغلاق جلسات الجرد وحل الفروق',
      'canInspectDamagedItAssets': 'فحص التالف واتخاذ القرار والتكهين',
      'canManageItProcurement': 'إدارة الموردين وطلبات الشراء',
      'canExportItReports': 'تصدير وطباعة تقارير أصول IT',
      'canManageItSettings': 'إدارة قواعد الاعتماد وإعدادات الوحدة',
      'canCloseItPeriods': 'قفل الفترات الشهرية',
      'canScanItAssets': 'مسح QR/Barcode للأجهزة وعرض بياناتها',
      'canScanItSpareParts': 'مسح QR/Barcode لقطع الغيار وعرض بياناتها',
      'canScanItInventory': 'تسجيل مسح الأجهزة داخل جلسات الجرد',
      'canDeleteItAssets': 'أرشفة وحذف الأجهزة وقطع الغيار',
      'canViewSnipeit': 'عرض صفحة Snipe-IT',
    };
    Map<String, bool> resolvePermissionsForRole() {
      if (role != 'admin') {
        return permissions;
      }
      return {for (final key in permissionLabels.keys) key: true};
    }

    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(user == null ? 'إضافة مستخدم' : 'تعديل مستخدم'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: usernameController,
                    enabled: !isSaving,
                    decoration: _dialogInputDecoration('اسم المستخدم'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: fullNameController,
                    enabled: !isSaving,
                    decoration: _dialogInputDecoration('الاسم الكامل'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: _dialogInputDecoration('الدور'),
                    items: const [
                      DropdownMenuItem(value: 'user', child: Text('user')),
                      DropdownMenuItem(
                        value: 'manager',
                        child: Text('manager'),
                      ),
                      DropdownMenuItem(value: 'admin', child: Text('admin')),
                    ],
                    onChanged: isSaving
                        ? null
                        : (value) => setLocalState(() {
                            role = value ?? role;
                            if (role == 'admin') {
                              for (final key in permissionLabels.keys) {
                                permissions[key] = true;
                              }
                            }
                          }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: departmentId,
                    decoration: _dialogInputDecoration('القسم'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('بدون قسم'),
                      ),
                      ...widget.departments.map(
                        (department) => DropdownMenuItem<String?>(
                          value: department.id,
                          child: Text(department.name),
                        ),
                      ),
                    ],
                    onChanged: isSaving
                        ? null
                        : (value) => departmentId = value,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: branchId,
                    decoration: _dialogInputDecoration('الفرع'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('بدون فرع'),
                      ),
                      ...widget.branches.map(
                        (branch) => DropdownMenuItem<String?>(
                          value: branch.id,
                          child: Text(branch.name),
                        ),
                      ),
                    ],
                    onChanged: isSaving ? null : (value) => branchId = value,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    enabled: !isSaving,
                    decoration:
                        _dialogInputDecoration(
                          user == null
                              ? 'كلمة المرور'
                              : 'كلمة مرور جديدة أو إعادة تعيينها',
                        ).copyWith(
                          helperText: user == null
                              ? 'اتركها فارغة لاستخدام 123456 أو اكتب 6 أحرف على الأقل'
                              : 'اتركها فارغة لو لن تغيّر كلمة المرور',
                        ),
                  ),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('صلاحيات مخصصة للمستخدم'),
                    children: [
                      for (final entry in permissionLabels.entries)
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(entry.value),
                          value: permissions[entry.key] == true,
                          onChanged: isSaving
                              ? null
                              : (value) => setLocalState(
                                  () => permissions[entry.key] = value,
                                ),
                        ),
                    ],
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final username = usernameController.text.trim();
                      final fullName = fullNameController.text.trim();
                      final password = passwordController.text.trim();
                      if (username.isEmpty) {
                        setLocalState(() => errorText = 'اسم المستخدم مطلوب.');
                        return;
                      }
                      if (fullName.isEmpty) {
                        setLocalState(() => errorText = 'الاسم الكامل مطلوب.');
                        return;
                      }
                      if (password.isNotEmpty && password.length < 6) {
                        setLocalState(
                          () => errorText =
                              'كلمة المرور يجب أن تكون 6 أحرف على الأقل.',
                        );
                        return;
                      }
                      setLocalState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        final effectivePermissions =
                            resolvePermissionsForRole();
                        if (user == null) {
                          await userRepository.createUser(
                            username: username,
                            fullName: fullName,
                            password: password.isEmpty ? '123456' : password,
                            role: role,
                            departmentId: departmentId,
                            branchId: branchId,
                            permissions: effectivePermissions,
                          );
                        } else {
                          await userRepository.updateUser(
                            userId: user.id,
                            username: username,
                            fullName: fullName,
                            password: password,
                            role: role,
                            departmentId: departmentId,
                            branchId: branchId,
                            permissions: effectivePermissions,
                          );
                        }
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (error) {
                        setLocalState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ButtonLoadingIndicator(),
                    )
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && context.mounted) {
      await usersController.refresh();
      await overviewController.refresh();
      if (!context.mounted) return;
      final actionLabel = user == null
          ? 'تم إنشاء المستخدم بنجاح.'
          : 'تم تحديث المستخدم بنجاح.';
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(actionLabel)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => _showUserDialog(context, ref),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('إضافة مستخدم'),
              ),
              const Spacer(),
              IconButton.filledTonal(
                onPressed: () =>
                    ref.read(usersControllerProvider.notifier).refresh(),
                icon: const Icon(Iconsax.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: _dialogInputDecoration(
                    'بحث بالاسم أو الفرع أو القسم أو اسم المستخدم',
                  ).copyWith(prefixIcon: const Icon(Icons.search)),
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _departmentFilter,
                  decoration: _dialogInputDecoration('القسم'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('كل الأقسام'),
                    ),
                    ...widget.departments.map(
                      (department) => DropdownMenuItem<String?>(
                        value: department.id,
                        child: Text(department.name),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _departmentFilter = value),
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _branchFilter,
                  decoration: _dialogInputDecoration('الفرع'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('كل الفروع'),
                    ),
                    ...widget.branches.map(
                      (branch) => DropdownMenuItem<String?>(
                        value: branch.id,
                        child: Text(branch.name),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _branchFilter = value),
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _roleFilter,
                  decoration: _dialogInputDecoration('الدور'),
                  items: const [
                    DropdownMenuItem<String?>(value: null, child: Text('الكل')),
                    DropdownMenuItem(value: 'admin', child: Text('admin')),
                    DropdownMenuItem(value: 'manager', child: Text('manager')),
                    DropdownMenuItem(value: 'user', child: Text('user')),
                  ],
                  onChanged: (value) => setState(() => _roleFilter = value),
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _statusFilter,
                  decoration: _dialogInputDecoration('الحالة'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('الكل')),
                    DropdownMenuItem(value: 'active', child: Text('نشط')),
                    DropdownMenuItem(value: 'inactive', child: Text('موقوف')),
                  ],
                  onChanged: (value) =>
                      setState(() => _statusFilter = value ?? 'all'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: widget.usersState.when(
              loading: () => const _AdminTableLoadingShimmer(),
              error: (error, stackTrace) =>
                  Center(child: Text(error.toString())),
              data: (users) {
                final filteredUsers = _filterUsers(users);
                return Card(
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).dividerColor.withOpacity(0.5),
                    ),
                  ),
                  child: ListView.separated(
                    itemCount: filteredUsers.length + 1,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Theme.of(context).dividerColor.withOpacity(0.3),
                    ),
                    itemBuilder: (context, index) {
                      if (index == filteredUsers.length) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: OutlinedButton.icon(
                            onPressed: () => ref
                                .read(usersControllerProvider.notifier)
                                .loadMore(),
                            icon: const Icon(Icons.expand_more_rounded),
                            label: const Text('تحميل المزيد'),
                          ),
                        );
                      }
                      final user = filteredUsers[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        title: Text(
                          user.fullName.isEmpty ? user.username : user.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${user.username} • ${user.role} • ${_managedUserDepartmentNames(widget.departments, user)} • ${_branchName(widget.branches, user.branchId)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        leading: Chip(
                          label: Text(user.isActive ? 'نشط' : 'موقوف'),
                          backgroundColor: user.isActive
                              ? Colors.green.withOpacity(0.1)
                              : Theme.of(
                                  context,
                                ).colorScheme.error.withOpacity(0.1),
                        ),
                        trailing: SizedBox(
                          width: 270,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: 'فرض تسجيل خروج من كل الأجهزة',
                                color: const Color(0xFFDC2626),
                                onPressed: () => _forceLogoutAll(context, user),
                                icon: const Icon(Icons.phonelink_erase_rounded),
                              ),
                              IconButton(
                                tooltip: 'إعادة تعيين كلمة المرور',
                                onPressed: () => _showResetPasswordDialog(
                                  context,
                                  ref,
                                  user,
                                ),
                                icon: const Icon(Iconsax.lock4),
                              ),
                              IconButton(
                                tooltip: 'تعديل',
                                onPressed: () =>
                                    _showUserDialog(context, ref, user: user),
                                icon: const Icon(Iconsax.edit),
                              ),
                              IconButton(
                                tooltip: 'حذف المستخدم',
                                color: Theme.of(context).colorScheme.error,
                                onPressed: () => _deleteUser(context, user),
                                icon: const Icon(Icons.delete_outline),
                              ),
                              _ManagedUserStatusSwitch(
                                userId: user.id,
                                isActive: user.isActive,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagedUserStatusSwitch extends ConsumerStatefulWidget {
  const _ManagedUserStatusSwitch({
    required this.userId,
    required this.isActive,
  });
  final String userId;
  final bool isActive;

  @override
  ConsumerState<_ManagedUserStatusSwitch> createState() =>
      _ManagedUserStatusSwitchState();
}

class _ManagedUserStatusSwitchState
    extends ConsumerState<_ManagedUserStatusSwitch> {
  late bool _isActive = widget.isActive;
  var _isSaving = false;

  @override
  void didUpdateWidget(covariant _ManagedUserStatusSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSaving && oldWidget.isActive != widget.isActive) {
      _isActive = widget.isActive;
    }
  }

  Future<void> _updateStatus(bool value) async {
    final previousValue = _isActive;
    setState(() {
      _isSaving = true;
      _isActive = value;
    });
    try {
      await ref
          .read(userManagementRepositoryProvider)
          .updateUserStatus(userId: widget.userId, isActive: value);
      await ref.read(usersControllerProvider.notifier).refresh();
      await ref.read(chatOverviewControllerProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            value ? 'تم تفعيل المستخدم بنجاح.' : 'تم إيقاف المستخدم بنجاح.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isActive = previousValue);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isSaving) {
      return const SizedBox(
        width: 28,
        height: 28,
        child: Padding(
          padding: EdgeInsets.all(4),
          child: ButtonLoadingIndicator(),
        ),
      );
    }
    return Switch(value: _isActive, onChanged: _updateStatus);
  }
}

// ---------------- Announcements Tab ----------------

class _BranchesAdminTab extends ConsumerStatefulWidget {
  const _BranchesAdminTab({required this.branches});

  final List<BranchSummary> branches;

  @override
  ConsumerState<_BranchesAdminTab> createState() => _BranchesAdminTabState();
}

class _BranchesAdminTabState extends ConsumerState<_BranchesAdminTab> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BranchSummary> _filteredBranches() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.branches;
    }
    return widget.branches.where((branch) {
      return branch.name.toLowerCase().contains(query) ||
          branch.code.toLowerCase().contains(query) ||
          branch.description.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _showBranchDialog(
    BuildContext context,
    WidgetRef ref, {
    BranchSummary? branch,
  }) async {
    final overviewController = ref.read(
      chatOverviewControllerProvider.notifier,
    );
    final nameController = TextEditingController(text: branch?.name ?? '');
    final codeController = TextEditingController(text: branch?.code ?? '');
    final descriptionController = TextEditingController(
      text: branch?.description ?? '',
    );
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(branch == null ? 'إضافة فرع' : 'تعديل فرع'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    enabled: !isSaving,
                    decoration: _dialogInputDecoration('اسم الفرع'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    enabled: !isSaving,
                    decoration: _dialogInputDecoration('كود الفرع'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    enabled: !isSaving,
                    decoration: _dialogInputDecoration('الوصف'),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final code = codeController.text.trim();
                      if (name.isEmpty) {
                        setLocalState(() => errorText = 'اسم الفرع مطلوب.');
                        return;
                      }
                      if (code.isEmpty) {
                        setLocalState(() => errorText = 'كود الفرع مطلوب.');
                        return;
                      }
                      setLocalState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        if (branch == null) {
                          await overviewController.createBranch(
                            name: name,
                            code: code,
                            description: descriptionController.text.trim(),
                          );
                        } else {
                          await overviewController.updateBranch(
                            branchId: branch.id,
                            name: name,
                            code: code,
                            description: descriptionController.text.trim(),
                          );
                        }
                        if (context.mounted) {
                          Navigator.pop(context, true);
                        }
                      } catch (error) {
                        setLocalState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ButtonLoadingIndicator(),
                    )
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (saved == true) {
      await overviewController.refresh();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            branch == null ? 'تم إنشاء الفرع بنجاح.' : 'تم تحديث الفرع بنجاح.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final branches = _filteredBranches();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => _showBranchDialog(context, ref),
                icon: const Icon(Iconsax.add),
                label: const Text('إضافة فرع'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: _dialogInputDecoration(
                    'بحث بالاسم أو الكود أو الوصف',
                  ).copyWith(prefixIcon: const Icon(Icons.search)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: branches.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final branch = branches[index];
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).dividerColor.withOpacity(0.5),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    title: Text(
                      branch.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${branch.code} • ${branch.description} • الأعضاء: ${branch.membersCount}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          onPressed: () =>
                              _showBranchDialog(context, ref, branch: branch),
                          icon: const Icon(Iconsax.edit),
                        ),
                        IconButton(
                          color: Theme.of(context).colorScheme.error,
                          onPressed: () async {
                            try {
                              await ref
                                  .read(chatOverviewControllerProvider.notifier)
                                  .deleteBranch(branch.id);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم حذف الفرع')),
                              );
                            } catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.toString())),
                              );
                            }
                          },
                          icon: const Icon(Iconsax.card_remove),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Announcements Tab ----------------

class _AnnouncementsAdminTab extends ConsumerWidget {
  const _AnnouncementsAdminTab({required this.announcementsState});
  final AsyncValue<List<AdminAnnouncement>> announcementsState;

  Color _toneColor(BuildContext context, String tone) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return switch (tone) {
      'success' => isDark ? Colors.green.shade400 : Colors.green.shade700,
      'warning' => isDark ? Colors.orange.shade400 : Colors.orange.shade700,
      'critical' => scheme.error,
      _ => scheme.primary,
    };
  }

  String _toneLabel(String tone) {
    return switch (tone) {
      'success' => 'نجاح',
      'warning' => 'تنبيه',
      'critical' => 'عاجل',
      _ => 'معلومة',
    };
  }

  Future<void> _showAnnouncementDialog(
    BuildContext context,
    WidgetRef ref, {
    AdminAnnouncement? announcement,
  }) async {
    final announcementRepository = ref.read(announcementRepositoryProvider);
    final adminAnnouncementsController = ref.read(
      adminAnnouncementsControllerProvider.notifier,
    );
    final announcementsController = ref.read(
      announcementsControllerProvider.notifier,
    );

    final titleController = TextEditingController(
      text: announcement?.title ?? '',
    );
    final messageController = TextEditingController(
      text: announcement?.message ?? '',
    );
    var tone = announcement?.tone ?? 'info';
    var isPinned = announcement?.isPinned == true;
    var isActive = announcement?.isActive != false;
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(announcement == null ? 'إضافة إعلان' : 'تعديل إعلان'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    enabled: !isSaving,
                    decoration: _dialogInputDecoration('العنوان'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: messageController,
                    enabled: !isSaving,
                    minLines: 3,
                    maxLines: 5,
                    decoration: _dialogInputDecoration('نص الإعلان'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: tone,
                    decoration: _dialogInputDecoration('النوع'),
                    items: const [
                      DropdownMenuItem(value: 'info', child: Text('معلومة')),
                      DropdownMenuItem(value: 'success', child: Text('نجاح')),
                      DropdownMenuItem(value: 'warning', child: Text('تنبيه')),
                      DropdownMenuItem(value: 'critical', child: Text('عاجل')),
                    ],
                    onChanged: isSaving
                        ? null
                        : (value) => tone = value ?? tone,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: isPinned,
                    onChanged: isSaving
                        ? null
                        : (value) => setLocalState(() => isPinned = value),
                    title: const Text('تثبيت في البداية'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    value: isActive,
                    onChanged: isSaving
                        ? null
                        : (value) => setLocalState(() => isActive = value),
                    title: const Text('نشط'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final title = titleController.text.trim();
                      final message = messageController.text.trim();
                      if (title.length < 2) {
                        setLocalState(
                          () => errorText =
                              'العنوان يجب أن يكون حرفين على الأقل.',
                        );
                        return;
                      }
                      if (message.length < 4) {
                        setLocalState(
                          () => errorText = 'نص الإعلان قصير جدًا.',
                        );
                        return;
                      }
                      setLocalState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        if (announcement == null) {
                          await announcementRepository.createAnnouncement(
                            title: title,
                            message: message,
                            tone: tone,
                            isPinned: isPinned,
                            isActive: isActive,
                          );
                        } else {
                          await announcementRepository.updateAnnouncement(
                            announcementId: announcement.id,
                            title: title,
                            message: message,
                            tone: tone,
                            isPinned: isPinned,
                            isActive: isActive,
                          );
                        }
                        if (!context.mounted) return;
                        Navigator.pop(context, true);
                      } catch (error) {
                        setLocalState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ButtonLoadingIndicator(),
                    )
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && context.mounted) {
      await adminAnnouncementsController.refresh();
      await announcementsController.refresh();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => _showAnnouncementDialog(context, ref),
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('إضافة إعلان'),
              ),
              const Spacer(),
              IconButton.filledTonal(
                onPressed: () => ref
                    .read(adminAnnouncementsControllerProvider.notifier)
                    .refresh(),
                icon: const Icon(Iconsax.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: announcementsState.when(
              loading: () => const _AdminTableLoadingShimmer(),
              error: (error, stackTrace) =>
                  Center(child: Text(error.toString())),
              data: (announcements) => ListView.separated(
                itemCount: announcements.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final announcement = announcements[index];
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Theme.of(context).dividerColor.withOpacity(0.5),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  announcement.title,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Switch(
                                value: announcement.isActive,
                                onChanged: (value) async {
                                  await ref
                                      .read(announcementRepositoryProvider)
                                      .updateAnnouncementStatus(
                                        announcementId: announcement.id,
                                        isActive: value,
                                      );
                                  await ref
                                      .read(
                                        adminAnnouncementsControllerProvider
                                            .notifier,
                                      )
                                      .refresh();
                                  await ref
                                      .read(
                                        announcementsControllerProvider
                                            .notifier,
                                      )
                                      .refresh();
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(announcement.message),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(
                                label: Text(_toneLabel(announcement.tone)),
                                backgroundColor: _toneColor(
                                  context,
                                  announcement.tone,
                                ).withOpacity(0.12),
                                side: BorderSide.none,
                              ),
                              if (announcement.isPinned)
                                const Chip(
                                  label: Text('مثبت'),
                                  side: BorderSide.none,
                                ),
                              Chip(
                                label: Text(
                                  announcement.isActive ? 'نشط' : 'متوقف',
                                ),
                                side: BorderSide.none,
                              ),
                              Chip(
                                label: Text(
                                  formatEgyptDateTime(
                                    announcement.updatedAt,
                                    separator: ' • ',
                                  ),
                                ),
                                side: BorderSide.none,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () => _showAnnouncementDialog(
                                  context,
                                  ref,
                                  announcement: announcement,
                                ),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('تعديل'),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.error,
                                ),
                                onPressed: () async {
                                  await ref
                                      .read(announcementRepositoryProvider)
                                      .deleteAnnouncement(announcement.id);
                                  await ref
                                      .read(
                                        adminAnnouncementsControllerProvider
                                            .notifier,
                                      )
                                      .refresh();
                                  await ref
                                      .read(
                                        announcementsControllerProvider
                                            .notifier,
                                      )
                                      .refresh();
                                },
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('حذف'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Departments Admin Tab ----------------

class _DepartmentsAdminTab extends ConsumerStatefulWidget {
  const _DepartmentsAdminTab({required this.departments, required this.users});
  final List<DepartmentSummary> departments;
  final List<ChatDirectoryUser> users;

  @override
  ConsumerState<_DepartmentsAdminTab> createState() =>
      _DepartmentsAdminTabState();
}

class _DepartmentsAdminTabState extends ConsumerState<_DepartmentsAdminTab> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DepartmentSummary> _filteredDepartments() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.departments;
    }
    return widget.departments.where((department) {
      return department.name.toLowerCase().contains(query) ||
          department.code.toLowerCase().contains(query) ||
          department.description.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _showDepartmentDialog(
    BuildContext context,
    WidgetRef ref, {
    DepartmentSummary? department,
  }) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final overviewController = container.read(
      chatOverviewControllerProvider.notifier,
    );

    final nameController = TextEditingController(text: department?.name ?? '');
    final codeController = TextEditingController(text: department?.code ?? '');
    final descriptionController = TextEditingController(
      text: department?.description ?? '',
    );
    final selectedManagers = <String>{
      ...department?.managers ?? const <String>[],
    };
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(department == null ? 'إضافة قسم' : 'تعديل قسم'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    enabled: !isSaving,
                    decoration: _dialogInputDecoration('اسم القسم'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    enabled: !isSaving,
                    decoration: _dialogInputDecoration('الكود'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    enabled: !isSaving,
                    decoration: _dialogInputDecoration('الوصف'),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'المديرون',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...widget.users
                      .where(
                        (entry) =>
                            entry.role == 'manager' || entry.role == 'admin',
                      )
                      .map(
                        (entry) => CheckboxListTile(
                          value: selectedManagers.contains(entry.id),
                          title: Text(entry.displayName),
                          subtitle: Text(entry.username),
                          onChanged: isSaving
                              ? null
                              : (value) {
                                  setLocalState(() {
                                    if (value == true) {
                                      selectedManagers.add(entry.id);
                                    } else {
                                      selectedManagers.remove(entry.id);
                                    }
                                  });
                                },
                        ),
                      ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final code = codeController.text.trim();
                      if (name.isEmpty) {
                        setLocalState(() => errorText = 'اسم القسم مطلوب.');
                        return;
                      }
                      if (code.isEmpty) {
                        setLocalState(() => errorText = 'كود القسم مطلوب.');
                        return;
                      }
                      setLocalState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        if (department == null) {
                          await overviewController.createDepartment(
                            name: name,
                            code: code,
                            description: descriptionController.text.trim(),
                          );
                        } else {
                          await overviewController.updateDepartment(
                            departmentId: department.id,
                            name: name,
                            code: code,
                            description: descriptionController.text.trim(),
                            managers: selectedManagers.toList(),
                          );
                        }
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (error) {
                        setLocalState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ButtonLoadingIndicator(),
                    )
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (saved == true) {
      await overviewController.refresh();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            department == null
                ? 'تم إنشاء القسم بنجاح.'
                : 'تم تحديث القسم بنجاح.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments = _filteredDepartments();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => _showDepartmentDialog(context, ref),
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('إضافة قسم'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: _dialogInputDecoration(
                    'بحث بالاسم أو الكود أو الوصف',
                  ).copyWith(prefixIcon: const Icon(Icons.search)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: departments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final department = departments[index];
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).dividerColor.withOpacity(0.5),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    title: Text(
                      department.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${department.code} • ${department.description} • الأعضاء: ${department.membersCount}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          onPressed: () => _showDepartmentDialog(
                            context,
                            ref,
                            department: department,
                          ),
                          icon: const Icon(Iconsax.edit),
                        ),
                        IconButton(
                          color: Theme.of(context).colorScheme.error,
                          onPressed: () async {
                            try {
                              await ref
                                  .read(chatOverviewControllerProvider.notifier)
                                  .deleteDepartment(department.id);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم حذف القسم')),
                              );
                            } catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.toString())),
                              );
                            }
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Rooms Admin Tab ----------------

class _RoomsAdminTab extends ConsumerWidget {
  const _RoomsAdminTab({required this.conversations, required this.users});
  final List<ChatConversation> conversations;
  final List<ChatDirectoryUser> users;

  Future<void> _showCreateBroadcastDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final overviewController = ref.read(
      chatOverviewControllerProvider.notifier,
    );
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final selectedPublishers = <String>{};
    final selectedAdmins = <String>{};
    var isSaving = false;
    String? errorText;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('إنشاء قناة بث'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    enabled: !isSaving,
                    decoration: _dialogInputDecoration('اسم القناة'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    enabled: !isSaving,
                    minLines: 1,
                    maxLines: 3,
                    decoration: _dialogInputDecoration('الوصف'),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'المرسلون',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...users.map(
                    (user) => CheckboxListTile(
                      value: selectedPublishers.contains(user.id),
                      title: Text(user.displayName),
                      subtitle: Text(user.username),
                      onChanged: isSaving
                          ? null
                          : (value) {
                              setLocalState(() {
                                if (value == true) {
                                  selectedPublishers.add(user.id);
                                } else {
                                  selectedPublishers.remove(user.id);
                                  selectedAdmins.remove(user.id);
                                }
                              });
                            },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'مشرفو البث',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...users
                      .where((user) => selectedPublishers.contains(user.id))
                      .map(
                        (user) => CheckboxListTile(
                          value: selectedAdmins.contains(user.id),
                          title: Text(user.displayName),
                          subtitle: Text(user.username),
                          onChanged: isSaving
                              ? null
                              : (value) {
                                  setLocalState(() {
                                    if (value == true) {
                                      selectedAdmins.add(user.id);
                                    } else {
                                      selectedAdmins.remove(user.id);
                                    }
                                  });
                                },
                        ),
                      ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'ملاحظة: المرسل يحدد الأقسام المستهدفة عند إرسال الرسالة.',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        setLocalState(() => errorText = 'اسم القناة مطلوب.');
                        return;
                      }
                      setLocalState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        await overviewController.createConversation(
                          type: 'broadcast',
                          name: name,
                          description: descriptionController.text.trim(),
                          memberIds: selectedPublishers.toList(),
                          adminIds: selectedAdmins.toList(),
                        );
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (error) {
                        setLocalState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ButtonLoadingIndicator(),
                    )
                  : const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );
    if (created == true && context.mounted) {
      await overviewController.refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء قناة البث بنجاح')),
        );
      }
    }
  }

  Future<void> _showRoomDialog(
    BuildContext context,
    WidgetRef ref, {
    required ChatConversation conversation,
  }) async {
    final overviewController = ref.read(
      chatOverviewControllerProvider.notifier,
    );
    final nameController = TextEditingController(text: conversation.name);
    final descriptionController = TextEditingController(
      text: conversation.description,
    );
    final isBroadcast = conversation.type == 'broadcast';
    final selectedMembers = <String>{
      ...(isBroadcast
          ? conversation.broadcastPublisherIds
          : conversation.members.map((entry) => entry.id)),
    };
    final selectedAdmins = <String>{
      ...conversation.admins.map((entry) => entry.id),
    };
    var isArchived = conversation.isArchived;
    var isActive = conversation.isActive;
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('إدارة الغرفة'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    enabled: !isSaving,
                    decoration: _dialogInputDecoration('الاسم'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    enabled: !isSaving,
                    decoration: _dialogInputDecoration('الوصف'),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: isArchived,
                    title: const Text('مؤرشفة'),
                    contentPadding: EdgeInsets.zero,
                    onChanged: isSaving
                        ? null
                        : (value) => setLocalState(() => isArchived = value),
                  ),
                  SwitchListTile(
                    value: isActive,
                    title: const Text('نشطة'),
                    contentPadding: EdgeInsets.zero,
                    onChanged: isSaving
                        ? null
                        : (value) => setLocalState(() => isActive = value),
                  ),
                  const Divider(height: 28),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      isBroadcast ? 'المرسلون' : 'الأعضاء',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ...users.map(
                    (user) => CheckboxListTile(
                      value: selectedMembers.contains(user.id),
                      title: Text(user.displayName),
                      subtitle: Text(user.username),
                      onChanged: isSaving
                          ? null
                          : (value) {
                              setLocalState(() {
                                if (value == true) {
                                  selectedMembers.add(user.id);
                                } else {
                                  selectedMembers.remove(user.id);
                                  selectedAdmins.remove(user.id);
                                }
                              });
                            },
                    ),
                  ),
                  const Divider(height: 28),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      isBroadcast ? 'مشرفو البث' : 'المشرفون',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ...users
                      .where((user) => selectedMembers.contains(user.id))
                      .map(
                        (user) => CheckboxListTile(
                          value: selectedAdmins.contains(user.id),
                          title: Text(user.displayName),
                          subtitle: Text(user.username),
                          onChanged: isSaving
                              ? null
                              : (value) {
                                  setLocalState(() {
                                    if (value == true) {
                                      selectedAdmins.add(user.id);
                                    } else {
                                      selectedAdmins.remove(user.id);
                                    }
                                  });
                                },
                        ),
                      ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) {
                        setLocalState(() => errorText = 'اسم الغرفة مطلوب.');
                        return;
                      }
                      setLocalState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        await overviewController.updateManagedConversation(
                          conversationId: conversation.id,
                          name: nameController.text.trim(),
                          description: descriptionController.text.trim(),
                          memberIds: selectedMembers.toList(),
                          adminIds: selectedAdmins.toList(),
                          isArchived: isArchived,
                          isActive: isActive,
                        );
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (error) {
                        setLocalState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ButtonLoadingIndicator(),
                    )
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && context.mounted) await overviewController.refresh();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUser = ref.watch(authControllerProvider).valueOrNull;
    final canSendBroadcast =
        authUser?.role == 'admin' || authUser?.can('canSendBroadcast') == true;

    final roomsView = conversations.isEmpty
        ? const Center(child: Text('لا توجد غرف قابلة للإدارة'))
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListView.separated(
              itemCount: conversations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final conversation = conversations[index];
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).dividerColor.withOpacity(0.5),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    title: Text(
                      conversation.displayTitle(''),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${conversation.type} • ${conversation.isActive ? 'نشطة' : 'معطلة'} • أعضاء: ${conversation.members.length} • مشرفون: ${conversation.admins.length}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          onPressed: () => _showRoomDialog(
                            context,
                            ref,
                            conversation: conversation,
                          ),
                          icon: const Icon(Iconsax.setting),
                        ),
                        IconButton(
                          color: Theme.of(context).colorScheme.error,
                          onPressed: () async {
                            try {
                              await ref
                                  .read(chatOverviewControllerProvider.notifier)
                                  .deleteManagedConversation(conversation.id);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم حذف الغرفة')),
                              );
                            } catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.toString())),
                              );
                            }
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Text(
                'إدارة الغرف والقنوات',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (canSendBroadcast)
                FilledButton.icon(
                  onPressed: () => _showCreateBroadcastDialog(context, ref),
                  icon: const Icon(Icons.campaign_outlined),
                  label: const Text('إنشاء قناة بث'),
                ),
            ],
          ),
        ),
        Expanded(child: roomsView),
      ],
    );
  }
}

// ---------------- Roles Admin Tab ----------------

class _RolesAdminTab extends ConsumerStatefulWidget {
  const _RolesAdminTab({required this.roles});
  final List<ChatRole> roles;
  @override
  ConsumerState<_RolesAdminTab> createState() => _RolesAdminTabState();
}

class _RolesAdminTabState extends ConsumerState<_RolesAdminTab> {
  late Map<String, ChatPermissionSet> _draftPermissions;

  bool _samePermissions(ChatPermissionSet a, ChatPermissionSet b) {
    return a.canCreateUsers == b.canCreateUsers &&
        a.canCreateDepartments == b.canCreateDepartments &&
        a.canCreateRooms == b.canCreateRooms &&
        a.canSendBroadcast == b.canSendBroadcast &&
        a.canDeleteMessages == b.canDeleteMessages &&
        a.canUploadFiles == b.canUploadFiles &&
        a.canModerateDepartment == b.canModerateDepartment &&
        a.canViewDepartmentLogs == b.canViewDepartmentLogs &&
        a.canManageAnnouncements == b.canManageAnnouncements &&
        a.canManageFiles == b.canManageFiles &&
        a.canManageBranches == b.canManageBranches &&
        a.canManageRoles == b.canManageRoles &&
        a.canManageSystem == b.canManageSystem &&
        a.canManageUpdates == b.canManageUpdates &&
        a.canManageBackups == b.canManageBackups &&
        a.canManageTickets == b.canManageTickets &&
        a.canViewPrinters == b.canViewPrinters &&
        a.canManagePrinters == b.canManagePrinters &&
        a.canSyncPrinters == b.canSyncPrinters &&
        a.canExportPrinterReports == b.canExportPrinterReports &&
        a.canViewSnipeit == b.canViewSnipeit;
  }

  bool _hasServerRolesChanged(List<ChatRole> previous, List<ChatRole> next) {
    if (identical(previous, next)) {
      return false;
    }
    if (previous.length != next.length) {
      return true;
    }
    for (var i = 0; i < previous.length; i++) {
      final before = previous[i];
      final after = next[i];
      if (before.id != after.id ||
          before.roleName != after.roleName ||
          !_samePermissions(before.permissions, after.permissions)) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _draftPermissions = {
      for (final role in widget.roles) role.id: role.permissions,
    };
  }

  @override
  void didUpdateWidget(covariant _RolesAdminTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasServerRolesChanged(oldWidget.roles, widget.roles)) {
      return;
    }
    _draftPermissions = {
      for (final role in widget.roles) role.id: role.permissions,
    };
  }

  ChatPermissionSet _updatePermission(
    ChatPermissionSet source,
    String key,
    bool value,
  ) {
    return ChatPermissionSet(
      canCreateUsers: key == 'canCreateUsers' ? value : source.canCreateUsers,
      canCreateDepartments: key == 'canCreateDepartments'
          ? value
          : source.canCreateDepartments,
      canCreateRooms: key == 'canCreateRooms' ? value : source.canCreateRooms,
      canSendBroadcast: key == 'canSendBroadcast'
          ? value
          : source.canSendBroadcast,
      canDeleteMessages: key == 'canDeleteMessages'
          ? value
          : source.canDeleteMessages,
      canUploadFiles: key == 'canUploadFiles' ? value : source.canUploadFiles,
      canModerateDepartment: key == 'canModerateDepartment'
          ? value
          : source.canModerateDepartment,
      canViewDepartmentLogs: key == 'canViewDepartmentLogs'
          ? value
          : source.canViewDepartmentLogs,
      canManageAnnouncements: key == 'canManageAnnouncements'
          ? value
          : source.canManageAnnouncements,
      canManageFiles: key == 'canManageFiles' ? value : source.canManageFiles,
      canManageBranches: key == 'canManageBranches'
          ? value
          : source.canManageBranches,
      canManageRoles: key == 'canManageRoles' ? value : source.canManageRoles,
      canManageSystem: key == 'canManageSystem'
          ? value
          : source.canManageSystem,
      canManageUpdates: key == 'canManageUpdates'
          ? value
          : source.canManageUpdates,
      canManageBackups: key == 'canManageBackups'
          ? value
          : source.canManageBackups,
      canManageTickets: key == 'canManageTickets'
          ? value
          : source.canManageTickets,
      canViewPrinters: key == 'canViewPrinters'
          ? value
          : source.canViewPrinters,
      canManagePrinters: key == 'canManagePrinters'
          ? value
          : source.canManagePrinters,
      canSyncPrinters: key == 'canSyncPrinters'
          ? value
          : source.canSyncPrinters,
      canExportPrinterReports: key == 'canExportPrinterReports'
          ? value
          : source.canExportPrinterReports,
      canViewSnipeit: key == 'canViewSnipeit' ? value : source.canViewSnipeit,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: widget.roles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final role = widget.roles[index];
        final draft = _draftPermissions[role.id] ?? role.permissions;

        Widget permissionSwitch(String key, String label, bool currentValue) {
          return SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(label),
            value: currentValue,
            onChanged: (value) {
              setState(() {
                _draftPermissions[role.id] = _updatePermission(
                  draft,
                  key,
                  value,
                );
              });
            },
          );
        }

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Theme.of(context).dividerColor.withOpacity(0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role.roleName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canCreateUsers',
                        'إنشاء مستخدمين',
                        draft.canCreateUsers,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canCreateDepartments',
                        'إنشاء أقسام',
                        draft.canCreateDepartments,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canCreateRooms',
                        'إنشاء غرف',
                        draft.canCreateRooms,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canSendBroadcast',
                        'إرسال إعلانات',
                        draft.canSendBroadcast,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canDeleteMessages',
                        'حذف الرسائل',
                        draft.canDeleteMessages,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canUploadFiles',
                        'رفع الملفات',
                        draft.canUploadFiles,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canModerateDepartment',
                        'إدارة محادثات القسم',
                        draft.canModerateDepartment,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canViewDepartmentLogs',
                        'عرض السجل الإداري',
                        draft.canViewDepartmentLogs,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canManageAnnouncements',
                        'إدارة الإعلانات',
                        draft.canManageAnnouncements,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canManageFiles',
                        'إدارة الملفات',
                        draft.canManageFiles,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canManageBranches',
                        'إدارة الفروع',
                        draft.canManageBranches,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canManageRoles',
                        'إدارة الصلاحيات',
                        draft.canManageRoles,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canManageSystem',
                        'إعدادات الخادم',
                        draft.canManageSystem,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canManageUpdates',
                        'إدارة التحديثات',
                        draft.canManageUpdates,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canManageBackups',
                        'النسخ الاحتياطي',
                        draft.canManageBackups,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canManageTickets',
                        'إدارة التذاكر',
                        draft.canManageTickets,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canViewPrinters',
                        'عرض صفحة الطابعات',
                        draft.canViewPrinters,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canManagePrinters',
                        'إدارة فروع الطابعات',
                        draft.canManagePrinters,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canSyncPrinters',
                        'مزامنة الطابعات',
                        draft.canSyncPrinters,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canExportPrinterReports',
                        'تصدير تقارير الطابعات',
                        draft.canExportPrinterReports,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: permissionSwitch(
                        'canViewSnipeit',
                        'عرض صفحة Snipe-IT',
                        draft.canViewSnipeit,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await ref
                          .read(chatOverviewControllerProvider.notifier)
                          .updateRole(
                            roleId: role.id,
                            permissions:
                                _draftPermissions[role.id] ?? role.permissions,
                          );
                    },
                    icon: const Icon(Iconsax.save_25),
                    label: const Text('حفظ الصلاحيات'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------- Audit Logs Tab ----------------

class _AuditLogsTab extends StatelessWidget {
  const _AuditLogsTab({required this.logsFuture});
  final Future<_AdminLoadResult<ChatAuditLog>> logsFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminLoadResult<ChatAuditLog>>(
      future: logsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData &&
            snapshot.connectionState != ConnectionState.done) {
          return const _AdminTableLoadingShimmer();
        }
        final result = snapshot.data;
        if (result == null) {
          return const Center(child: Text('تعذر تحميل السجل الآن'));
        }
        if (result.hasError) {
          return _AdminLoadErrorState(
            message: result.errorMessage!,
            hint: 'يمكنك تحديث اللوحة لاحقًا.',
          );
        }
        final logs = result.items;
        if (logs.isEmpty) return Center(child: Text(result.emptyMessage));

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: logs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final log = logs[index];
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).dividerColor.withOpacity(0.3),
                ),
              ),
              child: ListTile(
                title: Text(
                  log.action,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('${log.entityType} • ${log.entityId}'),
                trailing: Text(formatEgyptDateTime(log.createdAt)),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------- System Errors Tab ----------------

class _SystemErrorsTab extends StatelessWidget {
  const _SystemErrorsTab({required this.errorsFuture});
  final Future<_AdminLoadResult<ChatSystemError>> errorsFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminLoadResult<ChatSystemError>>(
      future: errorsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData &&
            snapshot.connectionState != ConnectionState.done) {
          return const _AdminTableLoadingShimmer();
        }
        final result = snapshot.data;
        if (result == null) {
          return const Center(child: Text('تعذر تحميل الأخطاء الآن'));
        }
        if (result.hasError) {
          return _AdminLoadErrorState(
            message: result.errorMessage!,
            hint: 'الخادم بطيء أو سجل الأخطاء كبير جدًا.',
          );
        }
        final errors = result.items;
        if (errors.isEmpty) return Center(child: Text(result.emptyMessage));

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: errors.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final error = errors[index];
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.error.withOpacity(0.5),
                ),
              ),
              child: ExpansionTile(
                title: Text(
                  '${error.statusCode} • ${error.errorName}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(error.path),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(error.message),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${error.method} • ${formatEgyptDateTime(error.createdAt)}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                  if (error.stack != null && error.stack!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: SelectableText(error.stack!),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------- Admin Load Error State ----------------

class _AdminLoadErrorState extends StatelessWidget {
  const _AdminLoadErrorState({required this.message, required this.hint});
  final String message;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: scheme.error.withOpacity(0.18)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: scheme.error, size: 36),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminTableLoadingShimmer extends StatelessWidget {
  const _AdminTableLoadingShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: const [
        ShimmerSkeleton(height: 48, borderRadius: 12),
        SizedBox(height: 10),
        ShimmerSkeleton(height: 64, borderRadius: 12),
        SizedBox(height: 8),
        ShimmerSkeleton(height: 64, borderRadius: 12),
        SizedBox(height: 8),
        ShimmerSkeleton(height: 64, borderRadius: 12),
      ],
    );
  }
}
