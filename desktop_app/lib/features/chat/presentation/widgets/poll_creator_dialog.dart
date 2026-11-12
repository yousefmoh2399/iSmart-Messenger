import 'package:flutter/material.dart';

class PollCreatorDialog extends StatefulWidget {
  const PollCreatorDialog({super.key, this.isChecklistMode = false});

  final bool isChecklistMode;

  @override
  State<PollCreatorDialog> createState() => _PollCreatorDialogState();
}

class _PollCreatorDialogState extends State<PollCreatorDialog> {
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<FocusNode> _focusNodes = [
    FocusNode(),
    FocusNode(),
  ];

  late bool _isAnonymous;
  late bool _isMultipleChoice;

  @override
  void initState() {
    super.initState();
    _isAnonymous = !widget.isChecklistMode;
    _isMultipleChoice = widget.isChecklistMode;
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _addOption([String initialText = '']) {
    if (_optionControllers.length < 10) {
      setState(() {
        _optionControllers.add(TextEditingController(text: initialText));
        _focusNodes.add(FocusNode());
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_focusNodes.isNotEmpty && initialText.isEmpty) {
          _focusNodes.last.requestFocus();
        }
      });
    }
  }

  void _removeOption(int index) {
    if (_optionControllers.length > 2) {
      setState(() {
        _optionControllers[index].dispose();
        _focusNodes[index].dispose();
        _optionControllers.removeAt(index);
        _focusNodes.removeAt(index);
      });
    }
  }

  void _applyPreset(List<String> items) {
    setState(() {
      for (final c in _optionControllers) {
        c.dispose();
      }
      for (final f in _focusNodes) {
        f.dispose();
      }
      _optionControllers.clear();
      _focusNodes.clear();

      for (final item in items) {
        _optionControllers.add(TextEditingController(text: item));
        _focusNodes.add(FocusNode());
      }
    });
  }

  bool get _isValid {
    final question = _questionController.text.trim();
    if (question.isEmpty) return false;
    final validOptions = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    return validOptions.length >= 2;
  }

