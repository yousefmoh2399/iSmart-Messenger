import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/providers/providers.dart';

class DesktopSyncedClipboardItem {
  const DesktopSyncedClipboardItem({
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

  bool get isFromMobile => sourceClientType.toLowerCase() == 'mobile';

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

  factory DesktopSyncedClipboardItem.fromJson(Map<String, dynamic> json) {
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
    return DesktopSyncedClipboardItem(
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

class DesktopClipboardSyncState {
  const DesktopClipboardSyncState({
    this.items = const <DesktopSyncedClipboardItem>[],
    this.hasMobileConnected = false,
    this.isSyncing = false,
  });

  final List<DesktopSyncedClipboardItem> items;
  final bool hasMobileConnected;
  final bool isSyncing;

  DesktopClipboardSyncState copyWith({
    List<DesktopSyncedClipboardItem>? items,
    bool? hasMobileConnected,
    bool? isSyncing,
  }) {
    return DesktopClipboardSyncState(
      items: items ?? this.items,
      hasMobileConnected: hasMobileConnected ?? this.hasMobileConnected,
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }
}

final desktopClipboardSyncControllerProvider =
    StateNotifierProvider<
      DesktopClipboardSyncController,
      DesktopClipboardSyncState
    >((ref) {
      return DesktopClipboardSyncController(ref);
    });

class DesktopClipboardSyncController
    extends StateNotifier<DesktopClipboardSyncState> {
  DesktopClipboardSyncController(this._ref)
    : super(const DesktopClipboardSyncState()) {
    _loadLocalHistory();
  }

  static const _storageKey = 'desktop_instant_clipboard_sync_history_v1';
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
            (e) => DesktopSyncedClipboardItem.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .where((e) => e.text.trim().isNotEmpty)
          .take(_maxItems)
          .toList();
      if (mounted) {
        state = state.copyWith(items: parsed);
      }
    } catch (_) {}
  }

  Future<void> _persistLocalHistory(
    List<DesktopSyncedClipboardItem> items,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        items.take(_maxItems).map((e) => e.toJson()).toList(),
      );
      await prefs.setString(_storageKey, encoded);
    } catch (_) {}
  }

  List<DesktopSyncedClipboardItem> _mergeItems(
    List<DesktopSyncedClipboardItem> incoming,
    List<DesktopSyncedClipboardItem> current,
  ) {
    final byText = <String, DesktopSyncedClipboardItem>{};
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
                    (e) => DesktopSyncedClipboardItem.fromJson(
                      Map<String, dynamic>.from(e),
                    ),
                  )
                  .toList()
            : <DesktopSyncedClipboardItem>[];
        final merged = _mergeItems(serverItems, state.items);
        if (mounted) {
          state = state.copyWith(
            items: merged,
            hasMobileConnected: data['hasMobile'] == true,
          );
        }
        await _persistLocalHistory(merged);
      }
    } catch (_) {}
  }

  Future<({DesktopSyncedClipboardItem item, bool deliveredToMobile})> syncText(
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
        'sourceClientType': 'desktop',
        'sourceDeviceName': 'كمبيوتر المكتب Windows',
        'autoCopy': true,
      }, timeout: const Duration(seconds: 8));

      DesktopSyncedClipboardItem syncedItem;
      bool hasMobile = state.hasMobileConnected;

      if (ack['ok'] == true && ack['data'] is Map) {
        final data = Map<String, dynamic>.from(ack['data'] as Map);
        hasMobile = data['hasMobile'] == true;
        if (data['item'] is Map) {
          syncedItem = DesktopSyncedClipboardItem.fromJson(
            Map<String, dynamic>.from(data['item'] as Map),
          );
        } else {
          syncedItem = DesktopSyncedClipboardItem(
            id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
            text: trimmed,
            sourceClientType: 'desktop',
            sourceDeviceName: 'كمبيوتر المكتب Windows',
            createdAt: DateTime.now(),
          );
        }
      } else {
        syncedItem = DesktopSyncedClipboardItem(
          id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
          text: trimmed,
          sourceClientType: 'desktop',
          sourceDeviceName: 'كمبيوتر المكتب Windows',
          createdAt: DateTime.now(),
        );
      }

      final updated = _mergeItems([syncedItem], state.items);
      if (mounted) {
        state = state.copyWith(
          items: updated,
          hasMobileConnected: hasMobile,
          isSyncing: false,
        );
      }
      await _persistLocalHistory(updated);
      return (item: syncedItem, deliveredToMobile: hasMobile);
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isSyncing: false);
      }
      rethrow;
    }
  }

  Future<DesktopSyncedClipboardItem?> handleIncomingSyncEvent(
    Map<String, dynamic> payload,
  ) async {
    final item = DesktopSyncedClipboardItem.fromJson(payload);
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
        hasMobileConnected: item.isFromMobile || state.hasMobileConnected,
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
        .map(
          (e) =>
              DesktopSyncedClipboardItem.fromJson(Map<String, dynamic>.from(e)),
        )
        .where((e) => e.text.trim().isNotEmpty)
        .toList();
    if (serverItems.isEmpty) {
      if (mounted) {
        state = state.copyWith(items: const <DesktopSyncedClipboardItem>[]);
      }
      await _persistLocalHistory(const <DesktopSyncedClipboardItem>[]);
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
      state = state.copyWith(items: const <DesktopSyncedClipboardItem>[]);
    }
    await _persistLocalHistory(const <DesktopSyncedClipboardItem>[]);
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

Future<void> showDesktopInstantClipboardSyncDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _DesktopInstantClipboardSyncDialog(),
  );
}

