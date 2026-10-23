import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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
  String category = 'عام',
  bool favorite = false,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('offline_stickers_v1');
  final current = raw == null
      ? <LocalSticker>[]
      : (jsonDecode(raw) as List)
            .map(LocalSticker.fromJson)
            .whereType<LocalSticker>()
            .toList();

  final alreadyExists = current.any((s) {
    if (s.name == name && s.bytes.length == bytes.length) return true;
    if (s.bytes.length == bytes.length && _bytesEqual(s.bytes, bytes)) return true;
    return false;
  });

  if (!alreadyExists) {
    current.add(
      LocalSticker(
        id: '${DateTime.now().microsecondsSinceEpoch}_${current.length}',
        name: name,
        bytes: bytes,
        category: category,
        favorite: favorite,
        lastUsedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await prefs.setString(
      'offline_stickers_v1',
      jsonEncode(current.map((e) => e.toJson()).toList()),
    );
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

class GifPickerPanel extends StatefulWidget {
  const GifPickerPanel({super.key});

  @override
  State<GifPickerPanel> createState() => _GifPickerPanelState();
}

class _GifPickerPanelState extends State<GifPickerPanel> {
  static const _prefsKey = 'offline_stickers_v1';
  static const _packsPrefsKey = 'offline_sticker_packs_v1';
  static const _maxStickerBytes = 10 * 1024 * 1024; // 10MB limit

  List<LocalSticker> _stickers = const [];
  List<LocalStickerPack> _packs = const [];
  String? _selectedPackId;
  bool _loading = true;
  bool _importing = false;
  String _filter = 'الكل';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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
    final sheetBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final surfaceVariant = isDark ? const Color(0xFF28282C) : const Color(0xFFF1F5F9);
    final borderColor = isDark ? const Color(0xFF2D2D32) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final visibleStickers = _visible;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // ── Drag Handle ──────────────────────────────────────────────
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),

            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: primaryAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.auto_awesome_motion_rounded,
                      color: primaryAccent,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
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
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: surfaceVariant,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                '${_stickers.length}',
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'ملصقاتك الخاصة والمحفوظة وتعمل بدون إنترنت',
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'حزمة جديدة',
                    splashRadius: 18,
                    onPressed: _createPack,
                    icon: Icon(
                      Icons.create_new_folder_outlined,
                      color: textSecondary,
                      size: 20,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _importing ? null : _import,
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    icon: _importing
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.add_photo_alternate_rounded, size: 15),
                    label: const Text(
                      'استيراد',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),

            // ── Search Bar ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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

            // ── Categories & Packs Tabs ─────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
                        borderRadius: BorderRadius.circular(9),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? primaryAccent
                                : (isDark ? const Color(0xFF28282C) : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(9),
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
                                size: 13,
                                color: isSelected ? Colors.white : textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${pack.name} ($count)',
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                                  fontSize: 11,
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

            const SizedBox(height: 4),

            // ── Stickers Grid ───────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : visibleStickers.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: surfaceVariant,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _searchController.text.isNotEmpty
                                    ? Icons.search_off_rounded
                                    : Icons.auto_awesome_motion_rounded,
                                size: 28,
                                color: textSecondary.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'لا توجد ملصقات مطابقة للبحث'
                                  : 'لا توجد ملصقات بعد في هذه القائمة',
                              style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'جرب البحث بكلمة أخرى أو تصفح الباقات الأخرى.'
                                  : 'يمكنك استيراد صور أو GIFs أو حفظ الملصقات التي تصلك في المحادثات بنقرة واحدة.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                            if (_searchController.text.isEmpty) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _import,
                                icon: const Icon(Icons.add_photo_alternate_outlined, size: 15),
                                label: const Text('استيراد ملصقات من جهازك'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: visibleStickers.length,
                      itemBuilder: (context, index) {
                        final sticker = visibleStickers[index];
                        return _MobileStickerCard(
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

            // ── Footer Helper ───────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: surfaceVariant.withValues(alpha: 0.5),
                border: Border(top: BorderSide(color: borderColor, width: 0.8)),
              ),
              child: Row(
                children: [
                  Icon(Icons.touch_app_outlined, size: 13, color: textSecondary),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'المس الملصق لإرساله فورًا. اضغط مطولاً للخيارات أو الحذف.',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryAccent
              : (isDark ? const Color(0xFF28282C) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(9),
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
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _MobileStickerCard extends StatelessWidget {
  const _MobileStickerCard({
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

  void _showStickerActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  sticker.favorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: const Color(0xFFF59E0B),
                ),
                title: Text(sticker.favorite ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة'),
                onTap: () {
                  Navigator.pop(ctx);
                  onToggleFavorite();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFEF4444),
                ),
                title: const Text(
                  'حذف الملصق',
                  style: TextStyle(color: Color(0xFFEF4444)),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF242428) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? const Color(0xFF323238) : const Color(0xFFE2E8F0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showStickerActions(context),
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: borderColor, width: 0.8),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Image.memory(
                    sticker.bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
              if (sticker.favorite)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.black54 : Colors.white).withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.star_rounded,
                      size: 13,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
