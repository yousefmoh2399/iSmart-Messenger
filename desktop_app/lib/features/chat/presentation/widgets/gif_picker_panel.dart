import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The GIF entry point is now an offline sticker library; it never calls web APIs.
class LocalSticker {
  const LocalSticker({
    required this.id,
    required this.name,
    required this.bytes,
    this.category = 'عام',
    this.favorite = false,
    this.lastUsedAt,
  });
  final String id;
  final String name;
  final Uint8List bytes;
  final String category;
  final bool favorite;
  final int? lastUsedAt;

  Map<String, String> toJson() => {
    'id': id,
    'name': name,
    'bytes': base64Encode(bytes),
    'category': category,
    'favorite': favorite.toString(),
    if (lastUsedAt != null) 'lastUsedAt': lastUsedAt.toString(),
  };
  static LocalSticker? fromJson(Object? value) {
    if (value is! Map) return null;
    try {
      final id = value['id']?.toString() ?? '';
      final name = value['name']?.toString() ?? '';
      final bytes = base64Decode(value['bytes']?.toString() ?? '');
      return id.isEmpty || name.isEmpty || bytes.isEmpty
          ? null
          : LocalSticker(
              id: id,
              name: name,
              bytes: bytes,
              category: value['category']?.toString() ?? 'عام',
              favorite: value['favorite']?.toString() == 'true',
              lastUsedAt: int.tryParse(value['lastUsedAt']?.toString() ?? ''),
            );
    } catch (_) {
      return null;
    }
  }
}

