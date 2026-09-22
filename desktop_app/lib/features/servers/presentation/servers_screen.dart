import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;
import '../../../shared/widgets/desktop_workspace_sidebar.dart';
import '../../chat/data/chat_socket_service.dart';
import '../../updates/presentation/update_center_screen.dart';

bool _webViewEnvironmentReady = false;

const List<_ServerTarget> _defaultServerTargets = [
  _ServerTarget(
    title: 'iSmart Messenger (251)',
    baseUrl: 'http://192.168.100.251:9090/',
    fallbackPorts: [9090],
  ),
  _ServerTarget(
    title: 'نظام القروض',
    baseUrl:
        'http://172.21.21.15:7003/mf/faces/loginpage?_afrLoop=131657097608000&Adf-Window-Id=w0&_afrWindowMode=0&_adf.ctrl-state=192ye88a61_3&_afrRedirect=131657346396800',
    fallbackPorts: [7003],
  ),
  _ServerTarget(
    title: 'Archive SVR (252)',
    baseUrl: 'http://192.168.100.252:9090/',
    fallbackPorts: [9090],
  ),
];

class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({super.key, this.isWrapped = false});

  final bool isWrapped;

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen>
    with WidgetsBindingObserver {
  static const String _lastPortPrefsPrefix = 'servers_last_port_';
  static const String _serversConnectTimeoutPrefsKey =
      'servers_connect_timeout_ms_v1';
  static const String _serversRequestTimeoutPrefsKey =
      'servers_request_timeout_ms_v1';
  static const String _serversAutoRetriesPrefsKey = 'servers_auto_retries_v1';
  final Map<String, List<bool>> _probeHistoryByServer = <String, List<bool>>{};
  List<_ServerTarget> _targets = List<_ServerTarget>.from(
    _defaultServerTargets,
  );

  late List<_ServerHealth> _health;
  bool _loading = true;
  _ServersFilter _filter = _ServersFilter.all;
  DateTime? _lastRefreshAt;
  _ServerTarget? _selected;
  int? _selectedPort;
  int _connectTimeoutMs = 3000;
  int _requestTimeoutMs = 4000;
  int _autoRetries = 2;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;
  StreamSubscription<ChatSocketEvent>? _socketEventsSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _health = _targets.map((_) => _ServerHealth.unknown()).toList();
    _listenToSocketEvents();
    unawaited(_initializeSettingsAndRefresh());
  }

  Future<void> _initializeSettingsAndRefresh() async {
    await _loadRetrySettings();
    await _loadServerTargets();
    await _requestRefresh();
  }

  Future<void> _loadServerTargets() async {
    try {
      final settings = await ref
          .read(publicAppSettingsServiceProvider)
          .fetchDefaults();
      final remoteTargets = settings.serverTargets
          .where((entry) => entry.title.trim().isNotEmpty)
          .where((entry) => entry.baseUrl.trim().isNotEmpty)
          .map(
            (entry) => _ServerTarget(
              title: entry.title.trim(),
              baseUrl: entry.baseUrl.trim(),
              fallbackPorts: entry.ports.isEmpty ? const [80] : entry.ports,
            ),
          )
          .toList();
      if (!mounted) {
        return;
      }
      setState(() {
        _targets = remoteTargets;
        _health = _targets.map((_) => _ServerHealth.unknown()).toList();
        _selected = null;
        _selectedPort = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _targets = List<_ServerTarget>.from(_defaultServerTargets);
        _health = _targets.map((_) => _ServerHealth.unknown()).toList();
      });
    }
  }

  Future<void> _loadRetrySettings() async {
    final prefs = await SharedPreferences.getInstance();
    _connectTimeoutMs = prefs.getInt(_serversConnectTimeoutPrefsKey) ?? 3000;
    _requestTimeoutMs = prefs.getInt(_serversRequestTimeoutPrefsKey) ?? 4000;
    _autoRetries = prefs.getInt(_serversAutoRetriesPrefsKey) ?? 2;
  }

  @override
  void dispose() {
    _socketEventsSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !(kIsWeb && web_bridge.isElectron())) {
      unawaited(_requestRefresh(showLoading: false));
    }
  }

  void _listenToSocketEvents() {
    _socketEventsSubscription?.cancel();
    final socket = ref.read(chatSocketServiceProvider);
    _socketEventsSubscription = socket.events.listen((event) {
      if (!mounted) {
        return;
      }
      if (event.type == 'socket_connected' ||
          event.type == 'socket_disconnected' ||
          event.type == 'socket_error') {
        unawaited(_requestRefresh(showLoading: false));
      }
    });
  }

  Future<void> _requestRefresh({bool showLoading = true}) async {
    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }
    _refreshInFlight = true;
    var currentShowLoading = showLoading;
    try {
      do {
        _refreshQueued = false;
        await _refreshStatuses(showLoading: currentShowLoading);
        currentShowLoading = false;
      } while (_refreshQueued && mounted);
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _refreshStatuses({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _loading = true);
    }
    if (_targets.isEmpty) {
      if (!mounted) return;
      setState(() {
        _health = const <_ServerHealth>[];
        _loading = false;
        _lastRefreshAt = DateTime.now();
      });
      return;
    }
    final previous = List<_ServerHealth>.from(_health);
    final next = await Future.wait(_targets.map(_probeServerHealth));
    if (!mounted) return;
    setState(() {
      _health = next;
      _loading = false;
      _lastRefreshAt = DateTime.now();
    });
    _notifyNewDownServers(previous, next);
  }

  double _recordAndScore(_ServerTarget target, bool isUp) {
    final key = _serverPrefsKey(target);
    final history = _probeHistoryByServer.putIfAbsent(key, () => <bool>[]);
    history.add(isUp);
    if (history.length > 30) {
      history.removeRange(0, history.length - 30);
    }
    final upCount = history.where((entry) => entry).length;
    return history.isEmpty ? 0 : (upCount / history.length) * 100;
  }

  void _notifyNewDownServers(
    List<_ServerHealth> previous,
    List<_ServerHealth> current,
  ) {
    for (var i = 0; i < current.length; i++) {
      final prevStatus = i < previous.length
          ? previous[i].status
          : _ServerStatus.unknown;
      if ((prevStatus == _ServerStatus.up ||
              prevStatus == _ServerStatus.degraded) &&
          current[i].status == _ServerStatus.down &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تنبيه: السيرفر "${_targets[i].title}" أصبح غير متاح.',
            ),
          ),
        );
      }
    }
  }

  Future<List<_PortProbe>> _probePorts(_ServerTarget target) async {
    final base = Uri.parse(target.baseUrl);
    return Future.wait(
      target.fallbackPorts.map(
        (port) => _probePortHealth(
          base.replace(port: port),
          connectTimeoutMs: _connectTimeoutMs,
          requestTimeoutMs: _requestTimeoutMs,
        ),
      ),
    );
  }

  List<_PortProbe> _rankPorts(List<_PortProbe> ports) {
    final ranked = List<_PortProbe>.from(ports);
    ranked.sort((a, b) {
      final priorityDelta = _probePriority(a.state) - _probePriority(b.state);
      if (priorityDelta != 0) {
        return priorityDelta;
      }
      final aMs = a.latencyMs ?? 1 << 30;
      final bMs = b.latencyMs ?? 1 << 30;
      return aMs.compareTo(bMs);
    });
    return ranked;
  }

  Future<_ServerHealth> _probeServerHealth(_ServerTarget target) async {
    final portsState = _rankPorts(await _probePorts(target));
    final hasHealthyPort = portsState.any((entry) => entry.isReachable);
    _PortProbe? bestAvailableProbe;
    for (final probe in portsState) {
      if (probe.canOpen) {
        bestAvailableProbe = probe;
        break;
      }
    }
    final stabilityScore = _recordAndScore(target, bestAvailableProbe != null);
    final checkedAt = DateTime.now();
    if (bestAvailableProbe == null) {
      return _ServerHealth.down(
        lastCheckedAt: checkedAt,
        portsState: portsState,
        stabilityScore: stabilityScore,
      );
    }
    final resolved = Uri.parse(
      target.baseUrl,
    ).replace(port: bestAvailableProbe.port);
    if (hasHealthyPort) {
      return _ServerHealth.up(
        lastCheckedAt: checkedAt,
        activePort: resolved.port,
        activeUrl: resolved,
        portsState: portsState,
        stabilityScore: stabilityScore,
      );
    }
    return _ServerHealth.degraded(
      lastCheckedAt: checkedAt,
      activePort: resolved.port,
      activeUrl: resolved,
      portsState: portsState,
      stabilityScore: stabilityScore,
    );
  }

  Future<Uri?> _resolveWorkingUrl(_ServerTarget target) async {
    final baseUri = Uri.parse(target.baseUrl);
    final probes = _rankPorts(await _probePorts(target));
    final savedPort = await _readLastSuccessfulPort(target);
    final orderedPorts = <int>[
      if (savedPort != null && target.fallbackPorts.contains(savedPort))
        savedPort,
      ...probes.map((p) => p.port).where((port) => port != savedPort),
    ];
    final candidates = <Uri>[
      for (final port in orderedPorts) baseUri.replace(port: port),
    ];
    for (var attempt = 0; attempt <= _autoRetries; attempt++) {
      for (final uri in candidates) {
        if (await _isReachable(uri)) {
          return uri;
        }
      }
    }
    return null;
  }

  Future<bool> _isReachable(Uri uri) async {
    final probe = await _probePortHealth(
      uri,
      connectTimeoutMs: _connectTimeoutMs,
      requestTimeoutMs: _requestTimeoutMs,
    );
    return probe.canOpen;
  }

  Future<void> _openServer(_ServerTarget target) async {
    final url = await _resolveWorkingUrl(target);
    if (!mounted) return;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('السيرفر غير متاح حاليًا على كل البورتات المحددة.'),
        ),
      );
      return;
    }
    await _saveLastSuccessfulPort(target, url.port);

    if (!mounted) return;
    if (kIsWeb && web_bridge.isElectron()) {
      await web_bridge.openUrlInNewTab(url.toString());
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ServerWebViewScreen(
          title: target.title,
          initialUrl: url,
          knownPortsByHost: _knownPortsByHost(),
          knownTitlesByHost: _knownTitlesByHost(),
        ),
      ),
    );
    if (mounted) {
      unawaited(_requestRefresh(showLoading: false));
    }
  }

  Future<void> _openServerWithPort(
    _ServerTarget target, {
    required int preferredPort,
  }) async {
    final base = Uri.parse(target.baseUrl);
    final preferred = base.replace(port: preferredPort);
    Uri? chosen;
    if (await _isReachable(preferred)) {
      chosen = preferred;
    } else {
      for (final port in target.fallbackPorts) {
        if (port == preferredPort) continue;
        final candidate = base.replace(port: port);
        if (await _isReachable(candidate)) {
          chosen = candidate;
          break;
        }
      }
    }
    if (!mounted) return;
    if (chosen == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('كل البورتات غير متاحة حاليًا لهذا السيرفر.'),
        ),
      );
      return;
    }
    await _saveLastSuccessfulPort(target, chosen.port);
    if (!mounted) return;
    if (kIsWeb && web_bridge.isElectron()) {
      await web_bridge.openUrlInNewTab(chosen.toString());
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ServerWebViewScreen(
          title: target.title,
          initialUrl: chosen!,
          knownPortsByHost: _knownPortsByHost(),
          knownTitlesByHost: _knownTitlesByHost(),
        ),
      ),
    );
    if (mounted) {
      unawaited(_requestRefresh(showLoading: false));
    }
  }

  Map<String, List<int>> _knownPortsByHost() {
    final map = <String, List<int>>{};
    for (final target in _targets) {
      map[Uri.parse(target.baseUrl).host] = List<int>.from(
        target.fallbackPorts,
      );
    }
    return map;
  }

  Map<String, String> _knownTitlesByHost() {
    final map = <String, String>{};
    for (final target in _targets) {
      map[Uri.parse(target.baseUrl).host] = target.title;
    }
    return map;
  }

  String _serverPrefsKey(_ServerTarget target) {
    final uri = Uri.parse(target.baseUrl);
    return '$_lastPortPrefsPrefix${uri.host}_${target.title}';
  }

  Future<void> _saveLastSuccessfulPort(_ServerTarget target, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_serverPrefsKey(target), port);
  }

  Future<int?> _readLastSuccessfulPort(_ServerTarget target) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_serverPrefsKey(target));
  }

  Future<void> _openRetrySettingsDialog() async {
    final connectController = TextEditingController(
      text: _connectTimeoutMs.toString(),
    );
    final requestController = TextEditingController(
      text: _requestTimeoutMs.toString(),
    );
    final retriesController = TextEditingController(
      text: _autoRetries.toString(),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعدادات إعادة المحاولة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: connectController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Connect timeout (ms)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: requestController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Request timeout (ms)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: retriesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Auto retries'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (result != true) return;
    final connect = int.tryParse(connectController.text.trim());
    final request = int.tryParse(requestController.text.trim());
    final retries = int.tryParse(retriesController.text.trim());
    if (connect == null || request == null || retries == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _serversConnectTimeoutPrefsKey,
      connect.clamp(800, 15000),
    );
    await prefs.setInt(
      _serversRequestTimeoutPrefsKey,
      request.clamp(1000, 20000),
    );
    await prefs.setInt(_serversAutoRetriesPrefsKey, retries.clamp(0, 8));
    if (!mounted) return;
    setState(() {
      _connectTimeoutMs = connect.clamp(800, 15000);
      _requestTimeoutMs = request.clamp(1000, 20000);
      _autoRetries = retries.clamp(0, 8);
    });
    unawaited(_requestRefresh());
  }

  Future<void> _exportServersSettings() async {
    final targetDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'اختر مجلد حفظ إعدادات السيرفرات',
    );
    if (targetDir == null || targetDir.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final lastPorts = <String, int>{};
    for (final target in _targets) {
      final value = prefs.getInt(_serverPrefsKey(target));
      if (value != null) {
        lastPorts[_serverPrefsKey(target)] = value;
      }
    }
    final payload = <String, dynamic>{
      'version': 1,
      'connectTimeoutMs': _connectTimeoutMs,
      'requestTimeoutMs': _requestTimeoutMs,
      'autoRetries': _autoRetries,
      'lastSuccessfulPorts': lastPorts,
      'exportedAt': DateTime.now().toIso8601String(),
    };
    final outPath = p.join(targetDir, 'servers_settings_export.json');
    await File(outPath).writeAsString(jsonEncode(payload));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('تم تصدير الإعدادات: $outPath')));
  }

  Future<void> _importServersSettings() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      allowMultiple: false,
      dialogTitle: 'اختر ملف إعدادات السيرفرات',
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    final content = await File(path).readAsString();
    final parsed = jsonDecode(content);
    if (parsed is! Map) return;
    final map = Map<String, dynamic>.from(parsed);
    final prefs = await SharedPreferences.getInstance();
    final connect = (map['connectTimeoutMs'] as num?)?.toInt();
    final request = (map['requestTimeoutMs'] as num?)?.toInt();
    final retries = (map['autoRetries'] as num?)?.toInt();
    if (connect != null) {
      await prefs.setInt(
        _serversConnectTimeoutPrefsKey,
        connect.clamp(800, 15000),
      );
    }
    if (request != null) {
      await prefs.setInt(
        _serversRequestTimeoutPrefsKey,
        request.clamp(1000, 20000),
      );
    }
    if (retries != null) {
      await prefs.setInt(_serversAutoRetriesPrefsKey, retries.clamp(0, 8));
    }
    final lastPorts = map['lastSuccessfulPorts'];
    if (lastPorts is Map) {
      for (final entry in lastPorts.entries) {
        final value = (entry.value as num?)?.toInt();
        if (value != null && entry.key is String) {
          await prefs.setInt(entry.key.toString(), value);
        }
      }
    }
    await _loadRetrySettings();
    if (!mounted) return;
    setState(() {});
    unawaited(_requestRefresh());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم استيراد إعدادات السيرفرات بنجاح.')),
    );
  }

  List<_ServerTarget> _visibleTargets() {
    if (_filter == _ServersFilter.all) return _targets;
    return _targets.where((target) {
      final idx = _targets.indexOf(target);
      final status = _health[idx].status;
      if (_filter == _ServersFilter.up) {
        return status == _ServerStatus.up || status == _ServerStatus.degraded;
      }
      return status == _ServerStatus.down;
    }).toList();
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _goToChat() => ref.read(activeSectionProvider.notifier).state = DesktopWorkspaceSection.chat;

  void _goToFiles() => ref.read(activeSectionProvider.notifier).state = DesktopWorkspaceSection.files;

  void _goToProfile() => ref.read(activeSectionProvider.notifier).state = DesktopWorkspaceSection.profile;

  void _goToAdminPanel() => ref.read(activeSectionProvider.notifier).state = DesktopWorkspaceSection.admin;

  void _goToTicketsPanel() => ref.read(activeSectionProvider.notifier).state = DesktopWorkspaceSection.tickets;

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(appSettingsRevisionProvider, (_, __) async {
      await _loadServerTargets();
      await _requestRefresh(showLoading: false);
    });
    final cs = Theme.of(context).colorScheme;
    final visible = _visibleTargets();
    final themeMode =
        ref.watch(themeModeControllerProvider).valueOrNull ?? ThemeMode.light;
    final user = ref.watch(authControllerProvider).valueOrNull;
    final canOpenAdmin = user?.canManageChat == true;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: Row(
                        children: [
                          const Expanded(
                            child: TabBar(
                              tabs: [
                                Tab(
                                  icon: Icon(Icons.dns_outlined),
                                  text: 'الحالة',
                                ),
                                Tab(
                                  icon: Icon(Icons.web_outlined),
                                  text: 'فتح سريع',
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'إعدادات متقدمة',
                            onSelected: (value) {
                              if (value == 'retry_settings') {
                                unawaited(_openRetrySettingsDialog());
                              } else if (value == 'export') {
                                unawaited(_exportServersSettings());
                              } else if (value == 'import') {
                                unawaited(_importServersSettings());
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'retry_settings',
                                child: Text('Retry Policy'),
                              ),
                              PopupMenuItem(
                                value: 'export',
                                child: Text('تصدير الإعدادات'),
                              ),
                              PopupMenuItem(
                                value: 'import',
                                child: Text('استيراد الإعدادات'),
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  16,
                                  8,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          ChoiceChip(
                                            label: const Text('الكل'),
                                            selected:
                                                _filter == _ServersFilter.all,
                                            onSelected: (_) => setState(
                                              () =>
                                                  _filter = _ServersFilter.all,
                                            ),
                                          ),
                                          ChoiceChip(
                                            label: const Text('المتاح'),
                                            selected:
                                                _filter == _ServersFilter.up,
                                            onSelected: (_) => setState(
                                              () => _filter = _ServersFilter.up,
                                            ),
                                          ),
                                          ChoiceChip(
                                            label: const Text('غير المتاح'),
                                            selected:
                                                _filter == _ServersFilter.down,
                                            onSelected: (_) => setState(
                                              () =>
                                                  _filter = _ServersFilter.down,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        if (_lastRefreshAt != null)
                                          Text(
                                            'آخر فحص: ${_formatTime(_lastRefreshAt!)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: cs.onSurfaceVariant,
                                                ),
                                          ),
                                        const SizedBox(height: 6),
                                        FilledButton.tonalIcon(
                                          onPressed: _loading
                                              ? null
                                              : () => unawaited(
                                                  _requestRefresh(),
                                                ),
                                          icon: _loading
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.refresh_rounded,
                                                ),
                                          label: Text(
                                            _loading
                                                ? 'جاري الفحص'
                                                : 'تحديث الحالة',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    16,
                                  ),
                                  itemCount: visible.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final target = visible[index];
                                    final sourceIndex = _targets.indexOf(
                                      target,
                                    );
                                    final health = _health[sourceIndex];
                                    final statusColor = switch (health.status) {
                                      _ServerStatus.degraded => const Color(
                                        0xFFD97706,
                                      ),
                                      _ServerStatus.up => const Color(
                                        0xFF16A34A,
                                      ),
                                      _ServerStatus.down => cs.error,
                                      _ServerStatus.unknown => cs.outline,
                                    };
                                    final statusText = switch (health.status) {
                                      _ServerStatus.degraded => 'تحذير',
                                      _ServerStatus.up => 'متصل',
                                      _ServerStatus.down => 'غير متاح',
                                      _ServerStatus.unknown => 'جارٍ الفحص...',
                                    };
                                    final isDark =
                                        Theme.of(context).brightness ==
                                        Brightness.dark;
                                    final cardBgColor = isDark
                                        ? cs.surface.withValues(alpha: 0.65)
                                        : Colors.white;
                                    final cardBorderColor = isDark
                                        ? cs.outlineVariant.withValues(
                                            alpha: 0.35,
                                          )
                                        : cs.outlineVariant.withValues(
                                            alpha: 0.55,
                                          );

                                    return Container(
                                      decoration: BoxDecoration(
                                        color: cardBgColor,
                                        borderRadius: BorderRadius.circular(22),
                                        border: Border.all(
                                          color: cardBorderColor,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: isDark ? 0.12 : 0.04,
                                            ),
                                            blurRadius: 16,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(22),
                                        child: InkWell(
                                          onTap: () => _openServer(target),
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 18,
                                              vertical: 16,
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 12,
                                                  height: 12,
                                                  decoration: BoxDecoration(
                                                    color: statusColor,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 14),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        target.title,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .titleMedium
                                                            ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                            ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        target.baseUrl,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color: cs
                                                                  .onSurfaceVariant,
                                                            ),
                                                      ),
                                                      if (health.activePort !=
                                                          null)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 6,
                                                              ),
                                                          child: Text(
                                                            'أفضل بورت: ${health.activePort} - الاستقرار ${health.stabilityScore.toStringAsFixed(0)}%',
                                                            style: Theme.of(context)
                                                                .textTheme
                                                                .labelSmall
                                                                ?.copyWith(
                                                                  color:
                                                                      statusColor,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                          ),
                                                        ),
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                      Wrap(
                                                        spacing: 8,
                                                        runSpacing: 8,
                                                        children: [
                                                          for (final probe
                                                              in health
                                                                  .portsState)
                                                            GestureDetector(
                                                              onTap: () =>
                                                                  _openServerWithPort(
                                                                    target,
                                                                    preferredPort:
                                                                        probe
                                                                            .port,
                                                                  ),
                                                              child: Container(
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          12,
                                                                      vertical:
                                                                          6,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color:
                                                                      probe
                                                                          .isReachable
                                                                      ? const Color(
                                                                          0xFF16A34A,
                                                                        ).withValues(
                                                                          alpha:
                                                                              0.12,
                                                                        )
                                                                      : cs.error.withValues(
                                                                          alpha:
                                                                              0.1,
                                                                        ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        12,
                                                                      ),
                                                                  border: Border.all(
                                                                    color:
                                                                        probe
                                                                            .isReachable
                                                                        ? const Color(
                                                                            0xFF16A34A,
                                                                          ).withValues(
                                                                            alpha:
                                                                                0.3,
                                                                          )
                                                                        : cs.error.withValues(
                                                                            alpha:
                                                                                0.25,
                                                                          ),
                                                                  ),
                                                                ),
                                                                child: Text(
                                                                  ':${probe.port} ${probe.isReachable ? 'متاح' : 'غير متاح'}${probe.latencyMs != null ? ' - ${probe.latencyMs}ms' : ''}',
                                                                  style: Theme.of(context)
                                                                      .textTheme
                                                                      .labelSmall
                                                                      ?.copyWith(
                                                                        color:
                                                                            probe.isReachable
                                                                            ? const Color(
                                                                                0xFF16A34A,
                                                                              )
                                                                            : cs.error,
                                                                        fontWeight:
                                                                            FontWeight.w700,
                                                                      ),
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 14),
                                                Text(
                                                  statusText,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelLarge
                                                      ?.copyWith(
                                                        color: statusColor,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                                const SizedBox(width: 8),
                                                const Icon(
                                                  Icons.open_in_new_rounded,
                                                  size: 20,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                DropdownButtonFormField<_ServerTarget>(
                                  value: _selected,
                                  decoration: const InputDecoration(
                                    labelText: 'اختر سيرفر للفتح السريع',
                                  ),
                                  items: _targets
                                      .map(
                                        (s) => DropdownMenuItem<_ServerTarget>(
                                          value: s,
                                          child: Text(s.title),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) => setState(() {
                                    _selected = value;
                                    _selectedPort = null;
                                  }),
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<int>(
                                  value: _selectedPort,
                                  decoration: const InputDecoration(
                                    labelText: 'اختيار البورت (اختياري)',
                                    hintText: 'Auto إذا تركتها فارغة',
                                  ),
                                  items: (_selected?.fallbackPorts ?? const <int>[])
                                      .map((port) {
                                        final index = _selected == null
                                            ? -1
                                            : _targets.indexOf(_selected!);
                                        _PortProbe? probe;
                                        if (index >= 0) {
                                          for (final entry
                                              in _health[index].portsState) {
                                            if (entry.port == port) {
                                              probe = entry;
                                              break;
                                            }
                                          }
                                        }
                                        final status = probe == null
                                            ? 'غير مفحوص'
                                            : (probe.isReachable
                                                  ? 'متاح${probe.latencyMs != null ? ' (${probe.latencyMs}ms)' : ''}'
                                                  : 'غير متاح');
                                        return DropdownMenuItem<int>(
                                          value: port,
                                          child: Text('Port $port - $status'),
                                        );
                                      })
                                      .toList(),
                                  onChanged: _selected == null
                                      ? null
                                      : (value) => setState(
                                          () => _selectedPort = value,
                                        ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: _selected == null
                                            ? null
                                            : () {
                                                if (_selectedPort == null) {
                                                  _openServer(_selected!);
                                                } else {
                                                  _openServerWithPort(
                                                    _selected!,
                                                    preferredPort:
                                                        _selectedPort!,
                                                  );
                                                }
                                              },
                                        icon: const Icon(
                                          Icons.open_in_browser_outlined,
                                        ),
                                        label: const Text('فتح داخل التطبيق'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!widget.isWrapped)
                DesktopWorkspaceSidebar(
                  user: user,
                  activeSection: DesktopWorkspaceSection.servers,
                  currentThemeMode: themeMode,
                  isDark: themeMode == ThemeMode.dark,
                  accentColor: Theme.of(context).colorScheme.primary,
                  onOpenChat: _goToChat,
                  onRefresh: _loading
                      ? () {}
                      : () => unawaited(_requestRefresh()),
                  onOpenFiles: _goToFiles,
                  onOpenServers: () {},
                  onOpenProfile: _goToProfile,
                  onOpenUpdates: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const UpdateCenterScreen(),
                    ),
                  ),
                  onToggleTheme: () => ref
                      .read(themeModeControllerProvider.notifier)
                      .cycleThemeMode(),
                  onOpenTickets: _goToTicketsPanel,
                  onLogout: () =>
                      ref.read(authControllerProvider.notifier).logout(),
                  onCreateConversation: _goToChat,
                  onOpenAdmin: canOpenAdmin ? _goToAdminPanel : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ServerStatus { unknown, up, degraded, down }

enum _ServersFilter { all, up, down }

class _ServerTarget {
  const _ServerTarget({
    required this.title,
    required this.baseUrl,
    required this.fallbackPorts,
  });

  final String title;
  final String baseUrl;
  final List<int> fallbackPorts;
}

class _ServerHealth {
  const _ServerHealth({
    required this.status,
    required this.lastCheckedAt,
    this.activePort,
    this.activeUrl,
    required this.portsState,
    required this.stabilityScore,
  });

  factory _ServerHealth.unknown() => _ServerHealth(
    status: _ServerStatus.unknown,
    lastCheckedAt: DateTime.now(),
    portsState: const [],
    stabilityScore: 0,
  );

  factory _ServerHealth.up({
    required DateTime lastCheckedAt,
    required int activePort,
    required Uri activeUrl,
    required List<_PortProbe> portsState,
    required double stabilityScore,
  }) => _ServerHealth(
    status: _ServerStatus.up,
    lastCheckedAt: lastCheckedAt,
    activePort: activePort,
    activeUrl: activeUrl,
    portsState: portsState,
    stabilityScore: stabilityScore,
  );

  factory _ServerHealth.degraded({
    required DateTime lastCheckedAt,
    required int activePort,
    required Uri activeUrl,
    required List<_PortProbe> portsState,
    required double stabilityScore,
  }) => _ServerHealth(
    status: _ServerStatus.degraded,
    lastCheckedAt: lastCheckedAt,
    activePort: activePort,
    activeUrl: activeUrl,
    portsState: portsState,
    stabilityScore: stabilityScore,
  );

  factory _ServerHealth.down({
    required DateTime lastCheckedAt,
    required List<_PortProbe> portsState,
    required double stabilityScore,
  }) => _ServerHealth(
    status: _ServerStatus.down,
    lastCheckedAt: lastCheckedAt,
    portsState: portsState,
    stabilityScore: stabilityScore,
  );

  final _ServerStatus status;
  final DateTime lastCheckedAt;
  final int? activePort;
  final Uri? activeUrl;
  final List<_PortProbe> portsState;
  final double stabilityScore;
}

class _PortProbe {
  const _PortProbe({
    required this.port,
    required this.state,
    required this.summary,
    this.detail,
    this.latencyMs,
    this.httpStatusCode,
  });

  final int port;
  final _PortProbeState state;
  final String summary;
  final String? detail;
  final int? latencyMs;
  final int? httpStatusCode;

  bool get isReachable => state != _PortProbeState.down;

  bool get canOpen => state != _PortProbeState.down;
}

enum _PortProbeState { healthy, degraded, down }

Future<_PortProbe> _probePortHealth(
  Uri uri, {
  required int connectTimeoutMs,
  required int requestTimeoutMs,
}) async {
  final watch = Stopwatch()..start();
  Socket? tcpSocket;
  try {
    int tcpLatencyMs = 0;
    if (!kIsWeb) {
      tcpSocket = await Socket.connect(
        uri.host,
        uri.port,
        timeout: Duration(milliseconds: connectTimeoutMs),
      );
      tcpLatencyMs = watch.elapsedMilliseconds;
      tcpSocket.destroy();
    }
    final httpResult = await _probeHttpReachability(
      uri,
      requestTimeoutMs: requestTimeoutMs,
    );
    watch.stop();
    final isHealthy =
        httpResult.statusCode != null &&
        httpResult.statusCode! >= 200 &&
        httpResult.statusCode! < 500;
    return _PortProbe(
      port: uri.port,
      state: isHealthy ? _PortProbeState.healthy : _PortProbeState.degraded,
      summary: httpResult.summary,
      detail: httpResult.detail,
      latencyMs: isHealthy ? watch.elapsedMilliseconds : tcpLatencyMs,
      httpStatusCode: httpResult.statusCode,
    );
  } on TimeoutException {
    watch.stop();
    return _PortProbe(
      port: uri.port,
      state: _PortProbeState.down,
      summary: 'TCP timeout',
      detail: 'انتهت مهلة فتح اتصال TCP مع هذا البورت.',
    );
  } on SocketException catch (error) {
    watch.stop();
    return _PortProbe(
      port: uri.port,
      state: _PortProbeState.down,
      summary: 'TCP مغلق',
      detail: _formatProbeError(error),
    );
  } catch (error) {
    watch.stop();
    return _PortProbe(
      port: uri.port,
      state: _PortProbeState.down,
      summary: 'فشل الفحص',
      detail: _formatProbeError(error),
    );
  } finally {
    if (!kIsWeb) {
      tcpSocket?.destroy();
    }
  }
}

Future<({int? statusCode, String summary, String detail})>
_probeHttpReachability(Uri uri, {required int requestTimeoutMs}) async {
  final headResult = await _sendProbeRequest(
    uri,
    method: 'HEAD',
    requestTimeoutMs: requestTimeoutMs,
  );
  if (headResult.statusCode == 405 || headResult.statusCode == 501) {
    return _sendProbeRequest(
      uri,
      method: 'GET',
      requestTimeoutMs: requestTimeoutMs,
    );
  }
  return headResult;
}

Future<({int? statusCode, String summary, String detail})> _sendProbeRequest(
  Uri uri, {
  required String method,
  required int requestTimeoutMs,
}) async {
  if (kIsWeb) {
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: Duration(milliseconds: requestTimeoutMs),
          receiveTimeout: Duration(milliseconds: requestTimeoutMs),
          validateStatus: (_) => true,
        ),
      );
      final response = await dio.requestUri<dynamic>(
        uri,
        options: Options(method: method, followRedirects: false),
      );
      final statusCode = response.statusCode ?? 0;
      final detail = switch (statusCode) {
        200 => 'الخدمة ردّت بشكل طبيعي.',
        301 || 302 || 303 || 307 || 308 => 'الخدمة تعمل وتعيد تحويل الطلب.',
        401 || 403 => 'الخدمة تعمل لكنها تطلب صلاحية أو تسجيل دخول.',
        404 => 'البورت يرد لكن المسار المطلوب غير موجود.',
        405 || 501 => 'الخدمة لا تدعم $method لهذا المسار.',
        _ when statusCode >= 500 =>
          'الخدمة على البورت تعمل لكن التطبيق يرجع خطأ داخليًا.',
        _ => 'البورت يرد على HTTP برمز $statusCode.',
      };
      return (
        statusCode: statusCode,
        summary: 'HTTP $statusCode',
        detail: detail,
      );
    } catch (error) {
      return (
        statusCode: null,
        summary: 'HTTP failed',
        detail: 'فشل فحص HTTP (قد يكون مغلق أو ممنوع من المتصفح)',
      );
    }
  }

  final client = HttpClient()
    ..connectionTimeout = Duration(milliseconds: requestTimeoutMs);
  try {
    final request = await client
        .openUrl(method, uri)
        .timeout(Duration(milliseconds: requestTimeoutMs));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.connectionHeader, 'close');
    final response = await request.close().timeout(
      Duration(milliseconds: requestTimeoutMs),
    );
    final sub = response.listen((_) {});
    await sub.cancel();
    final statusCode = response.statusCode;
    final detail = switch (statusCode) {
      200 => 'الخدمة ردّت بشكل طبيعي.',
      301 || 302 || 303 || 307 || 308 => 'الخدمة تعمل وتعيد تحويل الطلب.',
      401 || 403 => 'الخدمة تعمل لكنها تطلب صلاحية أو تسجيل دخول.',
      404 => 'البورت يرد لكن المسار المطلوب غير موجود.',
      405 || 501 => 'الخدمة لا تدعم $method لهذا المسار.',
      _ when statusCode >= 500 =>
        'الخدمة على البورت تعمل لكن التطبيق يرجع خطأ داخليًا.',
      _ => 'البورت يرد على HTTP برمز $statusCode.',
    };
    return (
      statusCode: statusCode,
      summary: 'HTTP $statusCode',
      detail: detail,
    );
  } on TimeoutException {
    return (
      statusCode: null,
      summary: 'HTTP timeout',
      detail: 'تم فتح TCP لكن WebLogic لم يكمل استجابة HTTP في الوقت المحدد.',
    );
  } on HttpException catch (error) {
    return (
      statusCode: null,
      summary: 'HTTP error',
      detail: _formatProbeError(error),
    );
  } on SocketException catch (error) {
    return (
      statusCode: null,
      summary: 'HTTP reset',
      detail: _formatProbeError(error),
    );
  } catch (error) {
    return (
      statusCode: null,
      summary: 'HTTP failed',
      detail: _formatProbeError(error),
    );
  } finally {
    client.close(force: true);
  }
}

int _probePriority(_PortProbeState state) {
  return switch (state) {
    _PortProbeState.healthy => 0,
    _PortProbeState.degraded => 1,
    _PortProbeState.down => 2,
  };
}

String _formatProbeError(Object error) {
  if (error is SocketException) {
    final message = error.osError?.message.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return error.message;
  }
  if (error is TimeoutException) {
    return 'انتهت المهلة قبل اكتمال الفحص.';
  }
  if (error is HttpException) {
    return error.message;
  }
  final raw = error.toString().trim();
  return raw.isEmpty ? 'تعذر إكمال الفحص لهذا البورت.' : raw;
}

class _ServerWebViewScreen extends StatefulWidget {
  const _ServerWebViewScreen({
    required this.title,
    required this.initialUrl,
    required this.knownPortsByHost,
    required this.knownTitlesByHost,
  });

  final String title;
  final Uri initialUrl;
  final Map<String, List<int>> knownPortsByHost;
  final Map<String, String> knownTitlesByHost;

  @override
  State<_ServerWebViewScreen> createState() => _ServerWebViewScreenState();
}

class _ServerWebViewScreenState extends State<_ServerWebViewScreen> {
  static const String _browserTabsPrefsKey = 'servers_browser_tabs_v1';
  static const String _browserActiveTabPrefsKey =
      'servers_browser_active_tab_v1';
  static const String _browserBookmarksPrefsKey =
      'servers_browser_bookmarks_v1';
  static const String _browserHistoryPrefsKey = 'servers_browser_history_v1';
  static const String _browserCredentialsPrefsKey =
      'servers_browser_credentials_v1';
  static const String _browserBestPortPrefsPrefix =
      'servers_browser_best_port_';
  static const String _browserHomeUrlPrefsKey = 'servers_browser_home_url_v1';
  static const String _browserSearchEnginePrefsKey =
      'servers_browser_search_engine_v1';
  static const String _browserPermissionsPrefsKey =
      'servers_browser_permissions_v1';
  static const String _browserIntranetOnlyPrefsKey =
      'servers_browser_intranet_only_v1';
  final WebviewController _controller = WebviewController();
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();
  final List<_BrowserTab> _tabs = <_BrowserTab>[];
  final List<_BrowserTab> _closedTabs = <_BrowserTab>[];
  bool _controllerInitialized = false;
  bool _loading = true;
  String? _error;
  bool _isNavigating = false;
  bool _triedFailoverForCurrentLoad = false;
  String _currentUrlText = '';
  bool _didPromptFailover = false;
  int _activeTabIndex = 0;

  /// Index of the tab whose document is currently loaded in the single WebView
  /// (may differ from [_activeTabIndex] while a dashboard tab is on top).
  int _webviewContentTabIndex = 0;
  String? _downloadDir;
  List<FileSystemEntity> _downloadedFiles = const <FileSystemEntity>[];
  final List<_DownloadJob> _downloadQueue = <_DownloadJob>[];
  bool _isProcessingDownloads = false;
  final List<_BookmarkItem> _bookmarks = <_BookmarkItem>[];
  final List<_HistoryItem> _history = <_HistoryItem>[];
  final List<_SavedCredential> _credentials = <_SavedCredential>[];
  final List<_SitePermission> _sitePermissions = <_SitePermission>[];
  final Set<String> _credentialPromptedHosts = <String>{};
  List<String> _urlSuggestions = const <String>[];
  bool _showUrlSuggestions = false;
  String _homeUrl = '';
  String _searchEngineTemplate = 'https://www.google.com/search?q={query}';
  bool _intranetOnlyMode = true;
  final Map<String, _DashboardServerState> _dashboardStatusByHost =
      <String, _DashboardServerState>{};

  @override
  void initState() {
    super.initState();
    _urlFocusNode.addListener(() {
      if (!_urlFocusNode.hasFocus && mounted && _showUrlSuggestions) {
        setState(() => _showUrlSuggestions = false);
      }
    });
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _initializeWebViewEnvironment();
      await _restoreSessionTabs();
      await _loadDownloadSettings();
      await _loadBookmarks();
      await _loadHistory();
      await _loadCredentials();
      await _loadBrowserSettings();
      await _loadSitePermissions();
      if (_tabs.isEmpty) {
        _tabs.add(
          _BrowserTab(title: 'تبويب 1', url: widget.initialUrl.toString()),
        );
      }
      _syncWebviewContentTabIndexFromState();
      await _controller.initialize();
      _controllerInitialized = true;
      await _controller.setBackgroundColor(Colors.transparent);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      _controller.url.listen((url) {
        if (!mounted) return;
        _currentUrlText = url;
        if (_tabs.isNotEmpty &&
            _activeTabIndex < _tabs.length &&
            !_tabs[_activeTabIndex].isDashboard) {
          _urlController.text = url;
        }
        final syncIdx = _tabIndexReceivingWebViewEvents();
        if (syncIdx != null) {
          _tabs[syncIdx] = _tabs[syncIdx].copyWith(url: url);
          unawaited(_persistSessionTabs());
        }
        _recordHistory(url);
        unawaited(_maybeAutofillForUrl(url));
        _maybeSuggestCredentialSave(url);
        setState(() {});
      });
      _controller.title.listen((title) {
        if (!mounted) return;
        final syncIdx = _tabIndexReceivingWebViewEvents();
        if (syncIdx != null) {
          final safeTitle = _compactTabTitle(
            title.trim().isEmpty ? _tabs[syncIdx].title : title.trim(),
          );
          _tabs[syncIdx] = _tabs[syncIdx].copyWith(title: safeTitle);
          unawaited(_persistSessionTabs());
          setState(() {});
        }
      });
      _controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() {
          _loading = state == LoadingState.loading;
          if (state == LoadingState.loading) {
            _triedFailoverForCurrentLoad = false;
            _didPromptFailover = false;
          } else if (state == LoadingState.navigationCompleted) {
            final current = _currentUrlText;
            if (current.trim().isNotEmpty) {
              unawaited(_maybeAutofillForUrl(current));
              unawaited(_applySitePermissionsForUrl(current));
            }
          }
        });
      });
      _controller.onLoadError.listen((_) {
        if (!mounted) return;
        unawaited(_handleLoadErrorAndFailover());
      });
      await _navigateWithAutoPort(widget.initialUrl);
      unawaited(_refreshDashboardServers());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _refreshDashboardServers() async {
    final next = <String, _DashboardServerState>{};
    for (final entry in widget.knownPortsByHost.entries) {
      final host = entry.key;
      final ports = entry.value;
      Uri? bestUri;
      int? bestLatency;
      for (final port in ports) {
        final uri = Uri.parse('http://$host:$port/');
        final probe = await _probePortHealth(
          uri,
          connectTimeoutMs: 3000,
          requestTimeoutMs: 4000,
        );
        if (!probe.canOpen) continue;
        final ms = probe.latencyMs ?? (1 << 30);
        if (bestUri == null || ms < (bestLatency ?? (1 << 30))) {
          bestUri = uri;
          bestLatency = ms;
        }
      }
      next[host] = _DashboardServerState(
        isUp: bestUri != null,
        bestUri: bestUri,
        latencyMs: bestLatency,
      );
    }
    if (!mounted) return;
    setState(() {
      _dashboardStatusByHost
        ..clear()
        ..addAll(next);
    });
  }

  String _compactTabTitle(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 'تبويب';
    final parsed = Uri.tryParse(value);
    String candidate = value;
    if (parsed != null && parsed.host.trim().isNotEmpty) {
      candidate = parsed.host.trim();
    }
    if (candidate.length > 36) {
      return '${candidate.substring(0, 33)}...';
    }
    return candidate;
  }

  void _syncWebviewContentTabIndexFromState() {
    if (_tabs.isEmpty) return;
    if (_activeTabIndex < _tabs.length && !_tabs[_activeTabIndex].isDashboard) {
      _webviewContentTabIndex = _activeTabIndex;
      return;
    }
    final i = _tabs.indexWhere((t) => !t.isDashboard);
    _webviewContentTabIndex = i >= 0 ? i : 0;
    if (_webviewContentTabIndex >= _tabs.length) {
      _webviewContentTabIndex = _tabs.length - 1;
    }
  }

  /// Tab that should receive URL/title updates from the single shared WebView.
  int? _tabIndexReceivingWebViewEvents() {
    if (_tabs.isEmpty || _activeTabIndex >= _tabs.length) return null;
    if (!_tabs[_activeTabIndex].isDashboard) {
      return _activeTabIndex;
    }
    final c = _webviewContentTabIndex;
    if (c >= 0 && c < _tabs.length && !_tabs[c].isDashboard) {
      return c;
    }
    return null;
  }

  void _ensureActiveTabOwnsWebView() {
    if (_tabs.isEmpty || _activeTabIndex >= _tabs.length) return;
    if (_tabs[_activeTabIndex].isDashboard) {
      setState(() {
        _tabs[_activeTabIndex] = _tabs[_activeTabIndex].copyWith(
          isDashboard: false,
        );
      });
    }
    _webviewContentTabIndex = _activeTabIndex;
  }

  int _effectivePortForCompare(Uri u) {
    if (u.hasPort) return u.port;
    if (u.scheme == 'https') return 443;
    if (u.scheme == 'http') return 80;
    return 0;
  }

  String _normalizePathForUrlCompare(String path) {
    if (path.isEmpty) return '/';
    if (path.length > 1 && path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  bool _urlsMatchForSameDocument(String a, String b) {
    final ua = Uri.tryParse(a.trim());
    final ub = Uri.tryParse(b.trim());
    if (ua == null || ub == null) {
      return a.trim() == b.trim();
    }
    return ua.scheme.toLowerCase() == ub.scheme.toLowerCase() &&
        ua.host.toLowerCase() == ub.host.toLowerCase() &&
        _effectivePortForCompare(ua) == _effectivePortForCompare(ub) &&
        _normalizePathForUrlCompare(ua.path) ==
            _normalizePathForUrlCompare(ub.path) &&
        ua.query == ub.query;
  }

  Future<void> _initializeWebViewEnvironment() async {
    if (_webViewEnvironmentReady) return;
    try {
      final supportDir = await getApplicationSupportDirectory();
      final webViewDataDir = Directory(
        p.join(supportDir.path, 'embedded_browser_profile'),
      );
      if (!await webViewDataDir.exists()) {
        await webViewDataDir.create(recursive: true);
      }
      await WebviewController.initializeEnvironment(
        userDataPath: webViewDataDir.path,
      );
      _webViewEnvironmentReady = true;
    } catch (_) {
      // Ignore re-initialization or environment errors and continue.
      _webViewEnvironmentReady = true;
    }
  }

  Future<void> _loadDownloadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('browser_download_dir');
    if (saved != null && saved.trim().isNotEmpty) {
      _downloadDir = saved.trim();
    } else {
      final downloads = await getDownloadsDirectory();
      _downloadDir = downloads?.path;
    }
    await _refreshDownloadedFiles();
  }

  Future<void> _loadBrowserSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedHome = prefs.getString(_browserHomeUrlPrefsKey)?.trim();
    final savedSearch = prefs.getString(_browserSearchEnginePrefsKey)?.trim();
    final savedIntranetOnly = prefs.getBool(_browserIntranetOnlyPrefsKey);
    _homeUrl = (savedHome == null || savedHome.isEmpty)
        ? widget.initialUrl.toString()
        : savedHome;
    _searchEngineTemplate = (savedSearch == null || savedSearch.isEmpty)
        ? 'https://www.google.com/search?q={query}'
        : savedSearch;
    _intranetOnlyMode = savedIntranetOnly ?? true;
  }

  Future<void> _persistBrowserSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_browserHomeUrlPrefsKey, _homeUrl);
    await prefs.setString(_browserSearchEnginePrefsKey, _searchEngineTemplate);
    await prefs.setBool(_browserIntranetOnlyPrefsKey, _intranetOnlyMode);
  }

  Future<void> _loadSitePermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_browserPermissionsPrefsKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _sitePermissions
          ..clear()
          ..addAll(
            decoded
                .whereType<Map>()
                .map((item) {
                  final map = Map<String, dynamic>.from(item);
                  return _SitePermission(
                    host: map['host']?.toString() ?? '',
                    notifications: map['notifications']?.toString() ?? 'ask',
                    cookies: map['cookies']?.toString() ?? 'allow',
                    popups: map['popups']?.toString() ?? 'block',
                  );
                })
                .where((entry) => entry.host.trim().isNotEmpty),
          );
      }
    } catch (_) {}
  }

  Future<void> _persistSitePermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _sitePermissions
          .map(
            (entry) => <String, dynamic>{
              'host': entry.host,
              'notifications': entry.notifications,
              'cookies': entry.cookies,
              'popups': entry.popups,
            },
          )
          .toList(),
    );
    await prefs.setString(_browserPermissionsPrefsKey, encoded);
  }

  _SitePermission _permissionForHost(String host) {
    final found = _sitePermissions
        .where((entry) => entry.host == host)
        .toList();
    if (found.isNotEmpty) return found.first;
    return _SitePermission(
      host: host,
      notifications: 'ask',
      cookies: 'allow',
      popups: 'block',
    );
  }

  Future<void> _setPermissionForHost(_SitePermission next) async {
    setState(() {
      _sitePermissions.removeWhere((entry) => entry.host == next.host);
      _sitePermissions.insert(0, next);
    });
    await _persistSitePermissions();
  }

  Future<void> _restoreSessionTabs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_browserTabsPrefsKey);
    final active = prefs.getInt(_browserActiveTabPrefsKey) ?? 0;
    if (raw == null || raw.trim().isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _tabs.clear();
        for (final item in decoded) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            final title = map['title']?.toString().trim() ?? 'تبويب';
            final url = map['url']?.toString().trim() ?? '';
            final pinned = map['pinned'] == true;
            final isDashboard = map['isDashboard'] == true;
            if (url.isNotEmpty || isDashboard) {
              _tabs.add(
                _BrowserTab(
                  title: title,
                  url: url,
                  pinned: pinned,
                  isDashboard: isDashboard,
                ),
              );
            }
          }
        }
        if (_tabs.isNotEmpty) {
          _activeTabIndex = active.clamp(0, _tabs.length - 1);
        }
      }
    } catch (_) {}
  }

  Future<void> _persistSessionTabs() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _tabs
          .map(
            (tab) => <String, dynamic>{
              'title': tab.title,
              'url': tab.url,
              'pinned': tab.pinned,
              'isDashboard': tab.isDashboard,
            },
          )
          .toList(),
    );
    await prefs.setString(_browserTabsPrefsKey, encoded);
    await prefs.setInt(_browserActiveTabPrefsKey, _activeTabIndex);
  }

  Future<void> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_browserBookmarksPrefsKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _bookmarks.clear();
        for (final item in decoded) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            final title = map['title']?.toString().trim() ?? '';
            final url = map['url']?.toString().trim() ?? '';
            if (url.isNotEmpty) {
              _bookmarks.add(
                _BookmarkItem(title: title.isEmpty ? url : title, url: url),
              );
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_browserCredentialsPrefsKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _credentials
          ..clear()
          ..addAll(
            decoded
                .whereType<Map>()
                .map((item) {
                  final map = Map<String, dynamic>.from(item);
                  return _SavedCredential(
                    host: map['host']?.toString() ?? '',
                    username: map['username']?.toString() ?? '',
                    password: map['password']?.toString() ?? '',
                    updatedAt:
                        DateTime.tryParse(map['updatedAt']?.toString() ?? '') ??
                        DateTime.now(),
                  );
                })
                .where(
                  (entry) => entry.host.isNotEmpty && entry.username.isNotEmpty,
                ),
          );
      }
    } catch (_) {}
  }

  Future<void> _persistCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _credentials
          .map(
            (entry) => <String, dynamic>{
              'host': entry.host,
              'username': entry.username,
              'password': entry.password,
              'updatedAt': entry.updatedAt.toIso8601String(),
            },
          )
          .toList(),
    );
    await prefs.setString(_browserCredentialsPrefsKey, encoded);
  }

  Future<void> _persistBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _bookmarks
          .map(
            (entry) => <String, dynamic>{
              'title': entry.title,
              'url': entry.url,
            },
          )
          .toList(),
    );
    await prefs.setString(_browserBookmarksPrefsKey, encoded);
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_browserHistoryPrefsKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _history.clear();
        for (final item in decoded) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            final url = map['url']?.toString().trim() ?? '';
            final title = map['title']?.toString().trim() ?? url;
            final ts = map['ts']?.toString().trim() ?? '';
            final at = DateTime.tryParse(ts);
            if (url.isNotEmpty && at != null) {
              _history.add(_HistoryItem(url: url, title: title, at: at));
            }
          }
        }
        _pruneHistory();
      }
    } catch (_) {}
  }

  Future<void> _persistHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _history
          .map(
            (entry) => <String, dynamic>{
              'url': entry.url,
              'title': entry.title,
              'ts': entry.at.toIso8601String(),
            },
          )
          .toList(),
    );
    await prefs.setString(_browserHistoryPrefsKey, encoded);
  }

  void _recordHistory(String url) {
    if (url.trim().isEmpty) return;
    final title = (_tabs.isNotEmpty && _activeTabIndex < _tabs.length)
        ? _tabs[_activeTabIndex].title
        : url;
    _history.removeWhere((entry) => entry.url == url);
    _history.insert(
      0,
      _HistoryItem(url: url, title: title, at: DateTime.now()),
    );
    _pruneHistory();
    unawaited(_persistHistory());
  }

  void _pruneHistory() {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    _history.removeWhere((entry) => entry.at.isBefore(cutoff));
    if (_history.length > 300) {
      _history.removeRange(300, _history.length);
    }
  }

  Future<void> _openHistorySheet() async {
    final searchController = TextEditingController();
    List<_HistoryItem> visible = List<_HistoryItem>.from(_history);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchController,
                            onChanged: (value) {
                              final q = value.trim().toLowerCase();
                              setModalState(() {
                                visible = q.isEmpty
                                    ? List<_HistoryItem>.from(_history)
                                    : _history
                                          .where(
                                            (entry) =>
                                                entry.url
                                                    .toLowerCase()
                                                    .contains(q) ||
                                                entry.title
                                                    .toLowerCase()
                                                    .contains(q),
                                          )
                                          .toList();
                              });
                            },
                            decoration: const InputDecoration(
                              hintText: 'ابحث في السجل...',
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'مسح السجل',
                          onPressed: () {
                            setState(() => _history.clear());
                            unawaited(_persistHistory());
                            setModalState(
                              () => visible = const <_HistoryItem>[],
                            );
                          },
                          icon: const Icon(Icons.delete_sweep_outlined),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'السجل محفوظ حتى 120 زيارة حديثة',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final item = visible[index];
                        return ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            item.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            _ensureActiveTabOwnsWebView();
                            final uri = Uri.tryParse(item.url);
                            if (uri != null) {
                              unawaited(_navigateWithAutoPort(uri));
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _addCurrentBookmark() {
    final uri = _currentUri();
    if (uri == null) return;
    final title = (_tabs.isNotEmpty && _activeTabIndex < _tabs.length)
        ? _tabs[_activeTabIndex].title
        : uri.toString();
    setState(() {
      _bookmarks.insert(0, _BookmarkItem(title: title, url: uri.toString()));
    });
    unawaited(_persistBookmarks());
  }

  bool _isCurrentBookmarked() {
    final uri = _currentUri();
    if (uri == null) return false;
    return _bookmarks.any((entry) => entry.url == uri.toString());
  }

  void _toggleCurrentBookmark() {
    final uri = _currentUri();
    if (uri == null) return;
    final existingIndex = _bookmarks.indexWhere(
      (entry) => entry.url == uri.toString(),
    );
    if (existingIndex >= 0) {
      setState(() => _bookmarks.removeAt(existingIndex));
      unawaited(_persistBookmarks());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إزالة الصفحة من المفضلة')),
      );
      return;
    }
    _addCurrentBookmark();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تمت إضافة الصفحة إلى المفضلة')),
    );
  }

  void _duplicateCurrentTab() {
    if (_tabs.isEmpty || _activeTabIndex >= _tabs.length) return;
    final current = _tabs[_activeTabIndex];
    setState(() {
      _tabs.insert(
        _activeTabIndex + 1,
        _BrowserTab(title: '${current.title} (نسخة)', url: current.url),
      );
      _activeTabIndex = _activeTabIndex + 1;
      _webviewContentTabIndex = _activeTabIndex;
    });
    unawaited(_persistSessionTabs());
    final uri = Uri.tryParse(current.url);
    if (uri != null) {
      unawaited(_navigateWithAutoPort(uri));
    }
  }

  void _reopenClosedTab() {
    if (_closedTabs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد تبويبات مغلقة مؤخرًا')),
      );
      return;
    }
    final tab = _closedTabs.removeLast();
    setState(() {
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
      _webviewContentTabIndex = _activeTabIndex;
    });
    unawaited(_persistSessionTabs());
    final uri = Uri.tryParse(tab.url);
    if (uri != null) {
      unawaited(_navigateWithAutoPort(uri));
    }
  }

  Future<void> _openFindInPageDialog() async {
    if (!mounted) return;
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('بحث داخل الصفحة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'اكتب كلمة البحث...',
            prefixIcon: Icon(Icons.search),
          ),
          onSubmitted: (_) => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('بحث'),
          ),
        ],
      ),
    );
    final q = controller.text.trim();
    if (q.isEmpty) return;
    final escaped = jsonEncode(q);
    try {
      await _controller.executeScript(
        'window.find($escaped, false, false, true, false, false, false);',
      );
    } catch (_) {}
  }

  Future<void> _openTabsOverviewSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.tab_outlined),
                title: Text('كل التبويبات'),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: _tabs.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final moved = _tabs.removeAt(oldIndex);
                      _tabs.insert(newIndex, moved);
                      if (_activeTabIndex == oldIndex) {
                        _activeTabIndex = newIndex;
                      } else if (oldIndex < _activeTabIndex &&
                          newIndex >= _activeTabIndex) {
                        _activeTabIndex -= 1;
                      } else if (oldIndex > _activeTabIndex &&
                          newIndex <= _activeTabIndex) {
                        _activeTabIndex += 1;
                      }
                      if (_webviewContentTabIndex == oldIndex) {
                        _webviewContentTabIndex = newIndex;
                      } else if (oldIndex < _webviewContentTabIndex &&
                          newIndex >= _webviewContentTabIndex) {
                        _webviewContentTabIndex -= 1;
                      } else if (oldIndex > _webviewContentTabIndex &&
                          newIndex <= _webviewContentTabIndex) {
                        _webviewContentTabIndex += 1;
                      }
                    });
                    unawaited(_persistSessionTabs());
                  },
                  itemBuilder: (context, index) {
                    final tab = _tabs[index];
                    final active = index == _activeTabIndex;
                    return ListTile(
                      key: ValueKey('tab_${tab.url}_$index'),
                      leading: Icon(
                        active
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      title: Text(
                        tab.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        tab.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.drag_indicator),
                      onTap: () {
                        Navigator.of(context).pop();
                        _switchTab(index);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openBrowserSettingsDialog() async {
    if (!mounted) return;
    final homeController = TextEditingController(text: _homeUrl);
    String selectedSearch = _searchEngineTemplate;
    bool intranetOnly = _intranetOnlyMode;
    const options = <String, String>{
      'https://www.google.com/search?q={query}': 'Google',
      'https://www.bing.com/search?q={query}': 'Bing',
      'https://duckduckgo.com/?q={query}': 'DuckDuckGo',
    };
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('إعدادات المتصفح'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: homeController,
                      decoration: const InputDecoration(
                        labelText: 'الرئيسية',
                        hintText: 'https://example.com',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedSearch,
                      decoration: const InputDecoration(
                        labelText: 'محرك البحث',
                      ),
                      items: options.entries
                          .map(
                            (entry) => DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() => selectedSearch = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: intranetOnly,
                      title: const Text('وضع الشبكة الداخلية فقط'),
                      subtitle: const Text(
                        'منع الروابط الخارجية والاكتفاء بسيرفرات LAN',
                      ),
                      onChanged: (value) =>
                          setModalState(() => intranetOnly = value),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != true) return;
    final nextHome = homeController.text.trim().isEmpty
        ? widget.initialUrl.toString()
        : homeController.text.trim();
    setState(() {
      _homeUrl = nextHome;
      _searchEngineTemplate = selectedSearch;
      _intranetOnlyMode = intranetOnly;
    });
    await _persistBrowserSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم حفظ إعدادات المتصفح')));
  }

  Future<void> _clearBrowsingData() async {
    if (!mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مسح بيانات التصفح'),
        content: const Text(
          'سيتم مسح السجل والمفضلة وكلمات المرور المحفوظة. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('مسح'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    setState(() {
      _history.clear();
      _bookmarks.clear();
      _credentials.clear();
      _urlSuggestions = const <String>[];
      _showUrlSuggestions = false;
    });
    await Future.wait<void>([
      _persistHistory(),
      _persistBookmarks(),
      _persistCredentials(),
    ]);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم مسح بيانات التصفح بنجاح')));
  }

  Future<void> _resetCurrentSitePermissions() async {
    final host = _currentUri()?.host.trim() ?? '';
    if (host.isEmpty || !mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعادة ضبط صلاحيات الموقع'),
        content: Text('سيتم حذف إعدادات الصلاحيات الخاصة بالموقع: $host'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('إعادة ضبط'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    setState(() => _sitePermissions.removeWhere((entry) => entry.host == host));
    await _persistSitePermissions();
    await _applySitePermissionsForUrl(_currentUrlText);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تمت إعادة ضبط صلاحيات هذا الموقع')),
    );
  }

  Future<void> _openSiteDataInspector() async {
    final uri = _currentUri();
    if (uri == null || !mounted) return;
    String cookieText = '';
    try {
      final raw = await _controller.executeScript('document.cookie || ""');
      final decoded = jsonDecode(raw);
      cookieText = decoded is String ? decoded : raw;
    } catch (_) {}
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('بيانات الموقع الحالية'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                'Host: ${uri.host}\nPort: ${uri.port}\nPath: ${uri.path}',
              ),
              const SizedBox(height: 12),
              const Text('Cookies'),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    cookieText.trim().isEmpty
                        ? 'لا توجد Cookies ظاهرة حاليًا.'
                        : cookieText,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBrowserProfile() async {
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'حفظ Browser Profile',
      fileName: 'browser_profile.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (savePath == null || savePath.trim().isEmpty) return;
    final data = <String, dynamic>{
      'version': 1,
      'homeUrl': _homeUrl,
      'searchEngineTemplate': _searchEngineTemplate,
      'bookmarks': _bookmarks
          .map(
            (entry) => <String, dynamic>{
              'title': entry.title,
              'url': entry.url,
            },
          )
          .toList(),
      'history': _history
          .map(
            (entry) => <String, dynamic>{
              'url': entry.url,
              'title': entry.title,
              'ts': entry.at.toIso8601String(),
            },
          )
          .toList(),
      'credentials': _credentials
          .map(
            (entry) => <String, dynamic>{
              'host': entry.host,
              'username': entry.username,
              'password': entry.password,
              'updatedAt': entry.updatedAt.toIso8601String(),
            },
          )
          .toList(),
      'sitePermissions': _sitePermissions
          .map(
            (entry) => <String, dynamic>{
              'host': entry.host,
              'notifications': entry.notifications,
              'cookies': entry.cookies,
              'popups': entry.popups,
            },
          )
          .toList(),
    };
    final file = File(savePath);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تصدير Browser Profile بنجاح')),
    );
  }

  Future<void> _importBrowserProfile() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'استيراد Browser Profile',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null || path.trim().isEmpty) return;
    final file = File(path);
    if (!await file.exists()) return;
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    final map = Map<String, dynamic>.from(decoded);

    final importedBookmarks = <_BookmarkItem>[];
    final importedHistory = <_HistoryItem>[];
    final importedCredentials = <_SavedCredential>[];
    final importedPermissions = <_SitePermission>[];

    final bookmarksRaw = map['bookmarks'];
    if (bookmarksRaw is List) {
      for (final item in bookmarksRaw.whereType<Map>()) {
        final m = Map<String, dynamic>.from(item);
        final url = m['url']?.toString().trim() ?? '';
        if (url.isEmpty) continue;
        importedBookmarks.add(
          _BookmarkItem(title: m['title']?.toString() ?? url, url: url),
        );
      }
    }

    final historyRaw = map['history'];
    if (historyRaw is List) {
      for (final item in historyRaw.whereType<Map>()) {
        final m = Map<String, dynamic>.from(item);
        final url = m['url']?.toString().trim() ?? '';
        final ts = DateTime.tryParse(m['ts']?.toString() ?? '');
        if (url.isEmpty || ts == null) continue;
        importedHistory.add(
          _HistoryItem(
            url: url,
            title: m['title']?.toString().trim() ?? url,
            at: ts,
          ),
        );
      }
    }

    final credentialsRaw = map['credentials'];
    if (credentialsRaw is List) {
      for (final item in credentialsRaw.whereType<Map>()) {
        final m = Map<String, dynamic>.from(item);
        final host = m['host']?.toString().trim() ?? '';
        final username = m['username']?.toString().trim() ?? '';
        final password = m['password']?.toString() ?? '';
        if (host.isEmpty || username.isEmpty || password.isEmpty) continue;
        importedCredentials.add(
          _SavedCredential(
            host: host,
            username: username,
            password: password,
            updatedAt:
                DateTime.tryParse(m['updatedAt']?.toString() ?? '') ??
                DateTime.now(),
          ),
        );
      }
    }

    final permsRaw = map['sitePermissions'];
    if (permsRaw is List) {
      for (final item in permsRaw.whereType<Map>()) {
        final m = Map<String, dynamic>.from(item);
        final host = m['host']?.toString().trim() ?? '';
        if (host.isEmpty) continue;
        importedPermissions.add(
          _SitePermission(
            host: host,
            notifications: m['notifications']?.toString() ?? 'ask',
            cookies: m['cookies']?.toString() ?? 'allow',
            popups: m['popups']?.toString() ?? 'block',
          ),
        );
      }
    }

    setState(() {
      _homeUrl = map['homeUrl']?.toString().trim().isNotEmpty == true
          ? map['homeUrl'].toString().trim()
          : _homeUrl;
      _searchEngineTemplate =
          map['searchEngineTemplate']?.toString().trim().isNotEmpty == true
          ? map['searchEngineTemplate'].toString().trim()
          : _searchEngineTemplate;
      _bookmarks
        ..clear()
        ..addAll(importedBookmarks);
      _history
        ..clear()
        ..addAll(importedHistory);
      _credentials
        ..clear()
        ..addAll(importedCredentials);
      _sitePermissions
        ..clear()
        ..addAll(importedPermissions);
    });
    _pruneHistory();
    await Future.wait<void>([
      _persistBrowserSettings(),
      _persistBookmarks(),
      _persistHistory(),
      _persistCredentials(),
      _persistSitePermissions(),
    ]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم استيراد Browser Profile بنجاح')),
    );
  }

  Future<void> _openCredentialsManagerSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: SizedBox(
                height: 420,
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.password_outlined),
                      title: Text('مدير كلمات المرور'),
                    ),
                    Expanded(
                      child: _credentials.isEmpty
                          ? const Center(
                              child: Text('لا توجد بيانات دخول محفوظة'),
                            )
                          : ListView.builder(
                              itemCount: _credentials.length,
                              itemBuilder: (context, index) {
                                final item = _credentials[index];
                                return ListTile(
                                  title: Text(item.host),
                                  subtitle: Text(item.username),
                                  trailing: IconButton(
                                    tooltip: 'حذف',
                                    onPressed: () async {
                                      setState(
                                        () => _credentials.removeAt(index),
                                      );
                                      setModalState(() {});
                                      await _persistCredentials();
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openSitePermissionsPanel() async {
    if (!mounted) return;
    final currentHost = _currentUri()?.host.trim() ?? '';
    _SitePermission current = currentHost.isEmpty
        ? const _SitePermission(
            host: '',
            notifications: 'ask',
            cookies: 'allow',
            popups: 'block',
          )
        : _permissionForHost(currentHost);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget buildChoice({
              required String label,
              required String value,
              required List<({String id, String text})> items,
              required ValueChanged<String?> onChanged,
            }) {
              return DropdownButtonFormField<String>(
                value: value,
                decoration: InputDecoration(labelText: label),
                items: items
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item.id,
                        child: Text(item.text),
                      ),
                    )
                    .toList(),
                onChanged: onChanged,
              );
            }

            return SafeArea(
              child: SizedBox(
                height: 560,
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.security_outlined),
                      title: Text('Site Permissions'),
                      subtitle: Text(
                        'Notifications / Cookies / Popups لكل موقع',
                      ),
                    ),
                    if (currentHost.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'الموقع الحالي: $currentHost',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                            const SizedBox(height: 10),
                            buildChoice(
                              label: 'Notifications',
                              value: current.notifications,
                              items: const [
                                (id: 'ask', text: 'Ask'),
                                (id: 'allow', text: 'Allow'),
                                (id: 'block', text: 'Block'),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                setModalState(() {
                                  current = current.copyWith(notifications: v);
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            buildChoice(
                              label: 'Cookies',
                              value: current.cookies,
                              items: const [
                                (id: 'allow', text: 'Allow'),
                                (id: 'block', text: 'Block'),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                setModalState(() {
                                  current = current.copyWith(cookies: v);
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            buildChoice(
                              label: 'Popups',
                              value: current.popups,
                              items: const [
                                (id: 'block', text: 'Block'),
                                (id: 'allow', text: 'Allow'),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                setModalState(() {
                                  current = current.copyWith(popups: v);
                                });
                              },
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: () async {
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  await _setPermissionForHost(current);
                                  final uri = _currentUri();
                                  if (uri != null) {
                                    await _applySitePermissionsForUrl(
                                      uri.toString(),
                                    );
                                  }
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'تم حفظ صلاحيات الموقع الحالي',
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.save_outlined),
                                label: const Text('حفظ للموقع الحالي'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 1),
                    const ListTile(
                      dense: true,
                      title: Text('كل المواقع المحفوظة'),
                    ),
                    Expanded(
                      child: _sitePermissions.isEmpty
                          ? const Center(
                              child: Text('لا توجد صلاحيات مواقع محفوظة'),
                            )
                          : ListView.builder(
                              itemCount: _sitePermissions.length,
                              itemBuilder: (context, index) {
                                final item = _sitePermissions[index];
                                return ListTile(
                                  title: Text(item.host),
                                  subtitle: Text(
                                    'N:${item.notifications}  C:${item.cookies}  P:${item.popups}',
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'حذف',
                                    onPressed: () async {
                                      setState(
                                        () => _sitePermissions.removeAt(index),
                                      );
                                      setModalState(() {});
                                      await _persistSitePermissions();
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openQuickPageActions() async {
    final uri = _currentUri();
    if (uri == null || !mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('نسخ عنوان الصفحة'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop('copy'),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('معلومات الصفحة الحالية'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop('info'),
              ),
            ],
          ),
        );
      },
    );
    if (choice == null) return;
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نسخ رابط الصفحة الحالية')),
      );
      return;
    }
    if (choice == 'info' && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('معلومات الصفحة'),
          content: SelectableText(
            'Host: ${uri.host}\nPort: ${uri.port}\nPath: ${uri.path.isEmpty ? '/' : uri.path}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _openBookmarksSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            children: [
              const ListTile(title: Text('المفضلة')),
              Expanded(
                child: ListView.builder(
                  itemCount: _bookmarks.length,
                  itemBuilder: (context, index) {
                    final item = _bookmarks[index];
                    return ListTile(
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        item.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        _ensureActiveTabOwnsWebView();
                        final uri = Uri.tryParse(item.url);
                        if (uri != null) {
                          unawaited(_navigateWithAutoPort(uri));
                        }
                      },
                      trailing: IconButton(
                        onPressed: () {
                          setState(() => _bookmarks.removeAt(index));
                          unawaited(_persistBookmarks());
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Uri? _parseAddressInput(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final encoded = Uri.encodeQueryComponent(text);
    final template = _searchEngineTemplate.contains('{query}')
        ? _searchEngineTemplate
        : 'https://www.google.com/search?q={query}';
    final withScheme = text.contains('://')
        ? text
        : (text.contains('.')
              ? 'http://$text'
              : template.replaceAll('{query}', encoded));
    return Uri.tryParse(withScheme);
  }

  bool _isPrivateOrKnownHost(Uri uri) {
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) return false;
    if (widget.knownPortsByHost.containsKey(host) || host == 'localhost') {
      return true;
    }
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final nums = <int>[];
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return false;
      nums.add(n);
    }
    if (nums[0] == 10) return true;
    if (nums[0] == 192 && nums[1] == 168) return true;
    if (nums[0] == 172 && nums[1] >= 16 && nums[1] <= 31) return true;
    return false;
  }

  Future<void> _openAllCompanyServers() async {
    final known = widget.knownPortsByHost.entries.toList();
    if (known.isEmpty) return;
    final toOpen = <Uri>[];
    for (final entry in known) {
      final host = entry.key;
      final firstPort = entry.value.isNotEmpty ? entry.value.first : 80;
      toOpen.add(Uri.parse('http://$host:$firstPort/'));
    }
    setState(() {
      _tabs
        ..clear()
        ..addAll(
          toOpen.map(
            (uri) =>
                _BrowserTab(title: uri.host, url: uri.toString(), pinned: true),
          ),
        );
      _activeTabIndex = 0;
      _webviewContentTabIndex = 0;
    });
    await _persistSessionTabs();
    if (toOpen.isNotEmpty) {
      await _navigateWithAutoPort(toOpen.first);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم فتح ${toOpen.length} سيرفرات الشركة في تبويبات مثبّتة.',
        ),
      ),
    );
  }

  Future<void> _refreshDownloadedFiles() async {
    final dirPath = _downloadDir;
    if (dirPath == null || dirPath.isEmpty) {
      _downloadedFiles = const <FileSystemEntity>[];
      return;
    }
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      _downloadedFiles = const <FileSystemEntity>[];
      return;
    }
    final files = await dir
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    _downloadedFiles = files.take(12).toList();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _urlFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<String> _buildAddressCandidates() {
    final candidates = <String>{
      widget.initialUrl.toString(),
      ..._tabs.map((tab) => tab.url),
      ..._bookmarks.map((item) => item.url),
      ..._history.map((item) => item.url),
    };
    for (final entry in widget.knownPortsByHost.entries) {
      for (final port in entry.value) {
        candidates.add('http://${entry.key}:$port/');
      }
    }
    return candidates.where((entry) => entry.trim().isNotEmpty).toList();
  }

  void _refreshUrlSuggestions(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    final base = _buildAddressCandidates();
    List<String> next;
    if (query.isEmpty) {
      next = base.take(8).toList();
    } else {
      final starts = base.where(
        (entry) => entry.toLowerCase().startsWith(query),
      );
      final contains = base.where((entry) {
        final value = entry.toLowerCase();
        return !value.startsWith(query) && value.contains(query);
      });
      next = <String>[...starts, ...contains].take(8).toList();
    }
    if (!mounted) return;
    setState(() {
      _urlSuggestions = next;
      _showUrlSuggestions = _urlFocusNode.hasFocus && next.isNotEmpty;
    });
  }

  void _selectSuggestion(String value) {
    _urlController.text = value;
    if (mounted) {
      setState(() => _showUrlSuggestions = false);
    }
    _ensureActiveTabOwnsWebView();
    final parsed = _parseAddressInput(value);
    if (parsed != null) {
      unawaited(_navigateWithAutoPort(parsed));
    }
    FocusScope.of(context).unfocus();
  }

  Future<void> _saveCredentialsForHost({
    required String host,
    required String username,
    required String password,
  }) async {
    if (host.trim().isEmpty || username.trim().isEmpty || password.isEmpty) {
      return;
    }
    setState(() {
      _credentials.removeWhere((entry) => entry.host == host);
      _credentials.insert(
        0,
        _SavedCredential(
          host: host,
          username: username.trim(),
          password: password,
          updatedAt: DateTime.now(),
        ),
      );
    });
    await _persistCredentials();
  }

  Map<String, dynamic>? _decodeScriptMapResult(String raw) {
    try {
      final first = jsonDecode(raw);
      if (first is Map) return Map<String, dynamic>.from(first);
      if (first is String) {
        final second = jsonDecode(first);
        if (second is Map) return Map<String, dynamic>.from(second);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveCredentialsFromCurrentPage({bool showSnack = true}) async {
    final uri = _currentUri();
    if (uri == null || uri.host.trim().isEmpty || !mounted) return;
    final script = '''
(() => {
  const userSelector = 'input[type="email"],input[name*="user" i],input[name*="login" i],input[id*="user" i],input[type="text"]';
  const passSelector = 'input[type="password"]';
  const user = document.querySelector(userSelector);
  const pass = document.querySelector(passSelector);
  const data = {
    username: (user && user.value ? user.value : '').trim(),
    password: (pass && pass.value ? pass.value : ''),
  };
  return JSON.stringify(data);
})();
''';
    String? username;
    String? password;
    try {
      final raw = await _controller.executeScript(script);
      final map = _decodeScriptMapResult(raw);
      username = map?['username']?.toString().trim();
      password = map?['password']?.toString();
    } catch (_) {}
    if (username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل بيانات الدخول في الصفحة أولًا ثم اضغط حفظ.'),
        ),
      );
      return;
    }
    await _saveCredentialsForHost(
      host: uri.host,
      username: username,
      password: password,
    );
    if (!mounted) return;
    if (showSnack) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ بيانات الدخول تلقائيًا لهذا الموقع'),
        ),
      );
    }
  }

  Future<void> _maybeAutofillForUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final saved = _credentials
        .where((entry) => entry.host == uri.host)
        .toList();
    if (saved.isEmpty) return;
    final cred = saved.first;
    final escapedUser = jsonEncode(cred.username);
    final escapedPass = jsonEncode(cred.password);
    final script =
        '''
(() => {
  const userSelector = 'input[type="email"],input[name*="user" i],input[name*="login" i],input[id*="user" i],input[type="text"]';
  const pwdSelector = 'input[type="password"]';
  const apply = () => {
    const user = document.querySelector(userSelector);
    const pass = document.querySelector(pwdSelector);
    if (user && !user.value) user.value = $escapedUser;
    if (pass && !pass.value) pass.value = $escapedPass;
    if (user) user.dispatchEvent(new Event('input', { bubbles: true }));
    if (pass) pass.dispatchEvent(new Event('input', { bubbles: true }));
  };
  apply();
  const observer = new MutationObserver(() => apply());
  observer.observe(document.documentElement || document.body, {
    childList: true,
    subtree: true,
  });
  window.__csScannerFillObserver = observer;
})();
''';
    try {
      await _controller.executeScript(
        'if (window.__csScannerFillObserver) { try { window.__csScannerFillObserver.disconnect(); } catch (_) {} }',
      );
      await _controller.executeScript(script);
    } catch (_) {}
  }

  Future<void> _applySitePermissionsForUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.trim().isEmpty) return;
    final permission = _permissionForHost(uri.host);
    try {
      await _controller.setPopupWindowPolicy(
        permission.popups == 'allow'
            ? WebviewPopupWindowPolicy.allow
            : WebviewPopupWindowPolicy.deny,
      );
    } catch (_) {}

    if (permission.cookies == 'block') {
      try {
        await _controller.executeScript('''
(() => {
  const cookies = document.cookie ? document.cookie.split(';') : [];
  for (const c of cookies) {
    const eqPos = c.indexOf('=');
    const name = eqPos > -1 ? c.substring(0, eqPos).trim() : c.trim();
    if (!name) continue;
    document.cookie = name + '=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/';
  }
})();
''');
      } catch (_) {}
    }

    final notifScript = permission.notifications == 'block'
        ? '''
(() => {
  try {
    if ('Notification' in window) {
      window.Notification.requestPermission = async () => 'denied';
      Object.defineProperty(window.Notification, 'permission', { get: () => 'denied' });
    }
  } catch (_) {}
})();
'''
        : permission.notifications == 'allow'
        ? '''
(() => {
  try {
    if ('Notification' in window) {
      window.Notification.requestPermission = async () => 'granted';
      Object.defineProperty(window.Notification, 'permission', { get: () => 'granted' });
    }
  } catch (_) {}
})();
'''
        : '';
    if (notifScript.isNotEmpty) {
      try {
        await _controller.executeScript(notifScript);
      } catch (_) {}
    }
  }

  bool _isLikelyLoginPath(Uri uri) {
    final value = uri.path.toLowerCase();
    return value.contains('login') ||
        value.contains('signin') ||
        value.contains('auth') ||
        value.contains('account');
  }

  void _maybeSuggestCredentialSave(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.host.isEmpty ||
        !_isLikelyLoginPath(uri) ||
        !mounted) {
      return;
    }
    final hasSaved = _credentials.any((entry) => entry.host == uri.host);
    if (hasSaved || _credentialPromptedHosts.contains(uri.host)) return;
    _credentialPromptedHosts.add(uri.host);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('هل تريد حفظ بيانات الدخول للموقع ${uri.host}؟'),
        action: SnackBarAction(
          label: 'حفظ',
          onPressed: () => unawaited(_saveCredentialsFromCurrentPage()),
        ),
      ),
    );
  }

  String _lastPortPrefsKeyForHost(String host) =>
      '$_browserBestPortPrefsPrefix$host';

  Future<int?> _readLastSuccessfulPortForHost(String host) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastPortPrefsKeyForHost(host));
  }

  Future<void> _saveLastSuccessfulPortForHost(String host, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastPortPrefsKeyForHost(host), port);
  }

  Future<List<int>> _rankPortsForUri(Uri fixed, List<int> ports) async {
    final saved = await _readLastSuccessfulPortForHost(fixed.host);
    final probes = <({int port, bool ok, int latency})>[];
    for (final port in ports) {
      final candidate = fixed.replace(port: port);
      final watch = Stopwatch()..start();
      final ok = await _isReachable(candidate);
      watch.stop();
      probes.add((port: port, ok: ok, latency: watch.elapsedMilliseconds));
    }
    probes.sort((a, b) {
      if (a.ok != b.ok) return a.ok ? -1 : 1;
      if (a.latency != b.latency) return a.latency.compareTo(b.latency);
      return a.port.compareTo(b.port);
    });
    final ordered = probes.map((p) => p.port).toList();
    final savedProbe = probes.where((p) => p.port == saved).toList();
    final savedOk = savedProbe.isNotEmpty && savedProbe.first.ok;
    if (saved != null && ordered.contains(saved) && savedOk) {
      ordered
        ..remove(saved)
        ..insert(0, saved);
    }
    return ordered;
  }

  Future<void> _openDownloadsSheet() async {
    await _refreshDownloadedFiles();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: 460,
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.download_for_offline_outlined),
                  title: Text('مدير التحميل'),
                ),
                if (_downloadQueue.isNotEmpty)
                  Expanded(
                    child: ListView.builder(
                      itemCount: _downloadQueue.length,
                      itemBuilder: (context, index) {
                        final job = _downloadQueue[index];
                        return ListTile(
                          leading: const Icon(Icons.downloading_outlined),
                          title: Text(
                            job.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(switch (job.status) {
                            _DownloadJobStatus.queued => 'في الانتظار',
                            _DownloadJobStatus.downloading =>
                              'جارٍ التحميل ${(job.progress * 100).toStringAsFixed(0)}%',
                            _DownloadJobStatus.completed => 'تم التحميل',
                            _DownloadJobStatus.failed => 'فشل التحميل',
                          }),
                          trailing:
                              job.status == _DownloadJobStatus.completed &&
                                  job.savedPath != null
                              ? IconButton(
                                  tooltip: 'فتح الملف',
                                  onPressed: () =>
                                      OpenFilex.open(job.savedPath!),
                                  icon: const Icon(Icons.open_in_new),
                                )
                              : job.status == _DownloadJobStatus.failed
                              ? IconButton(
                                  tooltip: 'إعادة المحاولة',
                                  onPressed: () => _retryDownloadJob(job),
                                  icon: const Icon(Icons.refresh),
                                )
                              : const SizedBox.shrink(),
                        );
                      },
                    ),
                  )
                else
                  const ListTile(
                    title: Text('لا توجد مهام تحميل حالية'),
                    dense: true,
                  ),
                const Divider(height: 1),
                const ListTile(
                  title: Text('آخر الملفات المحمّلة'),
                  dense: true,
                ),
                Expanded(
                  child: _downloadedFiles.isEmpty
                      ? const Center(child: Text('لا توجد ملفات بعد'))
                      : ListView.builder(
                          itemCount: _downloadedFiles.length,
                          itemBuilder: (context, index) {
                            final file = _downloadedFiles[index];
                            final name = p.basename(file.path);
                            return ListTile(
                              leading: const Icon(
                                Icons.insert_drive_file_outlined,
                              ),
                              title: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => OpenFilex.open(file.path),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleLoadErrorAndFailover() async {
    if (!mounted) {
      if (mounted) {
        setState(() {
          _error = 'تعذر تحميل الصفحة. تأكد من الشبكة أو السيرفر.';
        });
      }
      return;
    }
    setState(() {
      _error =
          'تعذر تحميل الصفحة. تأكد من الشبكة أو من حالة السيرفر ثم أعد المحاولة.';
      _triedFailoverForCurrentLoad = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'فشل تحميل الصفحة الحالية. المتصفح لن يغيّر البورت تلقائيًا إلا إذا لم تحدد بورت من البداية.',
        ),
      ),
    );
    return;
    // ignore: dead_code
    _triedFailoverForCurrentLoad = true;
    final current = _currentUri();
    if (current == null) {
      if (mounted) {
        setState(() {
          _error = 'تعذر تحميل الصفحة. تأكد من الشبكة أو السيرفر.';
        });
      }
      return;
    }
    final alternative = await _findAlternativePortUri(current);
    if (!mounted) return;
    if (alternative == null) {
      setState(() {
        _error = 'تعذر تحميل الصفحة وتمت تجربة البورتات البديلة بدون نجاح.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر الاتصال بالسيرفر الآن. حاول مرة أخرى بعد التأكد من الشبكة أو حالة السيرفر.',
          ),
        ),
      );
      return;
    }
    final nextUrl = alternative.toString();
    _isNavigating = true;
    try {
      await _controller.loadUrl(nextUrl);
      await _saveLastSuccessfulPortForHost(alternative.host, alternative.port);
      if (!mounted) return;
      setState(() {
        _error = null;
        _currentUrlText = nextUrl;
        if (_tabs.isNotEmpty &&
            _activeTabIndex < _tabs.length &&
            !_tabs[_activeTabIndex].isDashboard) {
          _urlController.text = nextUrl;
        }
        final syncIdx = _tabIndexReceivingWebViewEvents();
        if (syncIdx != null) {
          _tabs[syncIdx] = _tabs[syncIdx].copyWith(url: nextUrl);
        }
        _triedFailoverForCurrentLoad = false;
      });
      unawaited(_persistSessionTabs());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تحويل الاتصال تلقائيًا من البورت ${current.port} إلى البورت ${alternative.port} لضمان استمرار العمل.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تحميل الصفحة على البورت الحالي والبورت البديل.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'فشل التحويل التلقائي للبورت البديل. حاول إعادة المحاولة.',
          ),
        ),
      );
    } finally {
      _isNavigating = false;
    }
  }

  Future<Uri?> _findAlternativePortUri(Uri current) async {
    final hostPorts = widget.knownPortsByHost[current.host];
    if (hostPorts == null || hostPorts.isEmpty) return null;
    for (final port in hostPorts) {
      if (port == current.port) continue;
      final candidate = current.replace(port: port);
      if (await _isReachable(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  Uri? _currentUri() {
    try {
      final value = _currentUrlText;
      if (value.trim().isEmpty) return null;
      return Uri.parse(value);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _navigateWithAutoPort(
    Uri input, {
    bool allowSamePort = true,
  }) async {
    _isNavigating = true;
    try {
      final fixed = input.hasScheme
          ? input
          : Uri.parse('http://${input.toString()}');
      if (_intranetOnlyMode && !_isPrivateOrKnownHost(fixed)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'وضع الشبكة الداخلية مفعّل. لا يمكن فتح روابط خارجية من هذا المتصفح.',
              ),
            ),
          );
        }
        return false;
      }
      if (fixed.hasPort) {
        await _controller.loadUrl(fixed.toString());
        final reachable = await _isReachable(fixed);
        if (reachable) {
          await _saveLastSuccessfulPortForHost(fixed.host, fixed.port);
        }
        if (mounted) {
          setState(() {
            _error = null;
            _urlController.text = fixed.toString();
          });
        }
        return true;
      }
      final ports = widget.knownPortsByHost[fixed.host];
      if (ports == null || ports.isEmpty) {
        await _controller.loadUrl(fixed.toString());
        return true;
      }

      final rankedPorts = await _rankPortsForUri(fixed, ports);
      for (final port in rankedPorts) {
        if (!allowSamePort && port == fixed.port) {
          continue;
        }
        final candidate = fixed.replace(port: port);
        if (await _isReachable(candidate)) {
          await _controller.loadUrl(candidate.toString());
          await _saveLastSuccessfulPortForHost(fixed.host, port);
          if (mounted) {
            setState(() {
              _error = null;
              _urlController.text = candidate.toString();
            });
          }
          return true;
        }
      }

      if (allowSamePort && await _isReachable(fixed)) {
        await _controller.loadUrl(fixed.toString());
        await _saveLastSuccessfulPortForHost(fixed.host, fixed.port);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      _isNavigating = false;
    }
  }

  Future<bool> _isReachable(Uri uri) async {
    final probe = await _probePortHealth(
      uri,
      connectTimeoutMs: 3000,
      requestTimeoutMs: 4000,
    );
    return probe.canOpen;
  }

  Future<void> _openInExternalBrowser() async {
    final uri = _currentUri();
    if (uri == null) return;
    try {
      await Process.run('cmd', <String>[
        '/c',
        'start',
        '',
        uri.toString(),
      ], runInShell: true);
    } catch (_) {}
  }

  void _goHome() {
    _ensureActiveTabOwnsWebView();
    final uri = _parseAddressInput(_homeUrl) ?? widget.initialUrl;
    unawaited(_navigateWithAutoPort(uri));
  }

  void _newTab() {
    final nextIndex = _tabs.length + 1;
    setState(() {
      _tabs.add(
        _BrowserTab(title: 'تبويب $nextIndex', url: '', isDashboard: true),
      );
      _activeTabIndex = _tabs.length - 1;
    });
    unawaited(_persistSessionTabs());
    unawaited(_refreshDashboardServers());
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) return;
    if (_tabs[index].pinned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('التبويب مثبت. أزل التثبيت أولًا ثم أغلقه.'),
        ),
      );
      return;
    }
    _closedTabs.add(_tabs[index]);
    if (_closedTabs.length > 15) {
      _closedTabs.removeAt(0);
    }
    setState(() {
      _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
      if (_webviewContentTabIndex == index) {
        _webviewContentTabIndex = _activeTabIndex.clamp(0, _tabs.length - 1);
      } else if (_webviewContentTabIndex > index) {
        _webviewContentTabIndex--;
      }
    });
    unawaited(_persistSessionTabs());
    final active = _tabs[_activeTabIndex];
    if (active.isDashboard) {
      return;
    }
    final uri = Uri.tryParse(active.url);
    if (uri != null &&
        !_urlsMatchForSameDocument(_currentUrlText, active.url)) {
      unawaited(_navigateWithAutoPort(uri));
    }
  }

  void _switchTab(int index) {
    if (index == _activeTabIndex || index < 0 || index >= _tabs.length) return;
    setState(() {
      _activeTabIndex = index;
      _urlController.text = _tabs[index].url;
    });
    unawaited(_persistSessionTabs());
    if (_tabs[index].isDashboard) {
      unawaited(_refreshDashboardServers());
      return;
    }
    _webviewContentTabIndex = index;
    final tabUrl = _tabs[index].url;
    final uri = Uri.tryParse(tabUrl);
    if (uri != null &&
        tabUrl.trim().isNotEmpty &&
        !_urlsMatchForSameDocument(_currentUrlText, tabUrl)) {
      unawaited(_navigateWithAutoPort(uri));
    }
  }

  Future<void> _openServerFromDashboard(String host) async {
    final ports = widget.knownPortsByHost[host];
    if (ports == null || ports.isEmpty) return;
    final uri = Uri.parse('http://$host/');
    final opened = await _navigateWithAutoPort(uri);
    if (!mounted || !opened) return;
    final activeUrl = _currentUrlText.trim().isEmpty
        ? uri.toString()
        : _currentUrlText;
    setState(() {
      if (_activeTabIndex < _tabs.length) {
        _tabs[_activeTabIndex] = _tabs[_activeTabIndex].copyWith(
          title: widget.knownTitlesByHost[host] ?? host,
          url: activeUrl,
          isDashboard: false,
        );
        _webviewContentTabIndex = _activeTabIndex;
      }
    });
    await _persistSessionTabs();
  }

  Future<void> _pickDownloadDirectory() async {
    final downloads = await getDownloadsDirectory();
    final fallback = downloads?.path ?? '';
    if (!mounted) return;
    final controller = TextEditingController(text: _downloadDir ?? fallback);
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعدادات التحميل'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'مسار الحفظ',
            hintText: 'اكتب مسار مجلد التحميل',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (selected == null || selected.isEmpty) return;
    final dir = Directory(selected);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('browser_download_dir', selected);
    setState(() => _downloadDir = selected);
    await _refreshDownloadedFiles();
    if (mounted) setState(() {});
  }

  Future<void> _downloadCurrentUrl() async {
    final url = _currentUri();
    if (url == null) return;
    final dirPath = _downloadDir;
    if (dirPath == null || dirPath.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدد مجلد التحميل أولًا من الإعدادات.')),
      );
      return;
    }
    final name = p.basename(url.path).trim().isEmpty
        ? 'download_${DateTime.now().millisecondsSinceEpoch}.bin'
        : p.basename(url.path);
    setState(() {
      _downloadQueue.insert(
        0,
        _DownloadJob(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          url: url,
          fileName: name,
          targetDirectory: dirPath,
          status: _DownloadJobStatus.queued,
          progress: 0,
        ),
      );
    });
    unawaited(_processDownloadQueue());
  }

  Future<void> _processDownloadQueue() async {
    if (_isProcessingDownloads) return;
    _isProcessingDownloads = true;
    try {
      while (true) {
        final pending = _downloadQueue
            .where((job) => job.status == _DownloadJobStatus.queued)
            .toList();
        if (pending.isEmpty) break;
        final current = pending.first;
        final index = _downloadQueue.indexWhere(
          (entry) => entry.id == current.id,
        );
        if (index < 0) break;
        setState(() {
          _downloadQueue[index] = _downloadQueue[index].copyWith(
            status: _DownloadJobStatus.downloading,
            progress: 0,
            error: null,
          );
        });
        try {
          final client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 10);
          final req = await client.getUrl(current.url);
          final res = await req.close();
          if (res.statusCode < 200 || res.statusCode >= 400) {
            throw Exception('HTTP ${res.statusCode}');
          }
          final total = res.contentLength;
          final file = File(p.join(current.targetDirectory, current.fileName));
          final sink = file.openWrite();
          var received = 0;
          await for (final chunk in res) {
            sink.add(chunk);
            received += chunk.length;
            final progress = total > 0
                ? (received / total).clamp(0, 1).toDouble()
                : 0.0;
            final runningIdx = _downloadQueue.indexWhere(
              (entry) => entry.id == current.id,
            );
            if (runningIdx >= 0) {
              setState(() {
                _downloadQueue[runningIdx] = _downloadQueue[runningIdx]
                    .copyWith(progress: progress);
              });
            }
          }
          await sink.close();
          final doneIdx = _downloadQueue.indexWhere(
            (entry) => entry.id == current.id,
          );
          if (doneIdx >= 0) {
            setState(() {
              _downloadQueue[doneIdx] = _downloadQueue[doneIdx].copyWith(
                status: _DownloadJobStatus.completed,
                progress: 1,
                savedPath: file.path,
              );
            });
          }
          await _refreshDownloadedFiles();
        } catch (error) {
          final failIdx = _downloadQueue.indexWhere(
            (entry) => entry.id == current.id,
          );
          if (failIdx >= 0) {
            setState(() {
              _downloadQueue[failIdx] = _downloadQueue[failIdx].copyWith(
                status: _DownloadJobStatus.failed,
                error: error.toString(),
              );
            });
          }
        }
      }
    } finally {
      _isProcessingDownloads = false;
    }
  }

  void _retryDownloadJob(_DownloadJob job) {
    final index = _downloadQueue.indexWhere((entry) => entry.id == job.id);
    if (index < 0) return;
    setState(() {
      _downloadQueue[index] = _downloadQueue[index].copyWith(
        status: _DownloadJobStatus.queued,
        progress: 0,
        error: null,
      );
    });
    unawaited(_processDownloadQueue());
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () {
          _urlFocusNode.requestFocus();
          _urlController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _urlController.text.length,
          );
          _refreshUrlSuggestions(_urlController.text);
        },
        const SingleActivator(LogicalKeyboardKey.keyT, control: true): _newTab,
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
            _closeTab(_activeTabIndex),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
            _controller.reload(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            unawaited(_openFindInPageDialog()),
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          title: Row(
            children: [
              Text(widget.title),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_activeTabIndex + 1}/${_tabs.length}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'الرئيسية',
              onPressed: _goHome,
              icon: const Icon(Icons.home_outlined),
            ),
            IconButton(
              tooltip: 'السجل',
              onPressed: _openHistorySheet,
              icon: const Icon(Icons.history),
            ),
            IconButton(
              tooltip: 'إضافة للمفضلة',
              onPressed: _addCurrentBookmark,
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
            IconButton(
              tooltip: 'المفضلة',
              onPressed: _openBookmarksSheet,
              icon: const Icon(Icons.bookmarks_outlined),
            ),
            IconButton(
              tooltip: 'إضافة/إزالة من المفضلة',
              onPressed: _toggleCurrentBookmark,
              icon: Icon(
                _isCurrentBookmarked()
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
              ),
            ),
            IconButton(
              tooltip: 'إعدادات التحميل',
              onPressed: _pickDownloadDirectory,
              icon: const Icon(Icons.settings_outlined),
            ),
            IconButton(
              tooltip: 'حفظ بيانات الدخول',
              onPressed: _saveCredentialsFromCurrentPage,
              icon: const Icon(Icons.password_outlined),
            ),
            IconButton(
              tooltip: 'تحميل الرابط الحالي',
              onPressed: _downloadCurrentUrl,
              icon: const Icon(Icons.download_outlined),
            ),
            IconButton(
              tooltip: 'مدير التحميل',
              onPressed: _openDownloadsSheet,
              icon: const Icon(Icons.folder_zip_outlined),
            ),
            IconButton(
              tooltip: 'رجوع',
              onPressed: () => _controller.goBack(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
            ),
            IconButton(
              tooltip: 'تقدم',
              onPressed: () => _controller.goForward(),
              icon: const Icon(Icons.arrow_forward_ios_rounded),
            ),
            IconButton(
              tooltip: 'إعادة تحميل',
              onPressed: () => _controller.reload(),
              icon: const Icon(Icons.refresh),
            ),
            PopupMenuButton<String>(
              tooltip: 'أدوات المتصفح',
              onSelected: (value) {
                switch (value) {
                  case 'tabs':
                    unawaited(_openTabsOverviewSheet());
                    break;
                  case 'duplicate':
                    _duplicateCurrentTab();
                    break;
                  case 'reopen':
                    _reopenClosedTab();
                    break;
                  case 'find':
                    unawaited(_openFindInPageDialog());
                    break;
                  case 'passwords':
                    unawaited(_openCredentialsManagerSheet());
                    break;
                  case 'permissions':
                    unawaited(_openSitePermissionsPanel());
                    break;
                  case 'site-data':
                    unawaited(_openSiteDataInspector());
                    break;
                  case 'reset-permissions':
                    unawaited(_resetCurrentSitePermissions());
                    break;
                  case 'page':
                    unawaited(_openQuickPageActions());
                    break;
                  case 'settings':
                    unawaited(_openBrowserSettingsDialog());
                    break;
                  case 'open-company':
                    unawaited(_openAllCompanyServers());
                    break;
                  case 'clear':
                    unawaited(_clearBrowsingData());
                    break;
                  case 'export-profile':
                    unawaited(_exportBrowserProfile());
                    break;
                  case 'import-profile':
                    unawaited(_importBrowserProfile());
                    break;
                  case 'external':
                    unawaited(_openInExternalBrowser());
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'tabs', child: Text('إدارة كل التبويبات')),
                PopupMenuItem(
                  value: 'duplicate',
                  child: Text('نسخ التبويب الحالي'),
                ),
                PopupMenuItem(
                  value: 'reopen',
                  child: Text('إعادة فتح آخر تبويب مغلق'),
                ),
                PopupMenuItem(value: 'find', child: Text('بحث داخل الصفحة')),
                PopupMenuItem(
                  value: 'passwords',
                  child: Text('مدير كلمات المرور'),
                ),
                PopupMenuItem(
                  value: 'permissions',
                  child: Text('Site Permissions'),
                ),
                PopupMenuItem(
                  value: 'site-data',
                  child: Text('بيانات الموقع الحالية'),
                ),
                PopupMenuItem(
                  value: 'reset-permissions',
                  child: Text('إعادة ضبط صلاحيات الموقع الحالي'),
                ),
                PopupMenuItem(
                  value: 'page',
                  child: Text('أدوات الصفحة الحالية'),
                ),
                PopupMenuItem(
                  value: 'settings',
                  child: Text('إعدادات المتصفح'),
                ),
                PopupMenuItem(
                  value: 'open-company',
                  child: Text('فتح كل سيرفرات الشركة'),
                ),
                PopupMenuItem(
                  value: 'export-profile',
                  child: Text('تصدير Browser Profile'),
                ),
                PopupMenuItem(
                  value: 'import-profile',
                  child: Text('استيراد Browser Profile'),
                ),
                PopupMenuItem(value: 'clear', child: Text('مسح بيانات التصفح')),
                PopupMenuItem(
                  value: 'external',
                  child: Text('فتح في نافذة خارجية'),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            SizedBox(
              height: 46,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _tabs.length + 1,
                itemBuilder: (context, index) {
                  if (index == _tabs.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: OutlinedButton.icon(
                        onPressed: _newTab,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('تبويب'),
                      ),
                    );
                  }
                  final tab = _tabs[index];
                  final active = index == _activeTabIndex;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _switchTab(index),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 205),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: active
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Expanded(
                              child: Text(
                                tab.isDashboard
                                    ? '🧩 Grid View'
                                    : (tab.pinned
                                          ? '📌 ${_compactTabTitle(tab.title)}'
                                          : _compactTabTitle(tab.title)),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _tabs[index] = _tabs[index].copyWith(
                                    pinned: !_tabs[index].pinned,
                                  );
                                });
                                unawaited(_persistSessionTabs());
                              },
                              child: Icon(
                                tab.pinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                size: 14,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _closeTab(index),
                              child: const Icon(Icons.close, size: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      focusNode: _urlFocusNode,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'أدخل الرابط...',
                        prefixIcon: Icon(Icons.link),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        if (mounted) {
                          setState(() => _showUrlSuggestions = false);
                        }
                        _ensureActiveTabOwnsWebView();
                        final parsed = _parseAddressInput(value);
                        if (parsed != null) {
                          unawaited(_navigateWithAutoPort(parsed));
                        }
                      },
                      onTap: () => _refreshUrlSuggestions(_urlController.text),
                      onChanged: _refreshUrlSuggestions,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      if (mounted) {
                        setState(() => _showUrlSuggestions = false);
                      }
                      _ensureActiveTabOwnsWebView();
                      final parsed = _parseAddressInput(_urlController.text);
                      if (parsed != null) {
                        unawaited(_navigateWithAutoPort(parsed));
                      }
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('فتح'),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'نسخ الرابط',
                    onPressed: () async {
                      final text = _urlController.text.trim();
                      if (text.isEmpty) return;
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: text));
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(content: Text('تم نسخ الرابط')),
                      );
                    },
                    icon: const Icon(Icons.content_copy_outlined),
                  ),
                ],
              ),
            ),
            if (_showUrlSuggestions)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  shrinkWrap: true,
                  itemCount: _urlSuggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final suggestion = _urlSuggestions[index];
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (_) => _selectSuggestion(suggestion),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.travel_explore_outlined,
                          size: 18,
                        ),
                        title: Text(
                          suggestion,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(
                    onPressed: () {
                      setState(() => _error = null);
                      final uri = _currentUri();
                      if (uri != null) {
                        unawaited(
                          _navigateWithAutoPort(uri, allowSamePort: false),
                        );
                      } else {
                        _controller.reload();
                      }
                    },
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_controllerInitialized)
                    Webview(_controller)
                  else
                    const Center(child: CircularProgressIndicator()),
                  if (_tabs.isNotEmpty &&
                      _activeTabIndex < _tabs.length &&
                      _tabs[_activeTabIndex].isDashboard)
                    Positioned.fill(
                      child: Material(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: _buildNewTabGridView(),
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

  Widget _buildNewTabGridView() {
    final hosts = widget.knownPortsByHost.keys.toList();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'اختر سيرفر للفتح',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'سيتم الدخول تلقائيًا على أفضل بورت متاح',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = (constraints.maxWidth / 240)
                        .floor()
                        .clamp(1, 3);
                    final childAspectRatio = crossAxisCount == 1 ? 2.8 : 1.85;

                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: childAspectRatio,
                      ),
                      itemCount: hosts.length,
                      itemBuilder: (context, index) {
                        final host = hosts[index];
                        final state = _dashboardStatusByHost[host];
                        final isUp = state?.isUp == true;
                        final color = isUp ? Colors.green : Colors.red;
                        final name = widget.knownTitlesByHost[host] ?? host;
                        final bestPort =
                            state?.bestUri?.port ??
                            (widget.knownPortsByHost[host]?.isNotEmpty == true
                                ? widget.knownPortsByHost[host]!.first
                                : null);
                        final latencyLabel = state?.latencyMs != null
                            ? ' (${state!.latencyMs}ms)'
                            : '';

                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () =>
                              unawaited(_openServerFromDashboard(host)),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerLow,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.circle, size: 12, color: color),
                                    const SizedBox(width: 6),
                                    Text(
                                      isUp ? 'متاح' : 'غير متاح',
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  host,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const Spacer(),
                                Text(
                                  bestPort == null
                                      ? 'البورت: غير متاح'
                                      : 'أفضل بورت: $bestPort$latencyLabel',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
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
}

class _BrowserTab {
  const _BrowserTab({
    required this.title,
    required this.url,
    this.pinned = false,
    this.isDashboard = false,
  });

  final String title;
  final String url;
  final bool pinned;
  final bool isDashboard;

  _BrowserTab copyWith({
    String? title,
    String? url,
    bool? pinned,
    bool? isDashboard,
  }) {
    return _BrowserTab(
      title: title ?? this.title,
      url: url ?? this.url,
      pinned: pinned ?? this.pinned,
      isDashboard: isDashboard ?? this.isDashboard,
    );
  }
}

class _HistoryItem {
  const _HistoryItem({
    required this.url,
    required this.title,
    required this.at,
  });

  final String url;
  final String title;
  final DateTime at;
}

enum _DownloadJobStatus { queued, downloading, completed, failed }

class _DownloadJob {
  const _DownloadJob({
    required this.id,
    required this.url,
    required this.fileName,
    required this.targetDirectory,
    required this.status,
    required this.progress,
    this.error,
    this.savedPath,
  });

  final String id;
  final Uri url;
  final String fileName;
  final String targetDirectory;
  final _DownloadJobStatus status;
  final double progress;
  final String? error;
  final String? savedPath;

  _DownloadJob copyWith({
    _DownloadJobStatus? status,
    double? progress,
    String? error,
    String? savedPath,
  }) {
    return _DownloadJob(
      id: id,
      url: url,
      fileName: fileName,
      targetDirectory: targetDirectory,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error,
      savedPath: savedPath ?? this.savedPath,
    );
  }
}

class _BookmarkItem {
  const _BookmarkItem({required this.title, required this.url});

  final String title;
  final String url;
}

class _SavedCredential {
  const _SavedCredential({
    required this.host,
    required this.username,
    required this.password,
    required this.updatedAt,
  });

  final String host;
  final String username;
  final String password;
  final DateTime updatedAt;
}

class _SitePermission {
  const _SitePermission({
    required this.host,
    required this.notifications,
    required this.cookies,
    required this.popups,
  });

  final String host;
  final String notifications; // ask | allow | block
  final String cookies; // allow | block
  final String popups; // allow | block

  _SitePermission copyWith({
    String? host,
    String? notifications,
    String? cookies,
    String? popups,
  }) {
    return _SitePermission(
      host: host ?? this.host,
      notifications: notifications ?? this.notifications,
      cookies: cookies ?? this.cookies,
      popups: popups ?? this.popups,
    );
  }
}

class _DashboardServerState {
  const _DashboardServerState({
    required this.isUp,
    required this.bestUri,
    this.latencyMs,
  });

  final bool isUp;
  final Uri? bestUri;
  final int? latencyMs;
}
