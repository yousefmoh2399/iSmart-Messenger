import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

class ServerSettingsDialog extends ConsumerStatefulWidget {
  const ServerSettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const ServerSettingsDialog(),
    );
  }

  @override
  ConsumerState<ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends ConsumerState<ServerSettingsDialog> {
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _urlController.text = ref.read(apiBaseUrlControllerProvider).valueOrNull ?? '';
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _save() {
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      ref.read(apiBaseUrlControllerProvider.notifier).save(url);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إعدادات السيرفر'),
      content: TextField(
        controller: _urlController,
        decoration: const InputDecoration(
          labelText: 'رابط السيرفر',
          hintText: 'http://192.168.1.x:9090/',
        ),
        textDirection: TextDirection.ltr,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