class _DesktopInstantClipboardSyncDialog extends ConsumerStatefulWidget {
  const _DesktopInstantClipboardSyncDialog();

  @override
  ConsumerState<_DesktopInstantClipboardSyncDialog> createState() =>
      _DesktopInstantClipboardSyncDialogState();
}

class _DesktopInstantClipboardSyncDialogState
    extends ConsumerState<_DesktopInstantClipboardSyncDialog> {
  final TextEditingController _textController = TextEditingController();
  String? _localClipboardPreview;

  @override
  void initState() {
    super.initState();
    _inspectLocalClipboard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(desktopClipboardSyncControllerProvider.notifier)
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
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text?.trim() ?? _localClipboardPreview?.trim() ?? '';
      if (text.isEmpty) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('حافظة الكمبيوتر فارغة حالياً. انسخ أي نص أو اكتبه بالأسفل.'),
          ),
        );
        return;
      }
      final res = await ref
          .read(desktopClipboardSyncControllerProvider.notifier)
          .syncText(text, copyLocally: false);
      if (!mounted) return;
      setState(() {
        _localClipboardPreview = text;
      });
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            res.deliveredToMobile
                ? '⚡ تم نسخ النص فوراً في حافظة الموبايل!'
                : 'تم حفظ ومزامنة النص في الحافظة المشتركة.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text('تعذر المزامنة: $e')));
    }
  }

  Future<void> _sendCustomText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final res = await ref
          .read(desktopClipboardSyncControllerProvider.notifier)
          .syncText(text);
      if (!mounted) return;
      _textController.clear();
      setState(() {
        _localClipboardPreview = text;
      });
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            res.deliveredToMobile
                ? '⚡ تم إرسال النص ونسخه تلقائياً في حافظة الموبايل!'
                : 'تمت إضافة النص إلى الحافظة المشتركة ونسخه.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text('تعذر الإرسال: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1E242B) : Colors.white;
    final cardColor = isDark
        ? const Color(0xFF28303A)
        : const Color(0xFFF8FAFC);
    final borderColor = isDark ? Colors.white12 : const Color(0xFFE2E8F0);
    final subColor = isDark ? Colors.white60 : const Color(0xFF64748B);
    final syncState = ref.watch(desktopClipboardSyncControllerProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 650),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                        ),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.content_paste_go_rounded,
                        color: Colors.white,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'الحافظة المشتركة الفورية (الكمبيوتر ⇄ الموبايل)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: syncState.hasMobileConnected
                                      ? const Color(0xFF22C55E)
                                      : const Color(0xFFF59E0B),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  syncState.hasMobileConnected
                                      ? 'تطبيق الموبايل متصل الآن • أي نص ترسله يُنسخ فوراً في الهاتف'
                                      : 'انسخ أي نص أو رابط أو كود ليظهر فوراً في الموبايل بدون إرسال رسالة',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: syncState.hasMobileConnected
                                        ? const Color(0xFF22C55E)
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
                        tooltip: 'مسح سجل الحافظة المشتركة',
                        icon: const Icon(
                          Icons.delete_sweep_outlined,
                          color: Color(0xFFEF4444),
                        ),
                        onPressed: () {
                          ref
                              .read(
                                desktopClipboardSyncControllerProvider.notifier,
                              )
                              .clearHistory();
                        },
                      ),
                    IconButton(
                      tooltip: 'إغلاق',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── 1-Click Send Current Windows Clipboard to Mobile ─────────
                FilledButton.icon(
                  onPressed: syncState.isSyncing
                      ? null
                      : _sendFromSystemClipboard,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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
                      : const Icon(Icons.bolt_rounded, size: 22),
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'إرسال محتوى حافظة الكمبيوتر الحالية إلى الموبايل فوراً',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (_localClipboardPreview != null &&
                          _localClipboardPreview!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          '«${_localClipboardPreview!.replaceAll('\n', ' ')}»',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Custom Text / Link / Code Input Box ──────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          minLines: 1,
                          maxLines: 3,
                          onSubmitted: (_) => _sendCustomText(),
                          style: const TextStyle(fontSize: 13.5),
                          decoration: InputDecoration(
                            hintText:
                                'أو اكتب / الصق نصاً أو رابطاً أو كود هنا لإرساله للموبايل...',
                            hintStyle: TextStyle(
                              fontSize: 12.5,
                              color: subColor,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: syncState.isSyncing ? null : _sendCustomText,
                        icon: const Icon(Icons.send_to_mobile_rounded, size: 17),
                        label: const Text(
                          'مزامنة للموبايل',
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

                Row(
                  children: [
                    Text(
                      'سجل الحافظة المشتركة (${syncState.items.length})',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: subColor,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        _inspectLocalClipboard();
                        ref
                            .read(
                              desktopClipboardSyncControllerProvider.notifier,
                            )
                            .refreshFromServer();
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: const Text(
                        'تحديث',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                Flexible(
                  child: syncState.items.isEmpty
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 32,
                          ),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.content_paste_search_rounded,
                                size: 38,
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
                                'انسخ أي نص من الموبايل أو الكمبيوتر واضغط زر الحافظة المشتركة ليتم نسخه فوراً على الجهاز الآخر.',
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
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = syncState.items[index];
                            final badgeColor = item.isFromMobile
                                ? const Color(0xFF007AFF)
                                : const Color(0xFF5856D6);
                            return Container(
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: borderColor),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: badgeColor.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            7,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              item.isFromMobile
                                                  ? Icons.smartphone_rounded
                                                  : Icons.desktop_windows_rounded,
                                              size: 13,
                                              color: badgeColor,
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              item.isFromMobile
                                                  ? 'وارد من الموبايل'
                                                  : 'مرسل من الكمبيوتر',
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
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: subColor,
                                          ),
                                        ),
                                      ),
                                      if (item.isUrl)
                                        TextButton.icon(
                                          onPressed: () async {
                                            final uri = Uri.tryParse(
                                              item.text.trim(),
                                            );
                                            if (uri != null &&
                                                await canLaunchUrl(uri)) {
                                              await launchUrl(
                                                uri,
                                                mode: LaunchMode
                                                    .externalApplication,
                                              );
                                            }
                                          },
                                          icon: const Icon(
                                            Icons.open_in_new_rounded,
                                            size: 14,
                                          ),
                                          label: const Text(
                                            'فتح الرابط',
                                            style: TextStyle(fontSize: 11.5),
                                          ),
                                        ),
                                      TextButton.icon(
                                        onPressed: () async {
                                          await Clipboard.setData(
                                            ClipboardData(text: item.text),
                                          );
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.maybeOf(
                                            context,
                                          )?.showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'تم نسخ النص إلى حافظة الكمبيوتر',
                                              ),
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.copy_rounded,
                                          size: 14,
                                        ),
                                        label: const Text(
                                          'نسخ',
                                          style: TextStyle(fontSize: 11.5),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'إعادة إرسال للموبايل',
                                        icon: const Icon(
                                          Icons.send_to_mobile_rounded,
                                          size: 16,
                                        ),
                                        onPressed: () async {
                                          final messenger =
                                              ScaffoldMessenger.maybeOf(
                                                context,
                                              );
                                          try {
                                            await ref
                                                .read(
                                                  desktopClipboardSyncControllerProvider
                                                      .notifier,
                                                )
                                                .syncText(item.text);
                                            messenger?.showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  '⚡ تم إرسال النص مجدداً إلى حافظة الموبايل',
                                                ),
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          } catch (_) {}
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  SelectableText(
                                    item.text,
                                    maxLines: 4,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                      color: item.isUrl
                                          ? const Color(0xFF007AFF)
                                          : (isDark
                                                ? Colors.white
                                                : const Color(0xFF0F172A)),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
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