class LocalStickerPack {
  const LocalStickerPack({
    required this.id,
    required this.name,
    this.coverStickerId,
    this.stickerIds = const [],
  });
  final String id;
  final String name;
  final String? coverStickerId;
  final List<String> stickerIds;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'coverStickerId': coverStickerId,
    'stickerIds': stickerIds,
  };
  static LocalStickerPack? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString() ?? '';
    final name = raw['name']?.toString() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    return LocalStickerPack(
      id: id,
      name: name,
      coverStickerId: raw['coverStickerId']?.toString(),
      stickerIds: (raw['stickerIds'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
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
  static const _packsPrefsKey = 'offline_sticker_packs_v1';
  static const _maxStickerBytes = 5 * 1024 * 1024;
  List<LocalSticker> _stickers = const [];
  List<LocalStickerPack> _packs = const [];
  String? _selectedPackId;
  bool _loading = true;
  bool _importing = false;
  bool _dragging = false;
  String _filter = 'الكل';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
    final packsRaw = (await SharedPreferences.getInstance()).getString(
      _packsPrefsKey,
    );
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
          _packs = packsRaw == null
              ? const []
              : (jsonDecode(packsRaw) as List)
                    .map(LocalStickerPack.fromJson)
                    .whereType<LocalStickerPack>()
                    .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_stickers.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(
      _packsPrefsKey,
      jsonEncode(_packs.map((e) => e.toJson()).toList()),
    );
  }

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
    await _addFiles(result.files);
  }

  Future<void> _addFiles(List<PlatformFile> files) async {
    setState(() => _importing = true);
    final additions = <LocalSticker>[];
    for (final file in files) {
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
      setState(() {
        _stickers = [..._stickers, ...additions];
        if (_selectedPackId != null) {
          _packs = _packs
              .map(
                (pack) => pack.id != _selectedPackId
                    ? pack
                    : LocalStickerPack(
                        id: pack.id,
                        name: pack.name,
                        coverStickerId:
                            pack.coverStickerId ?? additions.first.id,
                        stickerIds: [
                          ...pack.stickerIds,
                          ...additions.map((s) => s.id),
                        ],
                      ),
              )
              .toList();
        }
      });
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

  Future<void> _update(LocalSticker old, LocalSticker replacement) async {
    setState(
      () => _stickers = _stickers
          .map((s) => s.id == old.id ? replacement : s)
          .toList(),
    );
    await _persist();
  }

  List<LocalSticker> get _visible {
    final query = _searchController.text.trim().toLowerCase();
    var items = _stickers.where(
      (s) => query.isEmpty || s.name.toLowerCase().contains(query),
    );
    if (_filter == 'المفضلة') items = items.where((s) => s.favorite);
    if (_filter == 'حديثة') items = items.where((s) => s.lastUsedAt != null);
    if (!const ['الكل', 'المفضلة', 'حديثة'].contains(_filter))
      items = items.where((s) => s.category == _filter);
    final result = items.toList();
    if (_filter == 'حديثة')
      result.sort((a, b) => (b.lastUsedAt ?? 0).compareTo(a.lastUsedAt ?? 0));
    return result;
  }

  Future<void> _createPack() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New sticker pack'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final pack = LocalStickerPack(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
    );
    setState(() {
      _packs = [..._packs, pack];
      _selectedPackId = pack.id;
    });
    await _persist();
  }

  Future<void> _exportSelectedPack() async {
    final pack = _packs.where((p) => p.id == _selectedPackId).firstOrNull;
    if (pack == null) return;
    final selected = _stickers
        .where((s) => pack.stickerIds.contains(s.id))
        .toList();
    final archive = Archive();
    archive.addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'format': 'ismart-stickers',
          'pack': pack.toJson(),
          'stickers': selected.map((s) => s.toJson()).toList(),
        }),
      ),
    );
    final encoded = ZipEncoder().encodeBytes(archive);
    await FilePicker.platform.saveFile(
      dialogTitle: 'Export sticker pack',
      fileName: '${pack.name}.ismartstickers.zip',
      bytes: Uint8List.fromList(encoded),
    );
  }

  Future<void> _importPack() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'ismartstickers'],
      withData: true,
    );
    final bytes = picked?.files.single.bytes;
    if (bytes == null) return;
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final manifest = archive.files
          .where((f) => f.name == 'manifest.json')
          .firstOrNull;
      if (manifest == null) throw const FormatException();
      final data =
          jsonDecode(utf8.decode(manifest.content as List<int>)) as Map;
      if (data['format'] != 'ismart-stickers') throw const FormatException();
      final pack = LocalStickerPack.fromJson(data['pack']);
      final stickers = (data['stickers'] as List? ?? const [])
          .map(LocalSticker.fromJson)
          .whereType<LocalSticker>()
          .toList();
      if (pack == null || stickers.isEmpty) throw const FormatException();
      final existingIds = _stickers.map((s) => s.id).toSet();
      final renamed = pack.id == '' || _packs.any((p) => p.id == pack.id)
          ? LocalStickerPack(
              id: '${pack.id}_${DateTime.now().microsecondsSinceEpoch}',
              name: pack.name,
              coverStickerId: pack.coverStickerId,
              stickerIds: pack.stickerIds,
            )
          : pack;
      setState(() {
        _stickers = [
          ..._stickers,
          ...stickers.where((s) => !existingIds.contains(s.id)),
        ];
        _packs = [..._packs, renamed];
        _selectedPackId = renamed.id;
      });
      await _persist();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر استيراد ملف باقة الملصقات.')),
        );
    }
  }

  Future<void> _toggleFavorite(LocalSticker sticker) => _update(
    sticker,
    LocalSticker(
      id: sticker.id,
      name: sticker.name,
      bytes: sticker.bytes,
      category: sticker.category,
      favorite: !sticker.favorite,
      lastUsedAt: sticker.lastUsedAt,
    ),
  );

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
              IconButton(
                onPressed: _createPack,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
              IconButton(
                onPressed: _selectedPackId == null ? null : _exportSelectedPack,
                icon: const Icon(Icons.ios_share_outlined),
              ),
              IconButton(
                onPressed: _importPack,
                icon: const Icon(Icons.download_for_offline_outlined),
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
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('All packs'),
                selected: _selectedPackId == null,
                onSelected: (_) => setState(() => _selectedPackId = null),
              ),
              ..._packs.map(
                (pack) => Padding(
                  padding: const EdgeInsetsDirectional.only(start: 6),
                  child: ChoiceChip(
                    label: Text(pack.name),
                    selected: _selectedPackId == pack.id,
                    onSelected: (_) =>
                        setState(() => _selectedPackId = pack.id),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'بحث في الملصقات',
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children:
                const [
                      'الكل',
                      'حديثة',
                      'المفضلة',
                      'مضحك',
                      'شغل',
                      'موافقة',
                      'تحذير',
                    ]
                    .map((title) => title)
                    .map(
                      (title) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ChoiceChip(
                          label: Text(title),
                          selected: _filter == title,
                          onSelected: (_) => setState(() => _filter = title),
                        ),
                      ),
                    )
                    .toList(),
          ),
        ),
        Expanded(
          child: DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (details) async {
              setState(() => _dragging = false);
              final files = <PlatformFile>[];
              for (final file in details.files) {
                final bytes = await file.readAsBytes();
                files.add(
                  PlatformFile(
                    name: file.name,
                    size: bytes.length,
                    bytes: bytes,
                  ),
                );
              }
              await _addFiles(files);
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _dragging
                    ? Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.45)
                    : null,
              ),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _visible.isEmpty
                  ? const Center(
                      child: Text(
                        'لا توجد ملصقات بعد. استورد صورًا أو GIF من جهازك.',
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemCount: _visible.length,
                      itemBuilder: (context, index) {
                        final sticker = _visible[index];
                        return InkWell(
                          onTap: () async {
                            await _update(
                              sticker,
                              LocalSticker(
                                id: sticker.id,
                                name: sticker.name,
                                bytes: sticker.bytes,
                                category: sticker.category,
                                favorite: sticker.favorite,
                                lastUsedAt:
                                    DateTime.now().millisecondsSinceEpoch,
                              ),
                            );
                            if (mounted) Navigator.of(context).pop(sticker);
                          },
                          onLongPress: () => _toggleFavorite(sticker),
                          borderRadius: BorderRadius.circular(12),
                          child: Tooltip(
                            message: sticker.name,
                            child: Image.memory(
                              sticker.bytes,
                              fit: BoxFit.contain,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
      ],
    ),
  );
}