  void _submit() {
    final question = _questionController.text.trim();
    if (question.isEmpty) return;

    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (options.length < 2) return;

    final pollData = {
      'question': question,
      'isAnonymous': _isAnonymous,
      'isMultipleChoice': _isMultipleChoice,
      'isChecklist': widget.isChecklistMode,
      'options': options.asMap().entries.map((e) => {
        'id': 'opt_${e.key}_${DateTime.now().millisecondsSinceEpoch + e.key}',
        'text': e.value,
      }).toList(),
    };

    Navigator.of(context).pop(pollData);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isChecklist = widget.isChecklistMode;
    final accentColor = isChecklist
        ? const Color(0xFF10B981) // Emerald Green
        : const Color(0xFF6366F1); // Indigo / Purple

    final surfaceCardColor = isDark
        ? const Color(0xFF1E1E22)
        : Colors.white;
    final insetGroupColor = isDark
        ? const Color(0xFF28282D)
        : const Color(0xFFF4F5F7);
    final textHeadingColor = isDark
        ? const Color(0xFFF1F5F9)
        : const Color(0xFF0F172A);
    final textMutedColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Dialog(
      backgroundColor: surfaceCardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 520,
          maxHeight: 700,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        isChecklist
                            ? Icons.task_alt_rounded
                            : Icons.poll_rounded,
                        color: accentColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isChecklist ? 'إنشاء قائمة مهام جديدة' : 'إنشاء استطلاع رأي جديد',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: textHeadingColor,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isChecklist
                                ? 'أنشئ قائمة مهام مشتركة يمكن للجميع تحديد إنجازها'
                                : 'اطرح سؤالاً ودع أعضاء المحادثة يصوتون على الخيارات',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: textMutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      style: IconButton.styleFrom(
                        foregroundColor: textMutedColor,
                        hoverColor: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Scrollable Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Question / Task title label
                      Row(
                        children: [
                          Text(
                            isChecklist ? 'عنوان قائمة المهام' : 'سؤال الاستطلاع',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: textHeadingColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            '*',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Question TextField
                      Container(
                        decoration: BoxDecoration(
                          color: insetGroupColor,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.07)
                                : Colors.black.withValues(alpha: 0.06),
                          ),
                        ),
                        child: TextField(
                          controller: _questionController,
                          onChanged: (_) => setState(() {}),
                          maxLines: 2,
                          minLines: 1,
                          style: TextStyle(
                            fontSize: 14,
                            color: textHeadingColor,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            hintText: isChecklist
                                ? 'مثال: مهام افتتاح الفرع اليومية، متطلبات التسليم...'
                                : 'مثال: ما هو الموعد الأنسب للاجتماع القادم؟...',
                            hintStyle: TextStyle(
                              fontSize: 13.5,
                              color: textMutedColor.withValues(alpha: 0.8),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Options Header + Count Badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                isChecklist ? 'بنود المهام' : 'خيارات الاستطلاع',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: textHeadingColor,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                '*',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_optionControllers.length}/10',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: accentColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Preset Templates Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: isChecklist
                              ? [
                                  _buildPresetChip(
                                    label: 'مهام الافتتاح',
                                    icon: Icons.storefront_rounded,
                                    items: [
                                      'فتح الأبواب وتشغيل أجهزة العمل',
                                      'مراجعة الخزينة ورصيد البداية',
                                      'فحص النظافة وجاهزية المنتجات',
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  _buildPresetChip(
                                    label: 'مهام الإغلاق والتسليم',
                                    icon: Icons.lock_clock_rounded,
                                    items: [
                                      'جرد المبيعات اليومية والخزينة',
                                      'إغلاق الأجهزة ونقاط البيع',
                                      'فحص الأمان وقفل منافذ الفرع',
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  _buildPresetChip(
                                    label: 'مهام استلام بضاعة',
                                    icon: Icons.inventory_2_rounded,
                                    items: [
                                      'مطابقة إذن الاستلام مع الشحنة',
                                      'فحص حالة الطرود والتوالف',
                                      'إدخال الكميات على المنظومة',
                                    ],
                                  ),
                                ]
                              : [
                                  _buildPresetChip(
                                    label: 'نعم / لا',
                                    icon: Icons.thumbs_up_down_rounded,
                                    items: ['نعم', 'لا'],
                                  ),
                                  const SizedBox(width: 8),
                                  _buildPresetChip(
                                    label: 'موافق / معارض / محايد',
                                    icon: Icons.how_to_vote_rounded,
                                    items: ['موافق', 'غير موافق', 'محايد'],
                                  ),
                                  const SizedBox(width: 8),
                                  _buildPresetChip(
                                    label: 'فترات العمل',
                                    icon: Icons.access_time_rounded,
                                    items: ['الفترة الصباحية', 'الفترة المسائية'],
                                  ),
                                ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Option rows
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _optionControllers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final canRemove = _optionControllers.length > 2;

                          return Container(
                            decoration: BoxDecoration(
                              color: insetGroupColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.black.withValues(alpha: 0.05),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: isChecklist
                                      ? Icon(
                                          Icons.check_box_outline_blank_rounded,
                                          size: 15,
                                          color: accentColor,
                                        )
                                      : Text(
                                          '${index + 1}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: accentColor,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _optionControllers[index],
                                    focusNode: _focusNodes[index],
                                    onChanged: (_) => setState(() {}),
                                    textInputAction: index == _optionControllers.length - 1
                                        ? TextInputAction.done
                                        : TextInputAction.next,
                                    onSubmitted: (_) {
                                      if (index == _optionControllers.length - 1 &&
                                          _optionControllers.length < 10) {
                                        _addOption();
                                      }
                                    },
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: textHeadingColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: isChecklist
                                          ? 'المهمة ${index + 1}...'
                                          : 'الخيار ${index + 1}...',
                                      hintStyle: TextStyle(
                                        fontSize: 13,
                                        color: textMutedColor.withValues(alpha: 0.75),
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                    ),
                                  ),
                                ),
                                if (canRemove)
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                                    style: IconButton.styleFrom(
                                      foregroundColor: Colors.redAccent.withValues(alpha: 0.8),
                                      hoverColor: Colors.redAccent.withValues(alpha: 0.1),
                                      padding: const EdgeInsets.all(6),
                                      minimumSize: Size.zero,
                                    ),
                                    tooltip: 'حذف الخيار',
                                    onPressed: () => _removeOption(index),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),

                      if (_optionControllers.length < 10) ...[
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () => _addOption(),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: accentColor.withValues(alpha: 0.22),
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_rounded, size: 18, color: accentColor),
                                const SizedBox(width: 6),
                                Text(
                                  isChecklist ? 'إضافة مهمة جديدة' : 'إضافة خيار آخر',
                                  style: TextStyle(
                                    color: accentColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 18),

                      // Settings / Info Section
                      if (!isChecklist) ...[
                        Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: insetGroupColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.black.withValues(alpha: 0.05),
                            ),
                          ),
                          child: Column(
                            children: [
                              SwitchListTile.adaptive(
                                secondary: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.visibility_off_outlined,
                                    size: 18,
                                    color: Colors.deepPurpleAccent,
                                  ),
                                ),
                                title: Text(
                                  'تصويت مجهول',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: textHeadingColor,
                                  ),
                                ),
                                subtitle: Text(
                                  'إخفاء أسماء وهوية المصوتين عن بقية الأعضاء',
                                  style: TextStyle(fontSize: 11.5, color: textMutedColor),
                                ),
                                value: _isAnonymous,
                                activeColor: accentColor,
                                onChanged: (val) => setState(() => _isAnonymous = val),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                              ),
                              Divider(
                                height: 0.5,
                                thickness: 0.5,
                                indent: 56,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.06),
                              ),
                              SwitchListTile.adaptive(
                                secondary: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.checklist_rtl_rounded,
                                    size: 18,
                                    color: Colors.blueAccent,
                                  ),
                                ),
                                title: Text(
                                  'السماح بعدة إجابات',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: textHeadingColor,
                                  ),
                                ),
                                subtitle: Text(
                                  'يستطيع العضو اختيار أكثر من خيار واحد',
                                  style: TextStyle(fontSize: 11.5, color: textMutedColor),
                                ),
                                value: _isMultipleChoice,
                                activeColor: accentColor,
                                onChanged: (val) => setState(() => _isMultipleChoice = val),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.group_work_rounded,
                                size: 20,
                                color: accentColor,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'قائمة مهام تفاعلية لفريق العمل',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: accentColor,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'يستطيع جميع أعضاء المحادثة تحديد وإنجاز المهام مباشرة، وسيتم عرض نسبة الإنجاز وهوية من أنجز كل مهمة.',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: textHeadingColor.withValues(alpha: 0.8),
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
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

              // Footer Actions
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: textMutedColor,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'إلغاء',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _isValid ? _submit : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: accentColor.withValues(alpha: 0.35),
                        disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      icon: Icon(
                        isChecklist ? Icons.add_task_rounded : Icons.send_rounded,
                        size: 18,
                      ),
                      label: Text(
                        isChecklist ? 'إنشاء قائمة المهام' : 'نشر الاستطلاع',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
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

  Widget _buildPresetChip({
    required String label,
    required IconData icon,
    required List<String> items,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isChecklist = widget.isChecklistMode;
    final accentColor = isChecklist
        ? const Color(0xFF10B981)
        : const Color(0xFF6366F1);

    return InkWell(
      onTap: () => _applyPreset(items),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: accentColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
