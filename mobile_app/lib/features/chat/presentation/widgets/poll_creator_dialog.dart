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
  late bool _isAnonymous;
  late bool _isMultipleChoice;

  @override
  void initState() {
    super.initState();
    _isAnonymous = !widget.isChecklistMode;
    _isMultipleChoice = widget.isChecklistMode;
  }

  void _addOption() {
    if (_optionControllers.length < 10) {
      setState(() {
        _optionControllers.add(TextEditingController());
      });
    }
  }

  void _removeOption(int index) {
    if (_optionControllers.length > 2) {
      setState(() {
        _optionControllers.removeAt(index);
      });
    }
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
      'options': options.asMap().entries.map((e) => {
        'id': 'opt_${e.key}_${DateTime.now().millisecondsSinceEpoch + e.key}',
        'text': e.value,
      }).toList(),
    };

    Navigator.of(context).pop(pollData);
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (var c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 600, maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.isChecklistMode ? 'إنشاء قائمة مهام' : 'إنشاء استطلاع رأي',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _questionController,
                decoration: const InputDecoration(
                  labelText: 'السؤال',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                maxLines: 2,
                minLines: 1,
              ),
              const SizedBox(height: 16),
              const Text('الخيارات', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _optionControllers.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _optionControllers[index],
                              decoration: InputDecoration(
                                hintText: 'خيار ${index + 1}',
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                          ),
                          if (_optionControllers.length > 2)
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                              onPressed: () => _removeOption(index),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (_optionControllers.length < 10)
                TextButton.icon(
                  onPressed: _addOption,
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة خيار'),
                ),
              if (!widget.isChecklistMode) const Divider(height: 24),
              if (!widget.isChecklistMode)
                SwitchListTile(
                  title: const Text('تصويت مجهول'),
                  value: _isAnonymous,
                  onChanged: (val) => setState(() => _isAnonymous = val),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              if (!widget.isChecklistMode)
                SwitchListTile(
                  title: const Text('إجابات متعددة'),
                  value: _isMultipleChoice,
                  onChanged: (val) => setState(() => _isMultipleChoice = val),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text('إرسال'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
