import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/providers/providers.dart';
import '../../data/chat_repository.dart';
import '../../data/chat_socket_service.dart';

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String resolveStickerExtension(Uint8List bytes, [String? currentName]) {
  if (bytes.length >= 3 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46) {
    return '.gif';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return '.webp';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return '.png';
  }
  if (currentName != null && currentName.contains('.')) {
    final ext = p.extension(currentName).toLowerCase();
    if (ext.isNotEmpty) return ext;
  }
  return '.png';
}

/// The local sticker model representing an offline sticker.
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'bytes': base64Encode(bytes),
    'category': category,
    'favorite': favorite,
    if (lastUsedAt != null) 'lastUsedAt': lastUsedAt,
  };

  static LocalSticker? fromJson(Object? value) {
    if (value is! Map) return null;
    try {
      final id = value['id']?.toString() ?? '';
      final name = value['name']?.toString() ?? '';
      final rawBytes = value['bytes'];
      Uint8List bytes;
      if (rawBytes is Uint8List) {
        bytes = rawBytes;
      } else if (rawBytes is List) {
        bytes = Uint8List.fromList(rawBytes.cast<int>());
      } else {
        bytes = base64Decode(rawBytes?.toString() ?? '');
      }
      return id.isEmpty || name.isEmpty || bytes.isEmpty
          ? null
          : LocalSticker(
              id: id,
              name: name,
              bytes: bytes,
              category: value['category']?.toString() ?? 'عام',
              favorite: value['favorite'] == true ||
                  value['favorite']?.toString() == 'true',
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
  String category = 'عام',
  bool favorite = false,
  ChatRepository? repository,
}) async {
  final ext = resolveStickerExtension(bytes, name);
  final base = p.basenameWithoutExtension(name);
  final resolvedName = '$base$ext';

  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('offline_stickers_v1');
  final current = raw == null
      ? <LocalSticker>[]
      : (jsonDecode(raw) as List)
            .map(LocalSticker.fromJson)
            .whereType<LocalSticker>()
            .toList();

  final alreadyExists = current.any((s) {
    if (s.name == resolvedName && s.bytes.length == bytes.length) return true;
    if (s.bytes.length == bytes.length && _bytesEqual(s.bytes, bytes)) return true;
    return false;
  });

  LocalSticker? newSticker;
  if (!alreadyExists) {
    newSticker = LocalSticker(
      id: '${DateTime.now().microsecondsSinceEpoch}_${current.length}',
      name: resolvedName,
      bytes: bytes,
      category: category,
      favorite: favorite,
      lastUsedAt: DateTime.now().millisecondsSinceEpoch,
    );
    current.add(newSticker);
    await prefs.setString(
      'offline_stickers_v1',
      jsonEncode(current.map((e) => e.toJson()).toList()),
    );
  }

  if (repository != null) {
    try {
      final stickerToSave = newSticker ??
          current.firstWhere(
            (s) => s.bytes.length == bytes.length && _bytesEqual(s.bytes, bytes),
          );
      await repository.saveUserSticker(stickerToSave.toJson());
    } catch (_) {}
  }
}

Future<bool> isLocalStickerSaved({
  required Uint8List bytes,
  String? name,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('offline_stickers_v1');
  if (raw == null) return false;
  try {
    final stickers = (jsonDecode(raw) as List)
        .map(LocalSticker.fromJson)
        .whereType<LocalSticker>();
    return stickers.any((s) {
      if (name != null && s.name == name && s.bytes.length == bytes.length) {
        return true;
      }
      if (s.bytes.length == bytes.length && _bytesEqual(s.bytes, bytes)) {
        return true;
      }
      return false;
    });
  } catch (_) {
    return false;
  }
}

class GifPickerPanel extends ConsumerStatefulWidget {
  const GifPickerPanel({super.key});

  @override
  ConsumerState<GifPickerPanel> createState() => _GifPickerPanelState();
}

class _GifPickerPanelState extends ConsumerState<GifPickerPanel> {
  static const _prefsKey = 'offline_stickers_v1';
  static const _packsPrefsKey = 'offline_sticker_packs_v1';
  static const _maxStickerBytes = 10 * 1024 * 1024; // 10MB limit

  List<LocalSticker> _stickers = const [];
  List<LocalStickerPack> _packs = const [];
  String? _selectedPackId;
  bool _loading = true;
  bool _importing = false;
  bool _dragging = false;
  String _filter = 'الكل';
  final _searchController = TextEditingController();
  StreamSubscription<ChatSocketEvent>? _socketSub;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenToSocket();
      _syncRemote();
    });
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _searchController.dispose();
    super.dispose();
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

    try {
      ref.read(chatRepositoryProvider).syncUserStickers(
        stickers: _stickers.map((e) => e.toJson()).toList(),
        packs: _packs.map((e) => e.toJson()).toList(),
      );
    } catch (_) {}
  }

  Future<void> _syncRemote() async {
    try {
      final repo = ref.read(chatRepositoryProvider);
      final remoteData = await repo.fetchUserStickers();
      final remoteStickersRaw = remoteData['stickers'] as List? ?? const [];
      final remotePacksRaw = remoteData['packs'] as List? ?? const [];

      final remoteStickers = remoteStickersRaw
          .map(LocalSticker.fromJson)
          .whereType<LocalSticker>()
          .toList();
      final remotePacks = remotePacksRaw
          .map(LocalStickerPack.fromJson)
          .whereType<LocalStickerPack>()
          .toList();

      if (remoteStickers.isEmpty && _stickers.isNotEmpty) {
        await repo.syncUserStickers(
          stickers: _stickers.map((s) => s.toJson()).toList(),
          packs: _packs.map((p) => p.toJson()).toList(),
        );
        return;
      }

      final merged = List<LocalSticker>.from(_stickers);
      bool changed = false;
      for (final r in remoteStickers) {
        final exists = merged.any((l) =>
            l.id == r.id ||
            (l.bytes.length == r.bytes.length && _bytesEqual(l.bytes, r.bytes)));
        if (!exists) {
          merged.add(r);
          changed = true;
        }
      }

      final mergedPacks = List<LocalStickerPack>.from(_packs);
      for (final rp in remotePacks) {
        if (!mergedPacks.any((p) => p.id == rp.id)) {
          mergedPacks.add(rp);
          changed = true;
        }
      }

      if (changed && mounted) {
        setState(() {
          _stickers = merged;
          _packs = mergedPacks;
        });
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
    } catch (_) {
      // Offline fallback
    }
  }

  void _listenToSocket() {
    try {
      final socketService = ref.read(chatSocketServiceProvider);
      _socketSub = socketService.events
          .where((e) => e.type == 'stickers_updated')
          .listen((e) {
        _handleRemoteStickersUpdated(e.payload);
      });
    } catch (_) {}
  }

  void _handleRemoteStickersUpdated(Map<String, dynamic> payload) {
    try {
      final remoteStickersRaw = payload['stickers'] as List? ?? const [];
      final remotePacksRaw = payload['packs'] as List? ?? const [];
      final remoteStickers = remoteStickersRaw
          .map(LocalSticker.fromJson)
          .whereType<LocalSticker>()
          .toList();
      final remotePacks = remotePacksRaw
          .map(LocalStickerPack.fromJson)
          .whereType<LocalStickerPack>()
          .toList();

      if (remoteStickers.isNotEmpty && mounted) {
        setState(() {
          _stickers = remoteStickers;
          if (remotePacks.isNotEmpty) {
            _packs = remotePacks;
          }
        });
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString(
            _prefsKey,
            jsonEncode(_stickers.map((e) => e.toJson()).toList()),
          );
          prefs.setString(
            _packsPrefsKey,
            jsonEncode(_packs.map((e) => e.toJson()).toList()),
          );
        });
      }
    } catch (_) {}
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

      // Check if duplicate already exists
      final alreadyExists = _stickers.any((s) {
        return (s.name == file.name && s.bytes.length == bytes.length) ||
            (s.bytes.length == bytes.length && _bytesEqual(s.bytes, bytes));
      });
      if (alreadyExists) continue;

      additions.add(
        LocalSticker(
          id: '${DateTime.now().microsecondsSinceEpoch}_${additions.length}',
          name: file.name,
          bytes: bytes,
          lastUsedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    if (additions.isNotEmpty) {
      setState(() {
        _stickers = [...additions, ..._stickers];
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
      if (additions.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم استيراد ${additions.length} ملصق بنجاح! 🎉'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _remove(LocalSticker sticker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
          title: const Text('حذف الملصق'),
          content: Text('هل تريد حذف الملصق «${sticker.name}» من مكتبتك؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      setState(() {
        _stickers = _stickers.where((e) => e.id != sticker.id).toList();
        _packs = _packs.map((p) {
          return LocalStickerPack(
            id: p.id,
            name: p.name,
            coverStickerId: p.coverStickerId == sticker.id ? null : p.coverStickerId,
            stickerIds: p.stickerIds.where((id) => id != sticker.id).toList(),
          );
        }).toList();
      });
      await _persist();
    }
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

    if (_selectedPackId != null) {
      final pack = _packs.where((p) => p.id == _selectedPackId).firstOrNull;
      if (pack != null) {
        items = items.where((s) => pack.stickerIds.contains(s.id));
      }
    }

    if (_filter == 'المفضلة') {
      items = items.where((s) => s.favorite);
    } else if (_filter == 'حديثة') {
      items = items.where((s) => s.lastUsedAt != null);
    }

    final result = items.toList();
    if (_filter == 'حديثة') {
      result.sort((a, b) => (b.lastUsedAt ?? 0).compareTo(a.lastUsedAt ?? 0));
    }
    return result;
  }

  Future<void> _createPack() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
          title: const Text('إنشاء حزمة ملصقات جديدة'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'اسم الحزمة (مثلاً: رياضة، مضحك)...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('إنشاء'),
            ),
          ],
        );
      },
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

  Future<void> _deletePack(LocalStickerPack pack) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
          title: const Text('حذف الحزمة'),
          content: Text('هل تريد بالتأكيد حذف حزمة «${pack.name}»؟ لن يتم حذف الملصقات التابعة لها من المكتبة.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف الحزمة'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      setState(() {
        _packs = _packs.where((p) => p.id != pack.id).toList();
        if (_selectedPackId == pack.id) {
          _selectedPackId = null;
        }
      });
      await _persist();
    }
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
      dialogTitle: 'تصدير باقة الملصقات',
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم استيراد باقة «${renamed.name}» بنجاح! 🎉')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر استيراد ملف باقة الملصقات.')),
        );
      }
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryAccent = const Color(0xFF007AFF);
    final panelBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final surfaceVariant = isDark ? const Color(0xFF28282C) : const Color(0xFFF1F5F9);
    final borderColor = isDark ? const Color(0xFF2D2D32) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final visibleStickers = _visible;

    return Container(
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: primaryAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.auto_awesome_motion_rounded,
                    color: primaryAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'مكتبة الملصقات',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: surfaceVariant,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${_stickers.length}',
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ملصقاتك الخاصة والمحفوظة من المحادثات وتعمل أوفلاين',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // Top Actions
                IconButton(
                  tooltip: 'إنشاء باقة جديدة',
                  splashRadius: 18,
                  onPressed: _createPack,
                  icon: Icon(
                    Icons.create_new_folder_outlined,
                    color: textSecondary,
                    size: 20,
                  ),
                ),
                if (_selectedPackId != null)
                  IconButton(
                    tooltip: 'تصدير هذه الباقة (.zip)',
                    splashRadius: 18,
                    onPressed: _exportSelectedPack,
                    icon: Icon(
                      Icons.ios_share_outlined,
                      color: textSecondary,
                      size: 20,
                    ),
                  ),
                IconButton(
                  tooltip: 'استيراد باقة (.zip)',
                  splashRadius: 18,
                  onPressed: _importPack,
                  icon: Icon(
                    Icons.download_for_offline_outlined,
                    color: textSecondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: _importing ? null : _import,
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: _importing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.add_photo_alternate_rounded, size: 16),
                  label: const Text(
                    'استيراد',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 1),

          // ── Search & Filter Bar ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor, width: 0.8),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 10),
                        Icon(Icons.search_rounded, size: 18, color: textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (_) => setState(() {}),
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: 'ابحث في أسماء الملصقات...',
                              hintStyle: TextStyle(
                                color: textSecondary.withValues(alpha: 0.7),
                                fontSize: 12.5,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            splashRadius: 16,
                            iconSize: 16,
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: Icon(Icons.cancel_rounded, color: textSecondary),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Pack Chips & Quick Categories ─────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(
              children: [
                _buildFilterTab(
                  label: 'الكل',
                  count: _stickers.length,
                  isSelected: _selectedPackId == null && _filter == 'الكل',
                  onTap: () => setState(() {
                    _selectedPackId = null;
                    _filter = 'الكل';
                  }),
                  isDark: isDark,
                  primaryAccent: primaryAccent,
                ),
                const SizedBox(width: 6),
                _buildFilterTab(
                  label: '⭐ المفضلة',
                  count: _stickers.where((s) => s.favorite).length,
                  isSelected: _selectedPackId == null && _filter == 'المفضلة',
                  onTap: () => setState(() {
                    _selectedPackId = null;
                    _filter = 'المفضلة';
                  }),
                  isDark: isDark,
                  primaryAccent: primaryAccent,
                ),
                const SizedBox(width: 6),
                _buildFilterTab(
                  label: '🕒 حديثة',
                  count: _stickers.where((s) => s.lastUsedAt != null).length,
                  isSelected: _selectedPackId == null && _filter == 'حديثة',
                  onTap: () => setState(() {
                    _selectedPackId = null;
                    _filter = 'حديثة';
                  }),
                  isDark: isDark,
                  primaryAccent: primaryAccent,
                ),
                ..._packs.map((pack) {
                  final isSelected = _selectedPackId == pack.id;
                  final count = _stickers.where((s) => pack.stickerIds.contains(s.id)).length;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () => setState(() {
                        _selectedPackId = pack.id;
                        _filter = 'الكل';
                      }),
                      onLongPress: () => _deletePack(pack),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primaryAccent
                              : (isDark ? const Color(0xFF28282C) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? primaryAccent : borderColor,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.folder_outlined,
                              size: 14,
                              color: isSelected ? Colors.white : textSecondary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${pack.name} ($count)',
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                                fontSize: 11.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // ── Stickers Grid with Drag & Drop ───────────────────────────
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
              child: Container(
                color: _dragging
                    ? primaryAccent.withValues(alpha: 0.08)
                    : Colors.transparent,
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : visibleStickers.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: surfaceVariant,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _searchController.text.isNotEmpty
                                      ? Icons.search_off_rounded
                                      : Icons.auto_awesome_motion_rounded,
                                  size: 32,
                                  color: textSecondary.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _searchController.text.isNotEmpty
                                    ? 'لا توجد ملصقات مطابقة للبحث'
                                    : 'لا توجد ملصقات بعد في هذه القائمة',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _searchController.text.isNotEmpty
                                    ? 'جرب البحث بكلمة أخرى أو تصفح الباقات الأخرى.'
                                    : 'يمكنك استيراد صور أو GIFs أو حفظ الملصقات التي تصلك في الشات مباشرة بنقرة واحدة.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              if (_searchController.text.isEmpty) ...[
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: _import,
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                                  label: const Text('استيراد ملصقات من جهازك'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: visibleStickers.length,
                        itemBuilder: (context, index) {
                          final sticker = visibleStickers[index];
                          return _StickerCard(
                            sticker: sticker,
                            isDark: isDark,
                            primaryAccent: primaryAccent,
                            onTap: () async {
                              final navigator = Navigator.of(context);
                              await _update(
                                sticker,
                                LocalSticker(
                                  id: sticker.id,
                                  name: sticker.name,
                                  bytes: sticker.bytes,
                                  category: sticker.category,
                                  favorite: sticker.favorite,
                                  lastUsedAt: DateTime.now().millisecondsSinceEpoch,
                                ),
                              );
                              if (mounted) {
                                navigator.pop(sticker);
                              }
                            },
                            onToggleFavorite: () => _toggleFavorite(sticker),
                            onDelete: () => _remove(sticker),
                          );
                        },
                      ),
              ),
            ),
          ),

          // ── Footer Helper ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: surfaceVariant.withValues(alpha: 0.5),
              border: Border(top: BorderSide(color: borderColor, width: 0.8)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'انقر على الملصق لإرساله فورًا. يمكنك سحب الصور وإفلاتها مباشرة لإضافتها.',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab({
    required String label,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
    required Color primaryAccent,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryAccent
              : (isDark ? const Color(0xFF28282C) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? primaryAccent
                : (isDark ? const Color(0xFF383840) : const Color(0xFFE2E8F0)),
            width: 0.8,
          ),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _StickerCard extends StatefulWidget {
  const _StickerCard({
    required this.sticker,
    required this.isDark,
    required this.primaryAccent,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onDelete,
  });

  final LocalSticker sticker;
  final bool isDark;
  final Color primaryAccent;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDelete;

  @override
  State<_StickerCard> createState() => _StickerCardState();
}

class _StickerCardState extends State<_StickerCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cardBg = widget.isDark ? const Color(0xFF242428) : const Color(0xFFF8FAFC);
    final borderColor = widget.isDark ? const Color(0xFF323238) : const Color(0xFFE2E8F0);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isHovered
                    ? widget.primaryAccent.withValues(alpha: 0.8)
                    : borderColor,
                width: _isHovered ? 1.4 : 0.8,
              ),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: widget.primaryAccent.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                // Sticker Image
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Image.memory(
                      widget.sticker.bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),

                // Favorite Star in Top Right
                Positioned(
                  top: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 140),
                    opacity: (widget.sticker.favorite || _isHovered) ? 1.0 : 0.0,
                    child: InkWell(
                      onTap: widget.onToggleFavorite,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(3.5),
                        decoration: BoxDecoration(
                          color: (widget.isDark ? Colors.black54 : Colors.white)
                              .withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.sticker.favorite
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 15,
                          color: widget.sticker.favorite
                              ? const Color(0xFFF59E0B)
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),

                // Delete Button in Top Left (shown on hover)
                Positioned(
                  top: 0,
                  left: 0,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 140),
                    opacity: _isHovered ? 1.0 : 0.0,
                    child: InkWell(
                      onTap: widget.onDelete,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(3.5),
                        decoration: BoxDecoration(
                          color: (widget.isDark ? Colors.black54 : Colors.white)
                              .withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          size: 14,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
