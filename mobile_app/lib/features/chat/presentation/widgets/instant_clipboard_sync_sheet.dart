import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/providers/providers.dart';

class SyncedClipboardItem {
  const SyncedClipboardItem({
    required this.id,
    required this.text,
    required this.sourceClientType,
    required this.sourceDeviceName,
    this.sourceDeviceUid,
    this.autoCopy = true,
    required this.createdAt,
  });

  final String id;
  final String text;
  final String sourceClientType;
  final String sourceDeviceName;
  final String? sourceDeviceUid;
  final bool autoCopy;
  final DateTime createdAt;

  bool get isFromDesktop => sourceClientType.toLowerCase() == 'desktop';

  bool get isUrl {
    final trimmed = text.trim();
    if (trimmed.contains(' ') || trimmed.contains('\n')) return false;
    final uri = Uri.tryParse(trimmed);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'text': text,
    'sourceClientType': sourceClientType,
    'sourceDeviceName': sourceDeviceName,
    if (sourceDeviceUid != null) 'sourceDeviceUid': sourceDeviceUid,
    'autoCopy': autoCopy,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory SyncedClipboardItem.fromJson(Map<String, dynamic> json) {
    final rawCreated = json['createdAt']?.toString();
    final createdAt = rawCreated != null
        ? (DateTime.tryParse(rawCreated)?.toLocal() ?? DateTime.now())
        : DateTime.now();
    final clientType = (json['sourceClientType'] ?? 'unknown')
        .toString()
        .trim()
        .toLowerCase();
    final defaultName = clientType == 'desktop'
        ? 'كمبيوتر المكتب Windows'
        : clientType == 'mobile'
        ? 'هاتف الموبايل'
        : 'جهاز متصل';
    return SyncedClipboardItem(
      id:
          json['id']?.toString() ??
          'clip_${DateTime.now().millisecondsSinceEpoch}',
      text: (json['text'] ?? '').toString(),
      sourceClientType: clientType,
      sourceDeviceName:
          json['sourceDeviceName']?.toString().trim().isNotEmpty == true
          ? json['sourceDeviceName'].toString().trim()
          : defaultName,
      sourceDeviceUid: json['sourceDeviceUid']?.toString(),
      autoCopy: json['autoCopy'] != false,
      createdAt: createdAt,
    );
  }
}

class InstantClipboardSyncState {
  const InstantClipboardSyncState({
    this.items = const <SyncedClipboardItem>[],
    this.hasDesktopConnected = false,
    this.isSyncing = false,
  });

  final List<SyncedClipboardItem> items;
  final bool hasDesktopConnected;
  final bool isSyncing;

  InstantClipboardSyncState copyWith({
    List<SyncedClipboardItem>? items,
    bool? hasDesktopConnected,
    bool? isSyncing,
  }) {
    return InstantClipboardSyncState(
      items: items ?? this.items,
      hasDesktopConnected: hasDesktopConnected ?? this.hasDesktopConnected,
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }
}

final instantClipboardSyncControllerProvider =
    StateNotifierProvider<
      InstantClipboardSyncController,
      InstantClipboardSyncState
    >((ref) {
      return InstantClipboardSyncController(ref);
    });

class InstantClipboardSyncController
    extends StateNotifier<InstantClipboardSyncState> {
  InstantClipboardSyncController(this._ref)
    : super(const InstantClipboardSyncState()) {
    _loadLocalHistory();
  }

  static const _storageKey = 'instant_clipboard_sync_history_v1';
  static const _maxItems = 20;

  final Ref _ref;

  Future<void> _loadLocalHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final parsed = decoded
          .whereType<Map>()
          .map(
            (e) => SyncedClipboardItem.fromJson(Map<String, dynamic>.from(e)),
          )
          .where((e) => e.text.trim().isNotEmpty)
          .take(_maxItems)
          .toList();
      if (mounted) {
        state = state.copyWith(items: parsed);
      }
    } catch (_) {}
  }

