import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/button_loading_indicator.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../models/ticket_models.dart';
import 'tickets_ui_kit.dart';

typedef _TicketDateFormatter = String Function(DateTime value);

class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({
    super.key,
    this.embedded = false,
    this.initialTab = TicketTab.tickets,
    this.autoOpenCreateDialog = false,
    this.initialDraftTitle,
    this.initialDraftDescription,
    this.initialDraftPriority = 'normal',
    this.initialAttachmentInfo,
  });

  final bool embedded;
  final TicketTab initialTab;
  final bool autoOpenCreateDialog;
  final String? initialDraftTitle;
  final String? initialDraftDescription;
  final String initialDraftPriority;
  final String? initialAttachmentInfo;

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

enum TicketTab { tickets, complaints, suggestions }

extension TicketTabLabel on TicketTab {
  String get label => switch (this) {
    TicketTab.tickets => 'تذاكر الدعم',
    TicketTab.complaints => 'الشكاوى',
    TicketTab.suggestions => 'المقترحات',
  };
}

class _TicketsScreenState extends ConsumerState<TicketsScreen> {
  final _searchController = TextEditingController();
  late TicketTab _activeTab;
  bool _didAutoOpenDraft = false;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    if (widget.autoOpenCreateDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _didAutoOpenDraft) return;
        _didAutoOpenDraft = true;
        _showCreateTicketDialog(
          initialTitle: widget.initialDraftTitle,
          initialDescription: widget.initialDraftDescription,
          initialPriority: widget.initialDraftPriority,
          attachmentInfo: widget.initialAttachmentInfo,
        );
      });
    }
  }

  double _dialogWidth(BuildContext context, double preferredWidth) {
    final availableWidth = MediaQuery.sizeOf(context).width - 32;
    return math.max(280, math.min(preferredWidth, availableWidth));
  }

  double _dialogMaxHeight(BuildContext context) {
    return MediaQuery.sizeOf(context).height * 0.78;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showCreateTicketDialog({
    String? initialTitle,
    String? initialDescription,
    String initialPriority = 'normal',
    String? attachmentInfo,
  }) async {
    final titleController = TextEditingController(text: initialTitle ?? '');
    final descriptionController = TextEditingController(
      text: initialDescription ?? '',
    );
    String priority = initialPriority;
    String? selectedDepartmentId;
    List<dynamic> departments = [];
    var isSaving = false;
    String? errorText;

    try {
      final dio = ref.read(authenticatedApiClientProvider).dio;
      final res = await dio.get('/api/departments');
      departments =
          (res.data['departments'] as List<dynamic>?) ??
          ((res.data['data'] as Map<String, dynamic>?)?['departments']
              as List<dynamic>?) ??
          const <dynamic>[];
      if (departments.isNotEmpty) {
        Map<String, dynamic>? preferredItDept;
        for (final raw in departments) {
          if (raw is Map) {
            final name = (raw['name']?.toString() ?? '').toLowerCase();
            if (name.contains('it') ||
                name.contains('دعم') ||
                name.contains('تقني') ||
                name.contains('معلومات') ||
                name.contains('صيانة')) {
              preferredItDept = Map<String, dynamic>.from(raw);
              break;
            }
          }
        }
        final targetDept = preferredItDept ?? departments.first;
        selectedDepartmentId =
            targetDept['id']?.toString() ?? targetDept['_id']?.toString();
      }
    } catch (e) {
      errorText = e.toString();
    }

    if (!mounted) return;

    final themeColor = switch (_activeTab) {
      TicketTab.tickets => const Color(0xFF2563EB),
      TicketTab.complaints => const Color(0xFFEA580C),
      TicketTab.suggestions => const Color(0xFF7C3AED),
    };

    final typeIcon = switch (_activeTab) {
      TicketTab.tickets => Icons.support_agent_rounded,
      TicketTab.complaints => Icons.report_problem_rounded,
      TicketTab.suggestions => Icons.lightbulb_rounded,
    };

    final titleLabel = switch (_activeTab) {
      TicketTab.tickets => 'إنشاء تذكرة جديدة',
      TicketTab.complaints => 'تقديم شكوى جديدة',
      TicketTab.suggestions => 'تقديم مقترح جديد',
    };

    final subtitleLabel = switch (_activeTab) {
      TicketTab.tickets => 'تواصل مع فريق الدعم الفني لحل مشكلة تقنية',
      TicketTab.complaints => 'أرسل شكواك إلى القسم المعني لمتابعتها وحلها',
      TicketTab.suggestions => 'شاركنا أفكارك ومقترحاتك لتطوير بيئة العمل',
    };

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final dialogWidth = _dialogWidth(context, 480);
          final dialogHeight = _dialogMaxHeight(context);

          final borderColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE2E8F0);
          final surfaceColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
          final fieldFillColor = isDark ? const Color(0xFF242428) : const Color(0xFFF8FAFC);

          return Dialog(
            backgroundColor: surfaceColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: borderColor, width: 1),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: dialogWidth,
                maxHeight: dialogHeight,
              ),
              child: SizedBox(
                width: dialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: themeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(typeIcon, color: themeColor, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  titleLabel,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitleLabel,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: isSaving ? null : () => Navigator.pop(context),
                            style: IconButton.styleFrom(
                              foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Divider(height: 1, thickness: 1, color: borderColor),

                    // Form Body
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (attachmentInfo != null &&
                                attachmentInfo.trim().isNotEmpty) ...[
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: themeColor.withValues(alpha: 0.09),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: themeColor.withValues(alpha: 0.28),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.attachment_rounded,
                                      size: 18,
                                      color: themeColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'مرفق مُضمّن من المحادثة: $attachmentInfo',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: themeColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            // Title
                            const Text('عنوان الطلب *', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: titleController,
                              enabled: !isSaving,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                hintText: 'مثال: عطل في الطابعة أو تأخر في الطلب',
                                prefixIcon: Icon(Icons.title_rounded, color: themeColor, size: 18),
                                filled: true,
                                fillColor: fieldFillColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: themeColor, width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              ),
                            ),

                            const SizedBox(height: 14),

                            // Department
                            const Text('القسم الموجه إليه *', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              value: selectedDepartmentId,
                              isExpanded: true,
                              dropdownColor: surfaceColor,
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.apartment_rounded, color: themeColor, size: 18),
                                filled: true,
                                fillColor: fieldFillColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: themeColor, width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              ),
                              items: departments.map((dept) {
                                final id = dept['id']?.toString() ?? dept['_id']?.toString() ?? '';
                                final name = dept['name']?.toString() ?? 'قسم غير معروف';
                                return DropdownMenuItem(value: id, child: Text(name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)));
                              }).toList(),
                              onChanged: isSaving
                                  ? null
                                  : (value) => setLocalState(() => selectedDepartmentId = value),
                            ),

                            const SizedBox(height: 14),

                            // Priority chips
                            const Text('مستوى الأولوية', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                {'key': 'low', 'label': 'منخفضة', 'color': const Color(0xFF0D9488)},
                                {'key': 'normal', 'label': 'عادية', 'color': const Color(0xFF2563EB)},
                                {'key': 'high', 'label': 'عالية', 'color': const Color(0xFFEA580C)},
                                {'key': 'critical', 'label': 'حرجة', 'color': const Color(0xFFDC2626)},
                              ].map((prio) {
                                final key = prio['key'] as String;
                                final label = prio['label'] as String;
                                final color = prio['color'] as Color;
                                final isSelected = priority == key;

                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                                    child: InkWell(
                                      onTap: isSaving ? null : () => setLocalState(() => priority = key),
                                      borderRadius: BorderRadius.circular(10),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 150),
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? color.withValues(alpha: 0.12)
                                              : (isDark ? const Color(0xFF242428) : const Color(0xFFF1F5F9)),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isSelected ? color : Colors.transparent,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            label,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                              color: isSelected
                                                  ? color
                                                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),

                            const SizedBox(height: 14),

                            // Description
                            Text(
                              _activeTab == TicketTab.tickets ? 'وصف المشكلة بالتفصيل *' : 'التفاصيل والوصف *',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: descriptionController,
                              enabled: !isSaving,
                              minLines: 4,
                              maxLines: 6,
                              decoration: InputDecoration(
                                hintText: 'يرجى كتابة التفاصيل بوضوح لتسهيل المعالجة...',
                                alignLabelWithHint: true,
                                prefixIcon: Padding(
                                  padding: const EdgeInsets.only(bottom: 45),
                                  child: Icon(Icons.description_outlined, color: themeColor, size: 18),
                                ),
                                filled: true,
                                fillColor: fieldFillColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: themeColor, width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                            ),

                            if (errorText != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDC2626).withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        errorText!,
                                        style: const TextStyle(
                                          color: Color(0xFFDC2626),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    Divider(height: 1, thickness: 1, color: borderColor),

                    // Actions
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isSaving ? null : () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                            child: const Text('إلغاء'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    final title = titleController.text.trim();
                                    final description = descriptionController.text.trim();
                                    if (title.length < 4 || description.length < 4) {
                                      setLocalState(() {
                                        errorText = 'العنوان والوصف مطلوبان (4 أحرف على الأقل).';
                                      });
                                      return;
                                    }
                                    if (selectedDepartmentId == null) {
                                      setLocalState(() {
                                        errorText = 'يجب اختيار القسم الموجه إليه الطلب.';
                                      });
                                      return;
                                    }

                                    setLocalState(() {
                                      isSaving = true;
                                      errorText = null;
                                    });
                                    try {
                                      final ticketType = switch (_activeTab) {
                                        TicketTab.tickets => 'ticket',
                                        TicketTab.complaints => 'complaint',
                                        TicketTab.suggestions => 'suggestion',
                                      };

                                      await ref
                                          .read(ticketsControllerProvider.notifier)
                                          .createTicket(
                                            title: title,
                                            description: description,
                                            priority: priority,
                                            ticketType: ticketType,
                                            targetDepartmentId: selectedDepartmentId,
                                          );
                                      if (!context.mounted) return;
                                      Navigator.pop(context);
                                    } catch (error) {
                                      setLocalState(() {
                                        isSaving = false;
                                        errorText = error.toString();
                                      });
                                    }
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: themeColor,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            icon: isSaving
                                ? const ButtonLoadingIndicator(radius: 8)
                                : const Icon(Icons.send_rounded, size: 16),
                            label: Text(
                              isSaving ? 'جارٍ الإنشاء...' : 'إنشاء الآن',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSupportTeamDialog() async {
    final authUser = ref.read(authControllerProvider).valueOrNull;
    if (authUser?.role != 'admin') {
      return;
    }

    try {
      final data = await ref
          .read(ticketsControllerProvider.notifier)
          .fetchSupportUsers();
      final selectedIds = <String>{...data.supportAgentIds};
      final exportPermissionsByUserId = <String, Set<String>>{
        for (final user in data.users)
          user.id: <String>{...user.exportTicketTypes},
      };

      var isSaving = false;
      var searchText = '';
      String? errorText;

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final dialogWidth = _dialogWidth(context, 500);
            final dialogHeight = _dialogMaxHeight(context);
            final brandColor = const Color(0xFF2563EB);

            final borderColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE2E8F0);
            final surfaceColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
            final fieldFillColor = isDark ? const Color(0xFF242428) : const Color(0xFFF8FAFC);

            final query = searchText.trim().toLowerCase();
            final filteredUsers = data.users.where((user) {
              if (query.isEmpty) return true;
              return user.displayName.toLowerCase().contains(query) ||
                  user.username.toLowerCase().contains(query);
            }).toList();

            return Dialog(
              backgroundColor: surfaceColor,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: BorderSide(color: borderColor, width: 1),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: dialogWidth,
                  maxHeight: dialogHeight,
                ),
                child: SizedBox(
                  width: dialogWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: brandColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(Icons.admin_panel_settings_rounded, color: brandColor, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'إعداد فريق الدعم والصلاحيات',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'عيّن موظفي الدعم وحدّد صلاحيات التصدير',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: isSaving ? null : () => Navigator.pop(context),
                              style: IconButton.styleFrom(
                                foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),

                      Divider(height: 1, thickness: 1, color: borderColor),

                      // Search bar & summary
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Column(
                          children: [
                            TextField(
                              decoration: InputDecoration(
                                hintText: 'بحث في قائمة المستخدمين...',
                                prefixIcon: Icon(Icons.search_rounded, size: 18, color: brandColor),
                                filled: true,
                                fillColor: fieldFillColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: brandColor, width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              onChanged: (val) => setLocalState(() => searchText = val),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: brandColor.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'تم تحديد ${selectedIds.length} كأعضاء دعم',
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: brandColor),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${filteredUsers.length} مستخدم',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      Divider(height: 1, thickness: 1, color: borderColor),

                      // Users list
                      Expanded(
                        child: filteredUsers.isEmpty
                            ? Center(
                                child: Text(
                                  data.users.isEmpty ? 'لا يوجد مستخدمون بالنظام.' : 'لا توجد نتائج مطابقة لبحثك.',
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            : Scrollbar(
                                child: ListView.separated(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  itemCount: filteredUsers.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final user = filteredUsers[index];
                                    final isSelected = selectedIds.contains(user.id);
                                    final exportTypes = exportPermissionsByUserId[user.id] ?? <String>{};

                                    return Container(
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? brandColor.withValues(alpha: 0.05)
                                            : (isDark ? const Color(0xFF222226) : const Color(0xFFF8FAFC)),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isSelected
                                              ? brandColor.withValues(alpha: 0.35)
                                              : borderColor,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          InkWell(
                                            borderRadius: BorderRadius.circular(14),
                                            onTap: isSaving
                                                ? null
                                                : () {
                                                    setLocalState(() {
                                                      if (isSelected) {
                                                        selectedIds.remove(user.id);
                                                      } else {
                                                        selectedIds.add(user.id);
                                                      }
                                                    });
                                                  },
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 20,
                                                    height: 20,
                                                    decoration: BoxDecoration(
                                                      color: isSelected ? brandColor : Colors.transparent,
                                                      borderRadius: BorderRadius.circular(5),
                                                      border: Border.all(
                                                        color: isSelected ? brandColor : (isDark ? const Color(0xFF64748B) : const Color(0xFFCBD5E1)),
                                                        width: 1.5,
                                                      ),
                                                    ),
                                                    child: isSelected
                                                        ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                                                        : null,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  CircleAvatar(
                                                    radius: 16,
                                                    backgroundColor: brandColor.withValues(alpha: 0.15),
                                                    child: Text(
                                                      user.displayName.isNotEmpty
                                                          ? user.displayName[0].toUpperCase()
                                                          : '?',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w700,
                                                        color: brandColor,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          user.displayName,
                                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                                        ),
                                                        Text(
                                                          '@${user.username} • ${user.role}',
                                                          style: TextStyle(
                                                            fontSize: 11.5,
                                                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),

                                          if (isSelected) ...[
                                            Container(
                                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                                              decoration: BoxDecoration(
                                                color: brandColor.withValues(alpha: 0.04),
                                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
                                              ),
                                              child: Row(
                                                children: [
                                                  Text(
                                                    'تصدير:',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w700,
                                                      color: brandColor,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Wrap(
                                                    spacing: 4,
                                                    children: [
                                                      {'key': 'ticket', 'label': 'تذاكر', 'color': const Color(0xFF2563EB)},
                                                      {'key': 'complaint', 'label': 'شكاوى', 'color': const Color(0xFFEA580C)},
                                                      {'key': 'suggestion', 'label': 'مقترحات', 'color': const Color(0xFF7C3AED)},
                                                    ].map((perm) {
                                                      final key = perm['key'] as String;
                                                      final label = perm['label'] as String;
                                                      final color = perm['color'] as Color;
                                                      final hasPerm = exportTypes.contains(key);

                                                      return InkWell(
                                                        onTap: isSaving
                                                            ? null
                                                            : () {
                                                                setLocalState(() {
                                                                  if (hasPerm) {
                                                                    exportTypes.remove(key);
                                                                  } else {
                                                                    exportTypes.add(key);
                                                                  }
                                                                  exportPermissionsByUserId[user.id] = exportTypes;
                                                                });
                                                              },
                                                        borderRadius: BorderRadius.circular(6),
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                          decoration: BoxDecoration(
                                                            color: hasPerm ? color.withValues(alpha: 0.15) : Colors.transparent,
                                                            borderRadius: BorderRadius.circular(6),
                                                            border: Border.all(
                                                              color: hasPerm ? color : color.withValues(alpha: 0.3),
                                                            ),
                                                          ),
                                                          child: Text(
                                                            label,
                                                            style: TextStyle(
                                                              fontSize: 10.5,
                                                              fontWeight: hasPerm ? FontWeight.w700 : FontWeight.w500,
                                                              color: hasPerm ? color : color.withValues(alpha: 0.7),
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    }).toList(),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),

                      if (errorText != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: Text(
                            errorText!,
                            style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],

                      Divider(height: 1, thickness: 1, color: borderColor),

                      // Actions
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: isSaving ? null : () => Navigator.pop(context),
                              style: TextButton.styleFrom(
                                foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                              child: const Text('إلغاء'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      setLocalState(() {
                                        isSaving = true;
                                        errorText = null;
                                      });
                                      try {
                                        await ref
                                            .read(ticketsControllerProvider.notifier)
                                            .updateSupportAgents(
                                              selectedIds.toList(),
                                              exportPermissionsByUserId: {
                                                for (final entry in exportPermissionsByUserId.entries)
                                                  entry.key: entry.value.toList(),
                                              },
                                            );
                                        if (!context.mounted) return;
                                        Navigator.pop(context);
                                      } catch (error) {
                                        setLocalState(() {
                                          isSaving = false;
                                          errorText = error.toString();
                                        });
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: brandColor,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              icon: isSaving
                                  ? const ButtonLoadingIndicator(radius: 8)
                                  : const Icon(Icons.check_rounded, size: 16),
                              label: Text(
                                isSaving ? 'جارٍ الحفظ...' : 'حفظ التغييرات',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
  String _departmentHandlerTypeForTab() => switch (_activeTab) {
    TicketTab.complaints => 'complaint',
    TicketTab.suggestions => 'suggestion',
    TicketTab.tickets => 'ticket',
  };

  Future<void> _showDepartmentHandlersDialog() async {
    final authUser = ref.read(authControllerProvider).valueOrNull;
    if (authUser?.role != 'admin') return;

    await showDialog<void>(
      context: context,
      builder: (_) => _DepartmentHandlersDialog(
        handlerType: _departmentHandlerTypeForTab(),
      ),
    );
  }

  List<TicketItem> _filteredTickets(List<TicketItem> tickets) {
    final query = _searchController.text.trim().toLowerCase();

    final typeFiltered = tickets.where((t) {
      final type = t.ticketType;
      return switch (_activeTab) {
        TicketTab.tickets => type == 'ticket',
        TicketTab.complaints => type == 'complaint',
        TicketTab.suggestions => type == 'suggestion',
      };
    }).toList();

    if (query.isEmpty) {
      return typeFiltered;
    }
    return typeFiltered.where((ticket) {
      return ticket.ticketNumber.toLowerCase().contains(query) ||
          ticket.title.toLowerCase().contains(query) ||
          ticket.description.toLowerCase().contains(query);
    }).toList();
  }

  Widget _buildContent() {
    final authUser = ref.watch(authControllerProvider).valueOrNull;
    final ticketState = ref.watch(ticketsControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ticketState.when(
      loading: () => CustomScrollView(
        slivers: [
          if (!widget.embedded)
            SliverAppBar(
              pinned: true,
              leading: Navigator.canPop(context)
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      tooltip: 'رجوع',
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : null,
              title: const Text('جاري التحميل...'),
              backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
              surfaceTintColor: Colors.transparent,
            ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  ShimmerSkeleton(height: 136, borderRadius: 24),
                  SizedBox(height: 10),
                  ShimmerSkeleton(height: 56, borderRadius: 16),
                  SizedBox(height: 10),
                  ShimmerSkeleton(height: 132, borderRadius: 20),
                  SizedBox(height: 10),
                  ShimmerSkeleton(height: 132, borderRadius: 20),
                ],
              ),
            ),
          ),
        ],
      ),
      error: (error, _) => Center(child: Text(error.toString())),
      data: (data) {
        final tabTickets = data.tickets.where((ticket) {
          final type = ticket.ticketType;
          return switch (_activeTab) {
            TicketTab.tickets => type == 'ticket',
            TicketTab.complaints => type == 'complaint',
            TicketTab.suggestions => type == 'suggestion',
          };
        }).toList();

        final tickets = _filteredTickets(data.tickets);
        final dateFormat = formatEgyptDateTime;
        final openTickets = tabTickets
            .where((ticket) => ticket.status != 'closed')
            .length;
        final myAssignedTickets = authUser == null
            ? 0
            : tabTickets
                  .where((ticket) => ticket.assignedTo?.id == authUser.id)
                  .length;

        final searchHint = switch (_activeTab) {
          TicketTab.tickets => 'ابحث في التذاكر',
          TicketTab.complaints => 'ابحث في الشكاوى',
          TicketTab.suggestions => 'ابحث في المقترحات',
        };

        return RefreshIndicator(
          onRefresh: () =>
              ref.read(ticketsControllerProvider.notifier).refresh(),
          child: CustomScrollView(
            slivers: [
              if (!widget.embedded)
                SliverAppBar(
                  pinned: true,
                  leading: Navigator.canPop(context)
                      ? IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          tooltip: 'رجوع',
                          onPressed: () => Navigator.of(context).pop(),
                        )
                      : null,
                  title: Text(switch (_activeTab) {
                    TicketTab.tickets => 'تذاكر الدعم',
                    TicketTab.complaints => 'الشكاوى',
                    TicketTab.suggestions => 'المقترحات',
                  }),
                  backgroundColor: isDark
                      ? Colors.black
                      : const Color(0xFFF2F2F7),
                  surfaceTintColor: Colors.transparent,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _showCreateTicketDialog,
                    ),
                    if (authUser?.role == 'admin')
                      IconButton(
                        icon: const Icon(Icons.tune_rounded),
                        onPressed: _activeTab == TicketTab.tickets
                            ? _showSupportTeamDialog
                            : _showDepartmentHandlersDialog,
                      ),
                  ],
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    children: [
                      Container(
                        clipBehavior: Clip.antiAlias,
                        // padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.38,
                            ),
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: searchHint,
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchController.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'مسح',
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (tickets.isEmpty)
                        TicketsEmptyIllustration(
                          title: switch (_activeTab) {
                            TicketTab.tickets => 'لا توجد تذاكر حاليًا',
                            TicketTab.complaints => 'لا توجد شكاوى حاليًا',
                            TicketTab.suggestions => 'لا توجد مقترحات حاليًا',
                          },
                          subtitle: _searchController.text.trim().isEmpty
                              ? 'أنشئ طلباً جديداً وسيظهر لمسؤولي القسم المختار فقط.'
                              : 'لا توجد نتائج مطابقة لعبارة "${_searchController.text.trim()}".',
                          icon: switch (_activeTab) {
                            TicketTab.tickets => Icons.support_agent_rounded,
                            TicketTab.complaints =>
                              Icons.report_problem_rounded,
                            TicketTab.suggestions => Icons.lightbulb_rounded,
                          },
                          accent: switch (_activeTab) {
                            TicketTab.tickets => TicketsPalette.brand,
                            TicketTab.complaints => TicketsPalette.complaint,
                            TicketTab.suggestions => TicketsPalette.suggestion,
                          },
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1C1C1E)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (int i = 0; i < tickets.length; i++) ...[
                                ModernTicketCard(
                                  ticket: tickets[i],
                                  dateFormat: dateFormat,
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => TicketDetailsScreen(
                                        ticketId: tickets[i].id,
                                        initialTicket: tickets[i],
                                      ),
                                    ),
                                  ),
                                ),
                                if (i < tickets.length - 1)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      start: 16,
                                    ),
                                    child: Divider(
                                      height: 0.5,
                                      thickness: 0.5,
                                      color: colorScheme.outlineVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildContent();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      body: _buildContent(),
      bottomNavigationBar: BottomNavigationBar(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        selectedItemColor: TicketsPalette.brand,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        currentIndex: _activeTab.index,
        onTap: (index) {
          setState(() {
            _activeTab = TicketTab.values[index];
            _searchController.clear();
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.support_agent_outlined),
            activeIcon: Icon(Icons.support_agent_rounded),
            label: 'تذاكر',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.report_problem_outlined),
            activeIcon: Icon(Icons.report_problem_rounded),
            label: 'شكاوى',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.lightbulb_outline_rounded),
            activeIcon: Icon(Icons.lightbulb_rounded),
            label: 'مقترحات',
          ),
        ],
      ),
    );
  }
}

class TicketDetailsScreen extends ConsumerStatefulWidget {
  const TicketDetailsScreen({
    super.key,
    required this.ticketId,
    this.initialTicket,
  });

  final String ticketId;
  final TicketItem? initialTicket;

  @override
  ConsumerState<TicketDetailsScreen> createState() =>
      _TicketDetailsScreenState();
}

class _TicketDetailsScreenState extends ConsumerState<TicketDetailsScreen> {
  final _messageController = TextEditingController();
  bool _internalNote = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _changeStatus(TicketDetailsData details) async {
    final statuses = const [
      'open',
      'assigned',
      'in_progress',
      'waiting_branch',
      'resolved',
      'closed',
    ];
    final selected = await showModalBottomSheet<String>(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: statuses
              .map(
                (status) => ListTile(
                  title: Text(_statusLabel(status)),
                  trailing: details.ticket.status == status
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(context, status),
                ),
              )
              .toList(),
        ),
      ),
    );

    if (selected == null || selected == details.ticket.status) {
      return;
    }
    try {
      await ref
          .read(ticketDetailsControllerProvider(widget.ticketId).notifier)
          .updateStatus(selected);
      await ref.read(ticketsControllerProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _assignTicket(TicketDetailsData details) async {
    final departmentId = details.ticket.targetDepartmentId;
    List<TicketActor> departmentHandlers = [];
    List<TicketActor> allSupportUsers = [];

    try {
      if (departmentId != null && departmentId.isNotEmpty) {
        final handlerType = details.ticket.ticketType == 'complaint'
            ? 'complaint'
            : (details.ticket.ticketType == 'suggestion'
                  ? 'suggestion'
                  : 'ticket');
        departmentHandlers = await ref
            .read(ticketsControllerProvider.notifier)
            .fetchDepartmentHandlers(departmentId, handlerType: handlerType);
      }
      final supportData = await ref
          .read(ticketsControllerProvider.notifier)
          .fetchSupportUsers();
      allSupportUsers = supportData.users
          .map(
            (u) => TicketActor(
              id: u.id,
              username: u.username,
              fullName: u.fullName,
              role: u.role,
            ),
          )
          .toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في جلب المستخدمين: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return; // Skip assignment modal on failure
    }

    if (!mounted) return;

    final List<TicketActor> candidates = [];
    final seen = <String>{};
    for (final handler in departmentHandlers) {
      if (seen.add(handler.id)) candidates.add(handler);
    }
    for (final user in allSupportUsers) {
      if (seen.add(user.id)) candidates.add(user);
    }

    final selected = await showModalBottomSheet<String?>(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('بدون إسناد'),
              onTap: () => Navigator.pop(context, null),
            ),
            if (departmentHandlers.isNotEmpty)
              const ListTile(
                title: Text(
                  'مسؤولو القسم:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
              ),
            ...candidates.map((user) {
              final isHandler = departmentHandlers.any((h) => h.id == user.id);
              return ListTile(
                leading: Icon(
                  isHandler
                      ? Icons.admin_panel_settings_outlined
                      : Icons.person_outline,
                ),
                title: Text(user.displayName),
                subtitle: Text(user.username),
                trailing: details.ticket.assignedTo?.id == user.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, user.id),
              );
            }),
          ],
        ),
      ),
    );

    if (selected == null && selected == details.ticket.assignedTo?.id) {
      // No change
      return;
    }

    try {
      await ref
          .read(ticketDetailsControllerProvider(widget.ticketId).notifier)
          .assignTo(selected);
      await ref.read(ticketsControllerProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الإسناد: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendComment(TicketDetailsData details) async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      return;
    }
    try {
      await ref
          .read(ticketDetailsControllerProvider(widget.ticketId).notifier)
          .addComment(
            message,
            internalNote: _internalNote && details.canManage,
          );
      _messageController.clear();
      setState(() {
        _internalNote = false;
      });
      await ref.read(ticketsControllerProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailsState = ref.watch(
      ticketDetailsControllerProvider(widget.ticketId),
    );
    final dateFormat = formatEgyptDateTime;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? Colors.black : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text('تفاصيل التذكرة'),
        backgroundColor: scaffoldBg,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: () => ref
                .read(ticketDetailsControllerProvider(widget.ticketId).notifier)
                .refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: detailsState.when(
        loading: () {
          if (widget.initialTicket != null) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: [
                TicketDetailsHeaderCard(
                  ticket: widget.initialTicket!,
                  dateFormat: dateFormat,
                  canManage: false,
                ),
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ],
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
        error: (error, _) => Center(child: Text(error.toString())),
        data: (details) {
          final displayTicket = widget.initialTicket != null
              ? widget.initialTicket!.mergeWith(details.ticket)
              : details.ticket;
          final viewData = TicketDetailsData(
            ticket: displayTicket,
            updates: details.updates,
            settings: details.settings,
            canManage: details.canManage,
          );
          final ticketClosed = displayTicket.status == 'closed';
          final colorScheme = Theme.of(context).colorScheme;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  children: [
                    TicketDetailsHeaderCard(
                      ticket: displayTicket,
                      dateFormat: dateFormat,
                      canManage: viewData.canManage,
                      onChangeStatus: viewData.canManage
                          ? () => _changeStatus(viewData)
                          : null,
                      onAssign: viewData.canManage
                          ? () => _assignTicket(viewData)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'سجل التذكرة',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (details.updates.isEmpty)
                      const _TicketsEmptyState(
                        query: '',
                        title: 'لا توجد تحديثات بعد',
                        subtitle:
                            'ستظهر هنا كل الرسائل والإجراءات الخاصة بالتذكرة.',
                      )
                    else
                      ...details.updates.map(
                        (update) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TicketTimelineTile(
                            label: _kindLabel(update.kind),
                            message: _ticketUpdateDisplayMessage(update),
                            actor: update.createdBy.displayName,
                            visibilityLabel: _visibilityLabel(
                              update.visibility,
                            ),
                            timestamp: update.createdAt != null
                                ? dateFormat(update.createdAt!)
                                : '—',
                            accent: _kindColor(update.kind),
                            isInternal: update.visibility == 'internal',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (details.canManage)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Text(
                                'ملاحظة داخلية (فريق الدعم فقط)',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              Switch.adaptive(
                                value: _internalNote,
                                onChanged: ticketClosed
                                    ? null
                                    : (v) => setState(() => _internalNote = v),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF2C2C2E)
                                    : const Color(0xFFF2F2F7),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: TextField(
                                controller: _messageController,
                                enabled: !ticketClosed,
                                minLines: 1,
                                maxLines: 5,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText: ticketClosed
                                      ? 'التذكرة مغلقة'
                                      : 'رسالة...',
                                  hintStyle: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed:
                                ticketClosed ||
                                    _messageController.text.trim().isEmpty
                                ? null
                                : () => _sendComment(details),
                            icon: const Icon(
                              Icons.arrow_circle_up_rounded,
                              size: 36,
                            ),
                            color: TicketsPalette.brand,
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TicketsEmptyState extends StatelessWidget {
  const _TicketsEmptyState({
    required this.query,
    this.title = 'لا توجد تذاكر حاليًا',
    this.subtitle = 'يمكنك إنشاء تذكرة جديدة أو تعديل البحث لعرض النتائج.',
  });

  final String query;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.12),
            child: const Icon(
              Icons.confirmation_number_outlined,
              color: Color(0xFF2563EB),
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            query.isEmpty ? subtitle : 'لا توجد نتائج مطابقة لعبارة "$query".',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketDetailsHeaderCard extends StatelessWidget {
  const _TicketDetailsHeaderCard({
    required this.ticket,
    required this.dateFormat,
    required this.canManage,
    required this.onChangeStatus,
    required this.onAssign,
  });

  final TicketItem ticket;
  final _TicketDateFormatter dateFormat;
  final bool canManage;
  final VoidCallback onChangeStatus;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ticket.title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            ticket.ticketNumber,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            ticket.description,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TicketTag(
                label: _statusLabel(ticket.status),
                color: _statusColor(ticket.status),
              ),
              if (ticket.ticketType == 'ticket')
                _TicketTag(
                  label: _priorityLabel(ticket.priority),
                  color: _priorityColor(ticket.priority),
                ),
              if (ticket.ticketType != 'ticket' &&
                  ticket.targetDepartmentName != null)
                _TicketTag(
                  label: 'القسم: ${ticket.targetDepartmentName!}',
                  color: const Color(0xFF0F766E),
                ),
              if (ticket.assignedTo != null)
                _TicketTag(
                  label: 'المسؤول: ${ticket.assignedTo!.displayName}',
                  color: const Color(0xFF6366F1),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'آخر تحديث: ${ticket.lastUpdateAt != null ? dateFormat(ticket.lastUpdateAt!) : '-'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (canManage) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onChangeStatus,
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('تغيير الحالة'),
                ),
                OutlinedButton.icon(
                  onPressed: onAssign,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('إسناد التذكرة'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TicketUpdateCard extends StatelessWidget {
  const _TicketUpdateCard({required this.update, required this.dateFormat});

  final TicketUpdateItem update;
  final _TicketDateFormatter dateFormat;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final kindLabel = _kindLabel(update.kind);
    final visibilityLabel = _visibilityLabel(update.visibility);
    final displayMessage = _ticketUpdateDisplayMessage(update);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.38),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TicketTag(
                      label: kindLabel,
                      color: _kindColor(update.kind),
                    ),
                    _TicketTag(
                      label: visibilityLabel,
                      color: update.visibility == 'internal'
                          ? const Color(0xFF7C3AED)
                          : const Color(0xFF2563EB),
                    ),
                  ],
                ),
              ),
              Text(
                update.createdAt != null ? dateFormat(update.createdAt!) : '',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            update.createdBy.displayName,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            displayMessage,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
        ],
      ),
    );
  }
}

class _TicketTag extends StatelessWidget {
  const _TicketTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

String _statusLabel(String status) {
  return switch (status) {
    'open' => 'مفتوحة',
    'assigned' => 'مسندة',
    'in_progress' => 'قيد التنفيذ',
    'waiting_branch' => 'بانتظار الفرع',
    'resolved' => 'تم الحل',
    'closed' => 'مغلقة',
    _ => status,
  };
}

Color _statusColor(String status) {
  return switch (status) {
    'open' => const Color(0xFF2563EB),
    'assigned' => const Color(0xFF7C3AED),
    'in_progress' => const Color(0xFF0EA5E9),
    'waiting_branch' => const Color(0xFFF59E0B),
    'resolved' => const Color(0xFF16A34A),
    'closed' => const Color(0xFF6B7280),
    _ => const Color(0xFF334155),
  };
}

String _priorityLabel(String priority) {
  return switch (priority) {
    'low' => 'منخفضة',
    'normal' => 'عادية',
    'high' => 'عالية',
    'critical' => 'حرجة',
    _ => priority,
  };
}

Color _priorityColor(String priority) {
  return switch (priority) {
    'low' => const Color(0xFF64748B),
    'normal' => const Color(0xFF2563EB),
    'high' => const Color(0xFFF97316),
    'critical' => const Color(0xFFDC2626),
    _ => const Color(0xFF334155),
  };
}

String _kindLabel(String kind) {
  return switch (kind) {
    'created' => 'تم إنشاء التذكرة',
    'comment' => 'تعليق',
    'status' => 'تحديث حالة',
    'assignment' => 'تغيير الإسناد',
    'note' => 'ملاحظة داخلية',
    _ => kind,
  };
}

String _visibilityLabel(String visibility) {
  return visibility == 'internal' ? 'ملاحظة داخلية' : 'رسالة عامة';
}

Color _kindColor(String kind) {
  return switch (kind) {
    'created' => const Color(0xFF2563EB),
    'comment' => const Color(0xFF0EA5E9),
    'status' => const Color(0xFFF59E0B),
    'assignment' => const Color(0xFF6366F1),
    'note' => const Color(0xFF7C3AED),
    _ => const Color(0xFF475569),
  };
}

String _ticketUpdateDisplayMessage(TicketUpdateItem update) {
  if (update.kind == 'status') {
    final fromLabel = update.fromStatus == null
        ? null
        : _statusLabel(update.fromStatus!);
    final toLabel = update.toStatus == null
        ? null
        : _statusLabel(update.toStatus!);
    if (fromLabel != null && toLabel != null) {
      return 'تم تغيير حالة التذكرة من "$fromLabel" إلى "$toLabel".';
    }
    if (toLabel != null) {
      return 'تم تحديث حالة التذكرة إلى "$toLabel".';
    }
  }

  if (update.kind == 'assignment') {
    if (update.toAssigneeName != null &&
        update.toAssigneeName!.trim().isNotEmpty) {
      return 'تم إسناد التذكرة إلى ${update.toAssigneeName!}.';
    }
    return 'تم إلغاء إسناد التذكرة.';
  }

  if (update.kind == 'created') {
    return update.message.trim().isEmpty
        ? 'تم إنشاء التذكرة وفتحها للمراجعة.'
        : update.message;
  }

  if (update.kind == 'note') {
    return update.message.trim().isEmpty
        ? 'تمت إضافة ملاحظة داخلية.'
        : update.message;
  }

  if (update.kind == 'comment') {
    return update.message.trim().isEmpty
        ? 'تمت إضافة رد جديد على التذكرة.'
        : update.message;
  }

  return update.message.trim().isEmpty
      ? _kindLabel(update.kind)
      : update.message;
}

class _DepartmentHandlersDialog extends ConsumerStatefulWidget {
  const _DepartmentHandlersDialog({required this.handlerType});

  final String handlerType;

  bool get isSuggestion => handlerType == 'suggestion';
  bool get isTicket => handlerType == 'ticket';

  String get dialogTitle => switch (handlerType) {
    'suggestion' => 'مسؤولو الرد على المقترحات',
    'ticket' => 'مسؤولو الرد على تذاكر الدعم',
    _ => 'مسؤولو الرد على الشكاوى',
  };

  String get dialogSubtitle => switch (handlerType) {
    'suggestion' => 'اختر القسم ثم حدّد الموظفين المسؤولين عن استلام والرد على مقترحات هذا القسم.',
    'ticket' => 'اختر القسم ثم حدّد الموظفين المسؤولين عن استلام والرد على تذاكر هذا القسم.',
    _ => 'اختر القسم ثم حدّد الموظفين المسؤولين عن استلام والرد على الشكاوى الموجهة لهذا القسم.',
  };

  Color get typeColor => switch (handlerType) {
    'suggestion' => const Color(0xFF7C3AED),
    'ticket' => const Color(0xFF2563EB),
    _ => const Color(0xFFEA580C),
  };

  IconData get typeIcon => switch (handlerType) {
    'suggestion' => Icons.lightbulb_rounded,
    'ticket' => Icons.support_agent_rounded,
    _ => Icons.report_problem_rounded,
  };

  @override
  ConsumerState<_DepartmentHandlersDialog> createState() =>
      _DepartmentHandlersDialogState();
}

class _DepartmentHandlersDialogState
    extends ConsumerState<_DepartmentHandlersDialog> {
  List<dynamic> _departments = [];
  String? _selectedDeptId;
  List<TicketSupportUser> _supportUsers = [];
  Set<String> _selectedHandlerIds = {};
  bool _isLoadingDepts = true;
  bool _isLoadingHandlers = false;
  bool _isSaving = false;
  String _searchText = '';
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _searchText = '';
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final dio = ref.read(authenticatedApiClientProvider).dio;
      final res = await dio.get('/api/departments');
      final depts =
          (res.data['departments'] as List<dynamic>?) ??
          ((res.data['data'] as Map<String, dynamic>?)?['departments']
              as List<dynamic>?) ??
          const <dynamic>[];
      final supportData = await ref
          .read(ticketsControllerProvider.notifier)
          .fetchSupportUsers();

      if (!mounted) return;
      setState(() {
        _departments = depts;
        _supportUsers = supportData.users;
        _isLoadingDepts = false;
        if (depts.isNotEmpty) {
          final firstId =
              depts.first['id']?.toString() ?? depts.first['_id']?.toString();
          _selectedDeptId = firstId;
          if (firstId != null) {
            _loadHandlers(firstId);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingDepts = false;
        _errorText = e.toString();
      });
    }
  }

  Future<void> _loadHandlers(String deptId) async {
    setState(() {
      _isLoadingHandlers = true;
      _errorText = null;
    });
    try {
      final handlers = await ref
          .read(ticketsControllerProvider.notifier)
          .fetchDepartmentHandlers(deptId, handlerType: widget.handlerType);
      if (!mounted) return;
      setState(() {
        _selectedHandlerIds = handlers.map((h) => h.id).toSet();
        _isLoadingHandlers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingHandlers = false;
        _errorText = e.toString();
      });
    }
  }

  Future<void> _saveHandlers() async {
    if (_selectedDeptId == null) return;
    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    try {
      await ref
          .read(ticketsControllerProvider.notifier)
          .updateDepartmentHandlers(
            _selectedDeptId!,
            _selectedHandlerIds.toList(),
            handlerType: widget.handlerType,
          );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final availableWidth = MediaQuery.sizeOf(context).width - 32;
    final dialogWidth = math.max(280.0, math.min(520.0, availableWidth));
    final dialogHeight = MediaQuery.sizeOf(context).height * 0.85;

    final borderColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE2E8F0);
    final surfaceColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final fieldFillColor = isDark ? const Color(0xFF242428) : const Color(0xFFF8FAFC);

    final query = _searchText.trim().toLowerCase();
    final filteredUsers = _supportUsers.where((user) {
      if (query.isEmpty) return true;
      return user.displayName.toLowerCase().contains(query) ||
          user.username.toLowerCase().contains(query);
    }).toList();

    return Dialog(
      backgroundColor: surfaceColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
        ),
        child: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: widget.typeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(widget.typeIcon, color: widget.typeColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.dialogTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.dialogSubtitle,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, thickness: 1, color: borderColor),

              // Department Selector card
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: fieldFillColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.apartment_rounded, size: 16, color: widget.typeColor),
                              const SizedBox(width: 6),
                              const Text('القسم المستهدف:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: widget.typeColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'تعيين ${_selectedHandlerIds.length} مسؤول',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: widget.typeColor),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _selectedDeptId,
                            isExpanded: true,
                            dropdownColor: surfaceColor,
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: surfaceColor,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: widget.typeColor, width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            items: _departments.map((dept) {
                              final id = dept['id']?.toString() ?? dept['_id']?.toString() ?? '';
                              final name = dept['name']?.toString() ?? 'قسم غير معروف';
                              return DropdownMenuItem(value: id, child: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)));
                            }).toList(),
                            onChanged: _isSaving
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedDeptId = value;
                                      });
                                      _loadHandlers(value);
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Search bar
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'بحث في قائمة الموظفين...',
                        prefixIcon: Icon(Icons.search_rounded, size: 18, color: widget.typeColor),
                        filled: true,
                        fillColor: fieldFillColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: widget.typeColor, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onChanged: (val) => setState(() => _searchText = val),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, thickness: 1, color: borderColor),

              // Handlers list
              Expanded(
                child: _isLoadingDepts || _isLoadingHandlers
                    ? const Center(child: CircularProgressIndicator())
                    : filteredUsers.isEmpty
                    ? Center(
                        child: Text(
                          _supportUsers.isEmpty ? 'لا يوجد مستخدمون متاحون.' : 'لا توجد نتائج مطابقة لبحثك.',
                          style: TextStyle(
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            fontSize: 13,
                          ),
                        ),
                      )
                    : Scrollbar(
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          itemCount: filteredUsers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final user = filteredUsers[index];
                            final isAssigned = _selectedHandlerIds.contains(user.id);

                            return Container(
                              decoration: BoxDecoration(
                                color: isAssigned
                                    ? widget.typeColor.withValues(alpha: 0.05)
                                    : (isDark ? const Color(0xFF222226) : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isAssigned
                                      ? widget.typeColor.withValues(alpha: 0.35)
                                      : borderColor,
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: _isSaving
                                    ? null
                                    : () {
                                        setState(() {
                                          if (isAssigned) {
                                            _selectedHandlerIds.remove(user.id);
                                          } else {
                                            _selectedHandlerIds.add(user.id);
                                          }
                                        });
                                      },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: isAssigned ? widget.typeColor : Colors.transparent,
                                          borderRadius: BorderRadius.circular(5),
                                          border: Border.all(
                                            color: isAssigned ? widget.typeColor : (isDark ? const Color(0xFF64748B) : const Color(0xFFCBD5E1)),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: isAssigned
                                            ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                                            : null,
                                      ),
                                      const SizedBox(width: 10),
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: widget.typeColor.withValues(alpha: 0.15),
                                        child: Text(
                                          user.displayName.isNotEmpty
                                              ? user.displayName[0].toUpperCase()
                                              : '?',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: widget.typeColor,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              user.displayName,
                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                            ),
                                            Text(
                                              '@${user.username} • ${user.role}',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),

              if (_errorText != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text(
                    _errorText!,
                    style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],

              Divider(height: 1, thickness: 1, color: borderColor),

              // Actions
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                      child: const Text('إلغاء'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _saveHandlers,
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.typeColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      icon: _isSaving
                          ? const ButtonLoadingIndicator(radius: 8)
                          : const Icon(Icons.check_rounded, size: 16),
                      label: Text(
                        _isSaving ? 'جارٍ الحفظ...' : 'حفظ التعيينات',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
