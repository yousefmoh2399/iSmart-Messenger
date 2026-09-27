import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only sticker library, kept under the historical GIF widget name.
class LocalSticker {
  const LocalSticker({
    required this.id,
    required this.name,
    required this.bytes,
  });
  final String id;
  final String name;
  final Uint8List bytes;
  Map<String, String> toJson() => {
    'id': id,
    'name': name,
    'bytes': base64Encode(bytes),
  };
  static LocalSticker? fromJson(Object? value) {
    if (value is! Map) return null;
    try {
      final id = value['id']?.toString() ?? '';
      final name = value['name']?.toString() ?? '';
      final bytes = base64Decode(value['bytes']?.toString() ?? '');
      return id.isEmpty || name.isEmpty || bytes.isEmpty
          ? null
          : LocalSticker(id: id, name: name, bytes: bytes);
    } catch (_) {
      return null;
    }
  }
}

Future<void> saveLocalSticker({
  required String name,
  required Uint8List bytes,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('offline_stickers_v1');
  final current = raw == null
      ? <LocalSticker>[]
      : (jsonDecode(raw) as List)
            .map(LocalSticker.fromJson)
            .whereType<LocalSticker>()
            .toList();
  current.add(
    LocalSticker(
      id: '${DateTime.now().microsecondsSinceEpoch}_${current.length}',
      name: name,
      bytes: bytes,
    ),
  );
  await prefs.setString(
    'offline_stickers_v1',
    jsonEncode(current.map((e) => e.toJson()).toList()),
  );
}

class GifPickerPanel extends StatefulWidget {
  const GifPickerPanel({super.key});
  @override
  State<GifPickerPanel> createState() => _GifPickerPanelState();
}

class _GifPickerPanelState extends State<GifPickerPanel> {
  static const _prefsKey = 'offline_stickers_v1';
  static const _maxStickerBytes = 5 * 1024 * 1024;
  List<LocalSticker> _stickers = const [];
  bool _loading = true;
  bool _importing = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
    try {
      final stickers = raw == null
          ? const <LocalSticker>[]
          : (jsonDecode(raw) as List)
                .map(LocalSticker.fromJson)
                .whereType<LocalSticker>()
                .toList();
      if (mounted) {
        setState(() {
          _stickers = stickers;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _persist() async =>
      (await SharedPreferences.getInstance()).setString(
        _prefsKey,
        jsonEncode(_stickers.map((e) => e.toJson()).toList()),
      );
  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null) {
      return;
    }
    setState(() => _importing = true);
    final additions = <LocalSticker>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty || bytes.length > _maxStickerBytes) {
        continue;
      }
      additions.add(
        LocalSticker(
          id: '${DateTime.now().microsecondsSinceEpoch}_${additions.length}',
          name: file.name,
          bytes: bytes,
        ),
      );
    }
    if (additions.isNotEmpty) {
      setState(() => _stickers = [..._stickers, ...additions]);
      await _persist();
    }
    if (mounted) {
      setState(() => _importing = false);
    }
  }

  Future<void> _remove(LocalSticker sticker) async {
    setState(
      () => _stickers = _stickers.where((e) => e.id != sticker.id).toList(),
    );
    await _persist();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'الملصقات',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: _importing ? null : _import,
                icon: _importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('استيراد'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'تعمل محليًا بدون إنترنت. اضغط مطولًا لحذف ملصق.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _stickers.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد ملصقات بعد. استورد صورًا أو GIF من جهازك.',
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _stickers.length,
                  itemBuilder: (context, index) {
                    final sticker = _stickers[index];
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(sticker),
                      onLongPress: () => _remove(sticker),
                      borderRadius: BorderRadius.circular(12),
                      child: Tooltip(
                        message: sticker.name,
                        child: Image.memory(sticker.bytes, fit: BoxFit.contain),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