  Future<void> _persistLocalHistory(List<SyncedClipboardItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        items.take(_maxItems).map((e) => e.toJson()).toList(),
      );
      await prefs.setString(_storageKey, encoded);
    } catch (_) {}
  }

  List<SyncedClipboardItem> _mergeItems(
    List<SyncedClipboardItem> incoming,
    List<SyncedClipboardItem> current,
  ) {
    final byText = <String, SyncedClipboardItem>{};
    for (final item in [...incoming, ...current]) {
      final key = item.text.trim();
      if (key.isEmpty) continue;
      final existing = byText[key];
      if (existing == null || item.createdAt.isAfter(existing.createdAt)) {
        byText[key] = item;
      }
    }
    final merged = byText.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return merged.take(_maxItems).toList();
  }

  Future<void> refreshFromServer() async {
    try {
      final socket = _ref.read(chatSocketServiceProvider);
      if (!socket.isConnected) return;
      final response = await socket.emitWithAck(
        'clipboard:get_history',
        const <String, dynamic>{},
        timeout: const Duration(seconds: 6),
      );
      if (response['ok'] == true && response['data'] is Map) {
        final data = Map<String, dynamic>.from(response['data'] as Map);
        final rawHistory = data['history'];
        final serverItems = rawHistory is List
            ? rawHistory
                  .whereType<Map>()
                  .map(
                    (e) => SyncedClipboardItem.fromJson(
                      Map<String, dynamic>.from(e),
                    ),
                  )
                  .toList()
            : <SyncedClipboardItem>[];
        final merged = _mergeItems(serverItems, state.items);
        if (mounted) {
          state = state.copyWith(
            items: merged,
            hasDesktopConnected: data['hasDesktop'] == true,
          );
        }
        await _persistLocalHistory(merged);
      }
    } catch (_) {}
  }

  Future<({SyncedClipboardItem item, bool deliveredToDesktop})> syncText(
    String rawText, {
    bool copyLocally = true,
  }) async {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      throw Exception('النص المراد مزامنته فارغ.');
    }

    if (mounted) {
      state = state.copyWith(isSyncing: true);
    }

    try {
      if (copyLocally) {
        await Clipboard.setData(ClipboardData(text: trimmed));
      }

      final socket = _ref.read(chatSocketServiceProvider);
      final ack = await socket.emitWithAck('clipboard:sync', <String, dynamic>{
        'text': trimmed,
        'sourceClientType': 'mobile',
        'sourceDeviceName': 'هاتف الموبايل',
        'autoCopy': true,
      }, timeout: const Duration(seconds: 8));

      SyncedClipboardItem syncedItem;
      bool hasDesktop = state.hasDesktopConnected;

      if (ack['ok'] == true && ack['data'] is Map) {
        final data = Map<String, dynamic>.from(ack['data'] as Map);
        hasDesktop = data['hasDesktop'] == true;
        if (data['item'] is Map) {
          syncedItem = SyncedClipboardItem.fromJson(
            Map<String, dynamic>.from(data['item'] as Map),
          );
        } else {
          syncedItem = SyncedClipboardItem(
            id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
            text: trimmed,
            sourceClientType: 'mobile',
            sourceDeviceName: 'هاتف الموبايل',
            createdAt: DateTime.now(),
          );
        }
      } else {
        syncedItem = SyncedClipboardItem(
          id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
          text: trimmed,
          sourceClientType: 'mobile',
          sourceDeviceName: 'هاتف الموبايل',
          createdAt: DateTime.now(),
        );
      }

      final updated = _mergeItems([syncedItem], state.items);
      if (mounted) {
        state = state.copyWith(
          items: updated,
          hasDesktopConnected: hasDesktop,
          isSyncing: false,
        );
      }
      await _persistLocalHistory(updated);
      return (item: syncedItem, deliveredToDesktop: hasDesktop);
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isSyncing: false);
      }
      rethrow;
    }
  }

  Future<SyncedClipboardItem?> handleIncomingSyncEvent(
    Map<String, dynamic> payload,
  ) async {
    final item = SyncedClipboardItem.fromJson(payload);
    if (item.text.trim().isEmpty) return null;

    if (item.autoCopy) {
      try {
        await Clipboard.setData(ClipboardData(text: item.text));
      } catch (_) {}
    }

    final updated = _mergeItems([item], state.items);
    if (mounted) {
      state = state.copyWith(
        items: updated,
        hasDesktopConnected: item.isFromDesktop || state.hasDesktopConnected,
      );
    }
    await _persistLocalHistory(updated);
    return item;
  }

  Future<void> handleHistoryUpdatedEvent(Map<String, dynamic> payload) async {
    final rawHistory = payload['history'];
    if (rawHistory is! List) return;
    final serverItems = rawHistory
        .whereType<Map>()
        .map((e) => SyncedClipboardItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.text.trim().isNotEmpty)
        .toList();
    if (serverItems.isEmpty) {
      if (mounted) {
        state = state.copyWith(items: const <SyncedClipboardItem>[]);
      }
      await _persistLocalHistory(const <SyncedClipboardItem>[]);
      return;
    }
    final merged = _mergeItems(serverItems, state.items);
    if (mounted) {
      state = state.copyWith(items: merged);
    }
    await _persistLocalHistory(merged);
  }

  Future<void> clearHistory() async {
    if (mounted) {
      state = state.copyWith(items: const <SyncedClipboardItem>[]);
    }
    await _persistLocalHistory(const <SyncedClipboardItem>[]);
    try {
      final socket = _ref.read(chatSocketServiceProvider);
      if (socket.isConnected) {
        await socket.emitWithAck(
          'clipboard:clear_history',
          const <String, dynamic>{},
          timeout: const Duration(seconds: 5),
        );
      }
    } catch (_) {}
  }
}

Future<void> showInstantClipboardSyncSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  HapticFeedback.selectionClick();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _InstantClipboardSyncBottomSheet(),
  );
}

class _InstantClipboardSyncBottomSheet extends ConsumerStatefulWidget {
  const _InstantClipboardSyncBottomSheet();

  @override
  ConsumerState<_InstantClipboardSyncBottomSheet> createState() =>
      _InstantClipboardSyncBottomSheetState();
}

class _InstantClipboardSyncBottomSheetState
    extends ConsumerState<_InstantClipboardSyncBottomSheet> {
  final TextEditingController _textController = TextEditingController();
  String? _localClipboardPreview;

  @override
  void initState() {
    super.initState();
    _inspectLocalClipboard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(instantClipboardSyncControllerProvider.notifier)
          .refreshFromServer();
    });
  }

  Future<void> _inspectLocalClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text?.trim();
      if (mounted && text != null && text.isNotEmpty) {
        setState(() {
          _localClipboardPreview = text;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _sendFromSystemClipboard() async {
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text?.trim() ?? _localClipboardPreview?.trim() ?? '';
      if (text.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('حافظة الهاتف فارغة حالياً. انسخ أي نص أو اكتبه بالأسفل.'),
          ),
        );
        return;
      }
      final res = await ref
          .read(instantClipboardSyncControllerProvider.notifier)
          .syncText(text, copyLocally: false);
      if (!mounted) return;
      setState(() {
        _localClipboardPreview = text;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            res.deliveredToDesktop
                ? '⚡ تم نسخ النص فوراً في حافظة الكمبيوتر!'
                : 'تم حفظ ومزامنة النص في الحافظة المشتركة.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('تعذر المزامنة: $e')));
    }
  }

  Future<void> _sendCustomText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await ref
          .read(instantClipboardSyncControllerProvider.notifier)
          .syncText(text);
      if (!mounted) return;
      _textController.clear();
      setState(() {
        _localClipboardPreview = text;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            res.deliveredToDesktop
                ? '⚡ تم إرسال النص ونسخه تلقائياً في حافظة الكمبيوتر!'
                : 'تمت إضافة النص إلى الحافظة المشتركة ونسخه.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('تعذر الإرسال: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final borderColor = isDark ? Colors.white12 : const Color(0xFFE2E8F0);
    final subColor = isDark ? Colors.white60 : const Color(0xFF64748B);
    final syncState = ref.watch(instantClipboardSyncControllerProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      CupertinoIcons.doc_on_clipboard_fill,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'الحافظة المشتركة الفورية',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 7.5,
                              height: 7.5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: syncState.hasDesktopConnected
                                    ? const Color(0xFF34C759)
                                    : const Color(0xFFFF9500),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                syncState.hasDesktopConnected
                                    ? 'كمبيوتر المكتب متصل الآن • نسخ فوري بضغطة واحدة'
                                    : 'انسخ أي نص أو رابط ليظهر في الكمبيوتر والموبايل معاً',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: syncState.hasDesktopConnected
                                      ? const Color(0xFF34C759)
                                      : subColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (syncState.items.isNotEmpty)
                    IconButton(
                      tooltip: 'مسح السجل',
                      icon: const Icon(
                        CupertinoIcons.trash,
                        size: 19,
                        color: Color(0xFFFF3B30),
                      ),
                      onPressed: () {
                        ref
                            .read(
                              instantClipboardSyncControllerProvider.notifier,
                            )
                            .clearHistory();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // ── 1-Tap Send Current Mobile Clipboard to PC ─────────────────
              FilledButton.icon(
                onPressed: syncState.isSyncing ? null : _sendFromSystemClipboard,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: syncState.isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.bolt_rounded, size: 21),
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'إرسال حافظة الموبايل الحالية إلى الكمبيوتر فوراً',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (_localClipboardPreview != null &&
                        _localClipboardPreview!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '«${_localClipboardPreview!.replaceAll('\n', ' ')}»',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Custom Text / Link / Code Input Box ───────────────────────
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor, width: 0.8),
                ),
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendCustomText(),
                        style: const TextStyle(fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText:
                              'أو الصق نصاً، رابطاً، أو كود هنا لإرساله للكمبيوتر...',
                          hintStyle: TextStyle(fontSize: 12.5, color: subColor),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.tonalIcon(
                      onPressed: syncState.isSyncing ? null : _sendCustomText,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(
                        CupertinoIcons.arrow_up_right_square_fill,
                        size: 16,
                      ),
                      label: const Text(
                        'إرسال',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Shared Clipboard History List ─────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Text(
                      'أحدث النصوص والروابط المتزامنة (${syncState.items.length})',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: subColor,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'الموبايل ⇄ الكمبيوتر',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: subColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              Flexible(
                child: syncState.items.isEmpty
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 28,
                        ),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: borderColor, width: 0.7),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.doc_on_clipboard,
                              size: 36,
                              color: subColor,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'لا توجد نصوص في الحافظة المشتركة بعد',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'أي نص أو رابط تنسخه من الكمبيوتر عبر زر الحافظة المشتركة سيظهر هنا ويُنسخ تلقائياً في هاتفك بدون إرسال رسالة.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: subColor,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: syncState.items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = syncState.items[index];
                          return _buildClipItemCard(
                            item: item,
                            cardColor: cardColor,
                            borderColor: borderColor,
                            subColor: subColor,
                            isDark: isDark,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClipItemCard({
    required SyncedClipboardItem item,
    required Color cardColor,
    required Color borderColor,
    required Color subColor,
    required bool isDark,
  }) {
    final badgeColor = item.isFromDesktop
        ? const Color(0xFF5856D6)
        : const Color(0xFF007AFF);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 0.7),
      ),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.isFromDesktop
                          ? CupertinoIcons.desktopcomputer
                          : CupertinoIcons.device_phone_portrait,
                      size: 12.5,
                      color: badgeColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      item.isFromDesktop ? 'من الكمبيوتر' : 'من الموبايل',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: badgeColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatEgyptDateTime(item.createdAt),
                  style: TextStyle(fontSize: 11, color: subColor),
                ),
              ),
              if (item.isUrl)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      final uri = Uri.tryParse(item.text.trim());
                      if (uri != null && await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34C759).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.link,
                            size: 12,
                            color: Color(0xFF34C759),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'فتح الرابط',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF34C759),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  HapticFeedback.lightImpact();
                  await Clipboard.setData(ClipboardData(text: item.text));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم نسخ النص إلى حافظة الهاتف'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.doc_on_doc,
                        size: 12.5,
                        color: Color(0xFF007AFF),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'نسخ',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF007AFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  HapticFeedback.lightImpact();
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref
                        .read(instantClipboardSyncControllerProvider.notifier)
                        .syncText(item.text);
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('⚡ تم إرسال النص مجدداً لحافظة الكمبيوتر'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  } catch (_) {}
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    CupertinoIcons.arrow_2_circlepath,
                    size: 13.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            item.text,
            maxLines: 4,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: item.isUrl
                  ? const Color(0xFF007AFF)
                  : (isDark ? Colors.white : const Color(0xFF0F172A)),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
