import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/formatters.dart';
import '../../../core/network/ip_address_utils.dart';
import '../../../features/admin/models/update_management_models.dart';
import '../../../shared/models/admin_announcement.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/managed_user.dart';
import '../../../shared/models/remote_document.dart';
import '../../../shared/models/document_folder.dart';
import '../../../shared/services/document_folder_service.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/lan_file_transfer_service.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;
import '../../../shared/widgets/app_loading_placeholders.dart';
import '../../../shared/widgets/button_loading_indicator.dart';
import '../../../shared/widgets/desktop_workspace_sidebar.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../../updates/presentation/update_center_screen.dart';

class FilesDashboardScreen extends ConsumerStatefulWidget {
  const FilesDashboardScreen({super.key, this.isWrapped = false});

  final bool isWrapped;

  @override
  ConsumerState<FilesDashboardScreen> createState() =>
      _FilesDashboardScreenState();
}

class _FilesDashboardScreenState extends ConsumerState<FilesDashboardScreen> {
  static const int _adminTransferMaxBytes = 200 * 1024 * 1024;
  static const int _userTransferMaxBytes = 30 * 1024 * 1024;
  static const int _lanTransferMaxBytes = 500 * 1024 * 1024;
  final _searchController = TextEditingController();
  bool _latestFirst = true;
  bool _isGridView = false;
  String? _currentFolderId;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  String? _downloadingFileName;
  final Set<String> _openingDocuments = <String>{};
  bool _sendingToMobile = false;
  bool _preparingLanDesktopSend = false;
  bool _sendingToLanDesktop = false;
  bool _showOutgoingTransferBanner = false;
  double _outgoingTransferProgress = 0;
  String? _outgoingTransferFileName;
  String _outgoingTransferStatus = '';
  String _outgoingTransferTarget = 'الموبايل';
  List<String> _localLanIps = const <String>[];
  List<Map<String, dynamic>> _pendingLanReceiveRequests =
      const <Map<String, dynamic>>[];

  void _goBack() {
    if (_currentFolderId == null) return;
    final folders = ref.read(documentFoldersProvider).valueOrNull ?? [];
    final currentFolder = folders.where((f) => f.id == _currentFolderId).firstOrNull;
    setState(() {
      _currentFolderId = currentFolder?.parentId;
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_refreshLocalLanIps());
    if (kIsWeb && web_bridge.isElectron()) {
      web_bridge.setElectronLanTransferProgressHandler(
        _handleElectronLanTransferProgress,
      );
      web_bridge.setElectronLanReceivePendingHandler((requests) {
        if (mounted) {
          setState(() => _pendingLanReceiveRequests = requests);
        }
      });
      unawaited(_refreshPendingLanReceiveRequests());
    }
  }

  @override
  void dispose() {
    if (kIsWeb && web_bridge.isElectron()) {
      web_bridge.setElectronLanTransferProgressHandler(null);
      web_bridge.setElectronLanReceivePendingHandler(null);
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('فولدر جديد'),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'اسم الفولدر', prefixIcon: Icon(Icons.folder_outlined))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('إنشاء')),
      ],
    ));
    if (name == null || name.isEmpty) return;
    if (!mounted) return;
    final color = Colors.primaries[Random().nextInt(Colors.primaries.length)].value;
    await ref.read(documentFoldersProvider.notifier).createFolder(name, parentId: _currentFolderId, colorValue: color);
  }
  Future<void> _renameFolder(DocumentFolder folder) async {
    final controller = TextEditingController(text: folder.name);
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('إعادة تسمية الفولدر'),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'اسم الفولدر')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('حفظ')),
      ],
    ));
    if (name == null || name.isEmpty) return;
    if (!mounted) return;
    await ref.read(documentFoldersProvider.notifier).renameFolder(folder.id, name);
  }
  Future<void> _deleteFolder(DocumentFolder folder) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('حذف الفولدر'),
      content: Text('سيتم حذف الفولدر «${folder.name}» والملفات ستعود للقائمة الرئيسية.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
      ],
    ));
    if (confirm != true) return;
    if (!mounted) return;
    await ref.read(documentFoldersProvider.notifier).deleteFolder(folder.id);
    if (mounted && _currentFolderId == folder.id) setState(() => _currentFolderId = null);
  }
  Future<void> _showMoveFolderPicker(String documentId) async {
    final folders = ref.read(documentFoldersProvider).valueOrNull ?? [];
    if (folders.isEmpty) return;
    final targetFolderId = await showModalBottomSheet<String>(context: context, builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('اختر الفولدر', style: TextStyle(fontWeight: FontWeight.w800))),
        ...folders.map((f) => ListTile(title: Text(f.name), onTap: () => Navigator.pop(ctx, f.id))),
      ])
    ));
    if (targetFolderId == null) return;
    if (!mounted) return;
    await ref.read(documentFoldersProvider.notifier).moveDocumentToFolder(documentId, targetFolderId);
  }
  Future<void> _removeDocumentFromFolder(String documentId) async {
    await ref.read(documentFoldersProvider.notifier).removeDocumentFromFolder(documentId);
  }


  Future<void> _refreshPendingLanReceiveRequests() async {
    if (!kIsWeb || !web_bridge.isElectron()) {
      return;
    }
    final requests = await web_bridge.getPendingElectronLanReceiveRequests();
    if (!mounted) {
      return;
    }
    setState(() => _pendingLanReceiveRequests = requests);
  }

  Future<void> _openPendingLanReceiveDialog() async {
    if (!kIsWeb || !web_bridge.isElectron()) {
      return;
    }
    final requestId = _pendingLanReceiveRequests.isEmpty
        ? null
        : _pendingLanReceiveRequests.first['requestId']?.toString();
    await web_bridge.openPendingElectronLanReceiveDialog(requestId);
    await _refreshPendingLanReceiveRequests();
  }

  Future<void> _openTransferCenter({required bool isAdmin}) async {
    if (!kIsWeb || !web_bridge.isElectron()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مركز النقل متاح في نسخة Electron فقط.')),
      );
      return;
    }
    var state = await web_bridge.getElectronTransferCenterState();
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final transfers = (state['transfers'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList()
              .reversed
              .toList();
          final inbox = (state['inbox'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList()
              .reversed
              .toList();
          final auditLogs = (state['auditLogs'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList()
              .reversed
              .toList();
          final notifications =
              (state['notifications'] as List<dynamic>? ?? const [])
                  .whereType<Map>()
                  .map((entry) => Map<String, dynamic>.from(entry))
                  .toList()
                  .reversed
                  .toList();
          final policy = Map<String, dynamic>.from(
            state['policy'] as Map? ?? const <String, dynamic>{},
          );
          return AlertDialog(
            title: const Text('مركز النقل'),
            content: SizedBox(
              width: 920,
              height: 620,
              child: DefaultTabController(
                length: isAdmin ? 5 : 4,
                child: Column(
                  children: [
                    TabBar(
                      isScrollable: true,
                      tabs: [
                        const Tab(text: 'العمليات'),
                        const Tab(text: 'Inbox'),
                        const Tab(text: 'Audit Log'),
                        Tab(text: 'الإشعارات (${notifications.length})'),
                        if (isAdmin) const Tab(text: 'السياسات'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _TransferCenterList(
                            emptyText: 'لا توجد عمليات نقل مسجلة.',
                            items: transfers,
                            trailingBuilder: null,
                          ),
                          _TransferCenterList(
                            emptyText: 'لا توجد ملفات مستلمة بعد.',
                            items: inbox,
                            trailingBuilder: (item) {
                              final savedPath = item['savedPath']?.toString();
                              return TextButton.icon(
                                onPressed:
                                    savedPath == null || savedPath.isEmpty
                                    ? null
                                    : () => web_bridge
                                          .openElectronInboxFileLocation(
                                            savedPath,
                                          ),
                                icon: const Icon(Icons.folder_open_rounded),
                                label: const Text('فتح المكان'),
                              );
                            },
                          ),
                          _TransferCenterList(
                            emptyText: 'لا توجد أحداث تدقيق.',
                            items: auditLogs,
                            trailingBuilder: null,
                          ),
                          _TransferCenterList(
                            emptyText: 'لا توجد إشعارات.',
                            items: notifications,
                            trailingBuilder: null,
                          ),
                          if (isAdmin)
                            _TransferPolicyEditor(
                              policy: policy,
                              onSave: (nextPolicy) async {
                                state = await web_bridge
                                    .updateElectronTransferPolicy(nextPolicy);
                                setDialogState(() {});
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  state = await web_bridge.getElectronTransferCenterState();
                  setDialogState(() {});
                },
                child: const Text('تحديث'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('إغلاق'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _handleElectronLanTransferProgress(Map<String, dynamic> event) {
    if (!mounted) {
      return;
    }
    final fileName = event['fileName']?.toString().trim();
    final peerLabel = event['peerLabel']?.toString().trim();
    final direction = event['direction']?.toString();
    final stage = event['stage']?.toString();
    final rawProgress = event['progress'];
    final progress = rawProgress is num
        ? rawProgress.toDouble()
        : double.tryParse(rawProgress?.toString() ?? '') ?? 0;
    final fallbackStatus = direction == 'incoming'
        ? 'جاري استقبال الملف ${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%'
        : 'جاري إرسال الملف ${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%';
    final status = event['message']?.toString().trim().isNotEmpty == true
        ? event['message'].toString()
        : fallbackStatus;
    _showOutgoingTransfer(
      fileName: fileName == null || fileName.isEmpty ? 'file' : fileName,
      targetLabel: peerLabel == null || peerLabel.isEmpty
          ? (direction == 'incoming' ? 'جهاز على الشبكة' : 'الجهاز الآخر')
          : peerLabel,
      progress: progress,
      status: status,
    );
    if (stage == 'completed' || stage == 'failed') {
      Future<void>.delayed(const Duration(seconds: 3), _clearOutgoingTransfer);
    }
  }

  Future<void> _refreshLocalLanIps() async {
    if (kIsWeb) {
      if (!web_bridge.isElectron()) {
        return;
      }
      final deviceInfo = await web_bridge.getElectronDeviceInfo();
      final ips =
          (deviceInfo['localIps'] as List<dynamic>? ?? const <dynamic>[])
              .map((entry) => normalizeIpAddress(entry.toString()))
              .where((entry) => entry.isNotEmpty)
              .toList();
      if (!mounted) {
        return;
      }
      setState(() => _localLanIps = ips);
      return;
    }
    final service = ref.read(lanFileTransferServiceProvider);
    final ips = await service.refreshLocalIpv4s();
    if (!mounted) {
      return;
    }
    setState(() => _localLanIps = ips);
  }

  Future<List<LanDiscoveredPeer>> _discoverLanPeersOnLocalNetworks() async {
    if (kIsWeb) {
      if (!web_bridge.isElectron()) {
        return const <LanDiscoveredPeer>[];
      }
      final peers = await web_bridge.discoverElectronLanPeers().timeout(
        const Duration(milliseconds: 2500),
      );
      return peers
          .map((peer) {
            final ip = normalizeIpAddress(
              peer['ip']?.toString() ?? peer['peerIp']?.toString(),
            );
            if (ip.isEmpty) {
              return null;
            }
            final peerIps = (peer['ips'] as List<dynamic>? ?? const <dynamic>[])
                .map((entry) => normalizeIpAddress(entry.toString()))
                .where((entry) => entry.isNotEmpty)
                .toList();
            return LanDiscoveredPeer(ip: ip, peerIps: peerIps);
          })
          .whereType<LanDiscoveredPeer>()
          .toList();
    }
    return ref
        .read(lanFileTransferServiceProvider)
        .discoverPeersOnLocalNetworks()
        .timeout(const Duration(milliseconds: 2500));
  }

  String _ipv4SubnetKey(String rawIp) {
    final normalized = normalizeIpAddress(rawIp);
    final parts = normalized.split('.');
    if (parts.length != 4) {
      return '';
    }
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }

  List<BranchPeerDevice> _filterPeersOnSameNetwork(
    List<BranchPeerDevice> peers,
  ) {
    final localSubnets = _localLanIps
        .map(_ipv4SubnetKey)
        .where((entry) => entry.isNotEmpty)
        .toSet();
    if (localSubnets.isEmpty) {
      return peers;
    }

    final sameNetwork = peers.where((peer) {
      final subnet = _ipv4SubnetKey(peer.localIp ?? '');
      return subnet.isNotEmpty && localSubnets.contains(subnet);
    }).toList();

    return sameNetwork.isNotEmpty ? sameNetwork : peers;
  }

  List<BranchPeerDevice> _sortPeers(List<BranchPeerDevice> peers) {
    final items = List<BranchPeerDevice>.from(peers);
    items.sort((a, b) => a.displayLabel.compareTo(b.displayLabel));
    return items;
  }

  List<BranchPeerDevice> _mergeDiscoveredPeers({
    required List<BranchPeerDevice> branchPeers,
    required List<LanDiscoveredPeer> discoveredPeers,
    required String branchCode,
  }) {
    final merged = <String, BranchPeerDevice>{};
    for (final peer in branchPeers) {
      final ip = normalizeIpAddress(peer.localIp);
      if (ip.isEmpty) {
        continue;
      }
      merged[ip] = peer;
    }
    for (final discovered in discoveredPeers) {
      final ip = normalizeIpAddress(discovered.ip);
      if (ip.isEmpty || merged.containsKey(ip)) {
        continue;
      }
      merged[ip] = BranchPeerDevice(
        id: 'lan-$ip',
        deviceUid: 'lan-$ip',
        deviceName: 'جهاز على الشبكة',
        hostName: null,
        localIp: ip,
        branchCode: branchCode,
        appVersion: 'lan',
        connectionStatus: 'online',
        lastKnownUserId: null,
        lastKnownUsername: null,
        lastKnownFullName: null,
        lastHeartbeatAt: null,
      );
    }
    return _sortPeers(_filterPeersOnSameNetwork(merged.values.toList()));
  }

  List<RemoteDocument> _filterAndSort(List<RemoteDocument> documents, List<DocumentFolder> folders) {
    final query = _searchController.text.trim().toLowerCase();

    // Collect ALL document IDs that are inside any folder
    final allFolderDocIds = <String>{};
    for (final f in folders) {
      allFolderDocIds.addAll(f.documentIds);
    }

    List<RemoteDocument> filtered;
    if (query.isNotEmpty) {
      // Search mode: search ALL documents regardless of folder
      filtered = documents
          .where((d) => d.fileName.toLowerCase().contains(query))
          .toList();
    } else if (_currentFolderId != null) {
      // Inside a folder: show only documents belonging to this folder
      final currentFolder = folders.where((f) => f.id == _currentFolderId).firstOrNull;
      if (currentFolder != null) {
        final docIds = currentFolder.documentIds.toSet();
        filtered = documents.where((d) => docIds.contains(d.id)).toList();
      } else {
        filtered = [];
      }
    } else {
      // Root level: show only documents NOT inside any folder
      filtered = documents.where((d) => !allFolderDocIds.contains(d.id)).toList();
    }

    filtered.sort(
      (a, b) => _latestFirst
          ? b.createdAt.compareTo(a.createdAt)
          : a.createdAt.compareTo(b.createdAt),
    );
    return filtered;
  }

  Future<void> _openDocument(RemoteDocument document) async {
    final docId = document.id;
    if (_openingDocuments.contains(docId)) return;
    _openingDocuments.add(docId);

    try {
      if (mounted) {
        setState(() {
          _isDownloading = true;
          _downloadProgress = 0;
          _downloadingFileName = document.fileName;
        });
      }
      final filePath = await ref
          .read(documentRepositoryProvider)
          .downloadDocument(
            document,
            onProgress: (received, total) {
              if (!mounted) return;
              setState(() {
                _downloadProgress = total <= 0
                    ? 0
                    : (received / total).clamp(0, 1).toDouble();
              });
            },
          );
      if (kIsWeb && web_bridge.isElectron()) {
        final opened = await web_bridge.openElectronLocalFile(filePath);
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر فتح الملف المحلي.')),
          );
        }
      } else if (!kIsWeb) {
        await OpenFilex.open(filePath);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      _openingDocuments.remove(docId);
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0;
          _downloadingFileName = null;
        });
      }
    }
  }

  Future<void> _printDocument(RemoteDocument document) async {
    if (!mounted) return;
    try {
      final prefs = ref.read(userPreferencesControllerProvider).valueOrNull;
      final docRepository = ref.read(documentRepositoryProvider);
      final printService = ref.read(desktopPrintServiceProvider);
      final bytes = await docRepository.fetchDocumentBytes(document);
      final result = await printService.executePrintJob({
            'fileName': document.fileName,
            'mimeType': 'application/pdf',
            'inlineFileBase64': base64Encode(bytes),
            'source': 'desktop_files',
          }, preferredPrinterName: prefs?.preferredPrinterName);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _renameDocument(RemoteDocument document) async {
    final controller = TextEditingController(text: document.fileName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعادة تسمية الملف'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'اسم الملف'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    try {
      final docRepository = ref.read(documentRepositoryProvider);
      final docsController = ref.read(documentsControllerProvider.notifier);
      await docRepository.renameDocument(document.id, result);
      await docsController.refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteDocument(RemoteDocument document) async {
    final shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('حذف الملف'),
            content: Text('هل تريد حذف "${document.fileName}"؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حذف'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldDelete || !mounted) return;
    try {
      final docRepository = ref.read(documentRepositoryProvider);
      final docsController = ref.read(documentsControllerProvider.notifier);
      await docRepository.deleteDocument(document.id);
      await docsController.refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _goToChat() => ref.read(activeSectionProvider.notifier).state = DesktopWorkspaceSection.chat;

  void _goToAdminPanel() => ref.read(activeSectionProvider.notifier).state = DesktopWorkspaceSection.admin;

  void _goToTicketsPanel() => ref.read(activeSectionProvider.notifier).state = DesktopWorkspaceSection.tickets;

  void _goToProfile() => ref.read(activeSectionProvider.notifier).state = DesktopWorkspaceSection.profile;

  void _goToServers() => ref.read(activeSectionProvider.notifier).state = DesktopWorkspaceSection.servers;

  void _showOutgoingTransfer({
    required String fileName,
    required String targetLabel,
    required double progress,
    required String status,
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      _showOutgoingTransferBanner = true;
      _outgoingTransferFileName = fileName;
      _outgoingTransferTarget = targetLabel;
      _outgoingTransferProgress = progress.clamp(0, 1).toDouble();
      _outgoingTransferStatus = status;
    });
  }

  void _clearOutgoingTransfer() {
    if (!mounted) {
      return;
    }
    setState(() {
      _showOutgoingTransferBanner = false;
      _outgoingTransferProgress = 0;
      _outgoingTransferFileName = null;
      _outgoingTransferStatus = '';
      _outgoingTransferTarget = 'الموبايل';
    });
  }

  Duration _uploadTimeoutForBytes(int bytes) {
    final megaBytes = bytes / (1024 * 1024);
    final minutes = megaBytes <= 8 ? 2 : (2 + (megaBytes / 12).ceil());
    return Duration(minutes: minutes.clamp(2, 15));
  }

  Future<Map<String, dynamic>> _uploadTemporaryTransfer({
    String? filePath,
    Uint8List? fileBytes,
    required String fileName,
    required int fileSizeBytes,
    required String source,
    void Function(int sent, int total)? onProgress,
  }) async {
    final multipartFile = fileBytes != null
        ? MultipartFile.fromBytes(fileBytes, filename: fileName)
        : await MultipartFile.fromFile(filePath!, filename: fileName);
    final formData = FormData.fromMap({
      'fileName': fileName,
      'source': source,
      'file': multipartFile,
    });
    final timeout = _uploadTimeoutForBytes(fileSizeBytes);
    final response = await ref
        .read(authenticatedApiClientProvider)
        .dio
        .post<Map<String, dynamic>>(
          '/api/chat/transfers',
          data: formData,
          options: Options(
            contentType: 'multipart/form-data',
            connectTimeout: timeout,
            sendTimeout: timeout,
            receiveTimeout: timeout,
          ),
          onSendProgress: onProgress,
        );
    final payload = response.data ?? const <String, dynamic>{};
    final data = payload['data'] is Map<String, dynamic>
        ? payload['data'] as Map<String, dynamic>
        : (payload['data'] is Map
              ? Map<String, dynamic>.from(payload['data'] as Map)
              : payload);
    final transfer = data['transfer'] is Map<String, dynamic>
        ? data['transfer'] as Map<String, dynamic>
        : Map<String, dynamic>.from(data['transfer'] as Map? ?? const {});
    if ((transfer['id']?.toString().trim().isEmpty ?? true)) {
      throw Exception('تعذر تجهيز نقل الملف للموبايل.');
    }
    return transfer;
  }

  Future<void> _sendFileToMobile(AppUser user) async {
    if (_sendingToMobile) return;
    StreamSubscription? progressSubscription;
    setState(() => _sendingToMobile = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: kIsWeb,
      );
      final pickedFile = picked?.files.single;
      if (pickedFile == null) return;
      final filePath = picked?.files.single.path;
      final fileBytes = pickedFile.bytes;
      if (!kIsWeb && (filePath == null || filePath.isEmpty)) return;

      final size = kIsWeb
          ? (pickedFile.size > 0 ? pickedFile.size : (fileBytes?.length ?? 0))
          : await File(filePath!).length();
      final maxAllowed = user.role == 'admin'
          ? _adminTransferMaxBytes
          : _userTransferMaxBytes;
      if (size > maxAllowed) {
        if (!mounted) return;
        final maxLabel = user.role == 'admin' ? '200 ميجا' : '30 ميجا';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حجم الملف أكبر من الحد المسموح ($maxLabel).'),
          ),
        );
        return;
      }

      final fileName = pickedFile.name.isNotEmpty
          ? pickedFile.name
          : (kIsWeb ? 'file' : File(filePath!).uri.pathSegments.last);
      _showOutgoingTransfer(
        fileName: fileName,
        targetLabel: 'الموبايل',
        progress: 0.04,
        status: 'جارٍ تجهيز الملف للإرسال...',
      );
      final transfer = await _uploadTemporaryTransfer(
        filePath: filePath,
        fileBytes: fileBytes,
        fileName: fileName,
        fileSizeBytes: size,
        source: 'desktop_send_to_mobile',
        onProgress: (sent, total) {
          final ratio = total <= 0
              ? 0.0
              : (sent / total).clamp(0, 1).toDouble();
          _showOutgoingTransfer(
            fileName: fileName,
            targetLabel: 'الموبايل',
            progress: 0.06 + (ratio * 0.56),
            status: 'جارٍ رفع الملف إلى الخادم...',
          );
        },
      );
      _showOutgoingTransfer(
        fileName: fileName,
        targetLabel: 'الموبايل',
        progress: 0.66,
        status: 'جارٍ إرسال طلب الاستلام إلى الموبايل...',
      );
      final ack = await ref
          .read(chatSocketServiceProvider)
          .emitWithAck('file_receive_request', {
            'transferId': transfer['id']?.toString(),
            'source': 'desktop_send_to_mobile',
          }, timeout: const Duration(seconds: 45));
      final ackOk = ack['ok'] == true && ack['success'] == true;
      final ackData = ack['data'] is Map<String, dynamic>
          ? ack['data'] as Map<String, dynamic>
          : Map<String, dynamic>.from(ack['data'] as Map? ?? const {});
      final jobId = ackData['jobId']?.toString();
      if (!ackOk || jobId == null || jobId.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ack['error']?.toString() ?? 'تعذر إرسال الملف إلى الموبايل.',
            ),
          ),
        );
        return;
      }

      _showOutgoingTransfer(
        fileName: fileName,
        targetLabel: 'الموبايل',
        progress: 0.72,
        status: 'تم إرسال الطلب، بانتظار موافقة الموبايل...',
      );
      final socket = ref.read(chatSocketServiceProvider);
      final completer = Completer<Map<String, dynamic>>();
      progressSubscription = socket.events.listen((event) {
        final eventJobId = event.payload['jobId']?.toString();
        if (eventJobId != jobId) {
          return;
        }
        if (event.type == 'file_receive_progress') {
          final progress = (event.payload['progress'] as num?)?.toDouble() ?? 0;
          final message =
              event.payload['message']?.toString().trim().isNotEmpty == true
              ? event.payload['message'].toString().trim()
              : 'جارٍ إرسال الملف للموبايل...';
          _showOutgoingTransfer(
            fileName: fileName,
            targetLabel: 'الموبايل',
            progress: 0.72 + (progress.clamp(0, 1) * 0.28),
            status: message,
          );
        } else if (event.type == 'file_receive_status' &&
            !completer.isCompleted) {
          completer.complete(event.payload);
        }
      });

      final status = await completer.future.timeout(
        const Duration(minutes: 10),
      );
      await progressSubscription.cancel();
      progressSubscription = null;
      if (!mounted) return;
      final success = status['success'] == true;
      final message = status['message']?.toString().trim();
      _showOutgoingTransfer(
        fileName: fileName,
        targetLabel: 'الموبايل',
        progress: 1,
        status: message?.isNotEmpty == true
            ? message!
            : (success
                  ? 'تم إرسال الملف للموبايل وحفظه بنجاح.'
                  : 'فشل حفظ الملف على الموبايل.'),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message?.isNotEmpty == true
                ? message!
                : (success
                      ? 'تم إرسال الملف للموبايل وحفظه بنجاح.'
                      : 'فشل حفظ الملف على الموبايل.'),
          ),
        ),
      );
    } on TimeoutException {
      if (!mounted) return;
      _showOutgoingTransfer(
        fileName: _outgoingTransferFileName ?? 'ملف',
        targetLabel: 'الموبايل',
        progress: 1,
        status: 'انتهت مهلة انتظار رد الموبايل.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('انتهت مهلة انتظار رد الموبايل.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showOutgoingTransfer(
        fileName: _outgoingTransferFileName ?? 'ملف',
        targetLabel: 'الموبايل',
        progress: 1,
        status: error.toString(),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      await progressSubscription?.cancel();
      if (mounted) {
        setState(() => _sendingToMobile = false);
        Future<void>.delayed(
          const Duration(seconds: 3),
          _clearOutgoingTransfer,
        );
      }
    }
  }

  Future<void> _sendFileToLanDesktop(AppUser user) async {
    if (_preparingLanDesktopSend || _sendingToLanDesktop) {
      return;
    }
    setState(() => _preparingLanDesktopSend = true);
    final ipController = TextEditingController();
    LanPeerProbeResult? probeResult;
    List<BranchPeerDevice> branchPeers = const <BranchPeerDevice>[];
    List<BranchPeerDevice> availablePeers = const <BranchPeerDevice>[];
    BranchPeerDevice? selectedPeer;
    String? branchPeersError;
    bool filteredToSameNetwork = false;
    try {
      try {
        unawaited(
          ref
              .read(desktopUpdateAgentProvider)
              .checkNow()
              .timeout(const Duration(seconds: 2))
              .catchError((_) {}),
        );
        branchPeers = await ref
            .read(updateManagementRepositoryProvider)
            .listBranchPeerDevices(branchCode: user.branchCode)
            .timeout(const Duration(seconds: 4));
        availablePeers = _sortPeers(_filterPeersOnSameNetwork(branchPeers));
        if (availablePeers.isEmpty && _localLanIps.isNotEmpty) {
          try {
            final discoveredPeers = await _discoverLanPeersOnLocalNetworks();
            if (discoveredPeers.isNotEmpty) {
              availablePeers = _mergeDiscoveredPeers(
                branchPeers: branchPeers,
                discoveredPeers: discoveredPeers,
                branchCode: user.branchCode,
              );
            }
          } catch (_) {}
        }
        filteredToSameNetwork =
            branchPeers.isNotEmpty &&
            availablePeers.length < branchPeers.length;
      } catch (error) {
        branchPeers = const <BranchPeerDevice>[];
        branchPeersError = error.toString();
        if (_localLanIps.isNotEmpty) {
          try {
            final discoveredPeers = await _discoverLanPeersOnLocalNetworks();
            availablePeers = _mergeDiscoveredPeers(
              branchPeers: const <BranchPeerDevice>[],
              discoveredPeers: discoveredPeers,
              branchCode: user.branchCode,
            );
          } catch (_) {
            availablePeers = const <BranchPeerDevice>[];
          }
        } else {
          availablePeers = const <BranchPeerDevice>[];
        }
      }
      if (!mounted) {
        return;
      }
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('إرسال ملف لجهاز على الشبكة'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (branchPeersError != null &&
                    branchPeersError.trim().isNotEmpty) ...[
                  Text(
                    'تعذر تحميل أجهزة الفرع الآن: ${branchPeersError.trim()}',
                    style: Theme.of(dialogContext).textTheme.bodySmall
                        ?.copyWith(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (availablePeers.isNotEmpty) ...[
                  if (_localLanIps.isNotEmpty) ...[
                    Text(
                      filteredToSameNetwork
                          ? 'تم عرض الأجهزة الموجودة على نفس الشبكة الحالية فقط.'
                          : 'سيتم عرض الأجهزة المتاحة حسب عناوين الشبكة المحلية المسجلة.',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: null,
                    decoration: const InputDecoration(
                      labelText: 'اختر جهازًا من نفس الفرع',
                    ),
                    items: availablePeers
                        .map(
                          (peer) => DropdownMenuItem<String>(
                            value: peer.deviceUid,
                            child: Text(
                              peer.displayLabel,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      BranchPeerDevice? peer;
                      for (final entry in availablePeers) {
                        if (entry.deviceUid == value) {
                          peer = entry;
                          break;
                        }
                      }
                      final targetIp = normalizeIpAddress(peer?.localIp);
                      setDialogState(() {
                        selectedPeer = peer;
                        ipController.text = targetIp;
                        probeResult = const LanPeerProbeResult(
                          success: false,
                          message: 'جارٍ فحص الاتصال بالجهاز المحدد...',
                          peerIp: '',
                        );
                      });
                      if (targetIp.isEmpty) {
                        setDialogState(() {
                          probeResult = const LanPeerProbeResult(
                            success: false,
                            message:
                                'هذا الجهاز لا يملك عنوان IP صالحًا حاليًا.',
                            peerIp: '',
                          );
                        });
                        return;
                      }
                      unawaited(() async {
                        final result = await _probeLanTargetIp(targetIp);
                        if (!dialogContext.mounted) {
                          return;
                        }
                        setDialogState(() {
                          if (selectedPeer?.deviceUid == peer?.deviceUid &&
                              ipController.text.trim() == targetIp) {
                            probeResult = result;
                          }
                        });
                      }());
                    },
                  ),
                  const SizedBox(height: 10),
                ] else ...[
                  Text(
                    'لم يتم العثور على أجهزة ديسكتوب فعالة في هذا الفرع حاليًا. تأكد أن الجهاز الآخر فتح التطبيق وسجل دخوله مؤخرًا.',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: ipController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'IP الجهاز الآخر',
                    hintText: 'مثال: 192.168.1.15',
                  ),
                  onChanged: (_) {
                    setDialogState(() {
                      probeResult = null;
                      if (selectedPeer != null &&
                          ipController.text.trim() !=
                              normalizeIpAddress(selectedPeer?.localIp)) {
                        selectedPeer = null;
                      }
                    });
                  },
                ),
                if (_localLanIps.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'عناوين هذا الجهاز: ${_localLanIps.join(' , ')}',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'الخطوة الأولى: فحص الاتصال بالجهاز الآخر قبل اختيار الملف.',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final targetIp = ipController.text.trim();
                          if (targetIp.isEmpty) {
                            setDialogState(() {
                              probeResult = const LanPeerProbeResult(
                                success: false,
                                message: 'أدخل عنوان IP أولًا.',
                                peerIp: '',
                              );
                            });
                            return;
                          }
                          setDialogState(() {
                            probeResult = const LanPeerProbeResult(
                              success: false,
                              message: 'جارٍ فحص الاتصال...',
                              peerIp: '',
                            );
                          });
                          final result = await _probeLanTargetIp(targetIp);
                          if (!dialogContext.mounted) {
                            return;
                          }
                          setDialogState(() => probeResult = result);
                        },
                        icon: const Icon(Icons.wifi_find_rounded),
                        label: const Text('فحص الاتصال'),
                      ),
                    ),
                  ],
                ),
                if (probeResult != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:
                          (probeResult!.success
                                  ? const Color(0xFF19A974)
                                  : Theme.of(dialogContext).colorScheme.error)
                              .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            (probeResult!.success
                                    ? const Color(0xFF19A974)
                                    : Theme.of(dialogContext).colorScheme.error)
                                .withValues(alpha: 0.22),
                      ),
                    ),
                    child: Text(
                      probeResult!.message,
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'الحد الأقصى للنقل المحلي المباشر: ${formatFileSize(_lanTransferMaxBytes)}.',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: probeResult?.success == true
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: const Text('اختيار الملف'),
              ),
            ],
          ),
        ),
      );
      if (approved != true) {
        return;
      }

      if (ipController.text.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أدخل عنوان IP للجهاز الآخر أولًا.')),
        );
        return;
      }

      final targetIp = normalizeIpAddress(
        probeResult?.peerIp ?? ipController.text.trim(),
      );
      final targetLabel = selectedPeer?.displayLabel ?? targetIp;
      final senderName = user.fullName.trim().isNotEmpty
          ? user.fullName.trim()
          : user.username;

      if (kIsWeb && web_bridge.isElectron()) {
        setState(() {
          _preparingLanDesktopSend = false;
          _sendingToLanDesktop = true;
        });
        final result = await _sendElectronFileToLanIp(
          targetIp: targetIp,
          senderName: senderName,
          senderBranchCode: user.branchCode,
          receiverBranchCode: selectedPeer?.branchCode,
          targetLabel: targetLabel,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
        return;
      }

      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: kIsWeb,
      );
      final pickedFile = picked?.files.single;
      if (pickedFile == null) {
        return;
      }
      final filePath = picked?.files.single.path;
      final fileBytes = pickedFile.bytes;
      if (!kIsWeb && (filePath == null || filePath.isEmpty)) {
        return;
      }
      if (kIsWeb && (fileBytes == null || fileBytes.isEmpty)) {
        return;
      }
      final fileSize = kIsWeb
          ? pickedFile.size
          : await File(filePath!).length();
      if (fileSize > _lanTransferMaxBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حجم الملف أكبر من الحد المسموح للنقل المحلي (${formatFileSize(_lanTransferMaxBytes)}).',
            ),
          ),
        );
        return;
      }

      final fileName = pickedFile.name.isNotEmpty
          ? pickedFile.name
          : (kIsWeb ? 'file' : p.basename(filePath!));
      setState(() {
        _preparingLanDesktopSend = false;
        _sendingToLanDesktop = true;
      });
      _showOutgoingTransfer(
        fileName: fileName,
        targetLabel: targetLabel,
        progress: 0.04,
        status: 'تم الاتصال. جارٍ تجهيز النقل عبر الشبكة المحلية...',
      );

      final result = kIsWeb
          ? await _sendWebFileToLanIp(
              targetIp: targetIp,
              fileName: fileName,
              fileBytes: fileBytes!,
              senderName: senderName,
              targetLabel: targetLabel,
            )
          : await ref
                .read(lanFileTransferServiceProvider)
                .sendFileToIp(
                  targetIp: targetIp,
                  filePath: filePath!,
                  senderName: senderName,
                  onProgress: (event) {
                    _showOutgoingTransfer(
                      fileName: event.fileName,
                      targetLabel:
                          selectedPeer?.displayLabel ??
                          event.peerIp ??
                          targetIp,
                      progress: event.progress,
                      status: event.message ?? 'جارٍ النقل...',
                    );
                  },
                );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    } finally {
      ipController.dispose();
      if (mounted) {
        setState(() {
          _preparingLanDesktopSend = false;
          _sendingToLanDesktop = false;
        });
        Future<void>.delayed(
          const Duration(seconds: 3),
          _clearOutgoingTransfer,
        );
      }
    }
  }

  Future<LanSendFileResult> _sendElectronFileToLanIp({
    required String targetIp,
    required String senderName,
    String? senderBranchCode,
    String? receiverBranchCode,
    required String targetLabel,
  }) async {
    final progressToken =
        'lan-${DateTime.now().microsecondsSinceEpoch}-${targetIp.hashCode}';
    _showOutgoingTransfer(
      fileName: 'file',
      targetLabel: targetLabel,
      progress: 0.02,
      status:
          'اختر الملف، ثم سيتم انتظار قبول الجهاز الآخر أو تحديد مكان الحفظ بدون استعجال...',
    );
    try {
      final result = await web_bridge.pickAndSendElectronLanFile(
        targetIp: targetIp,
        senderName: senderName,
        maxBytes: _lanTransferMaxBytes,
        progressToken: progressToken,
        senderBranchCode: senderBranchCode,
        receiverBranchCode: receiverBranchCode,
      );
      final canceled = result['canceled'] == true;
      final success = result['success'] == true;
      final fileName = result['fileName']?.toString().trim();
      if (fileName != null && fileName.isNotEmpty) {
        _showOutgoingTransfer(
          fileName: fileName,
          targetLabel: targetLabel,
          progress: success ? 1 : 0.08,
          status: success
              ? 'تم إرسال الملف بنجاح عبر الشبكة المحلية.'
              : (result['message']?.toString() ?? 'لم يتم إرسال الملف.'),
        );
      }
      if (canceled) {
        return const LanSendFileResult(
          success: false,
          message: 'تم إلغاء اختيار الملف.',
        );
      }
      return LanSendFileResult(
        success: success,
        message:
            result['message']?.toString() ??
            (success
                ? 'تم إرسال الملف بنجاح عبر الشبكة المحلية.'
                : 'فشل إرسال الملف عبر الشبكة المحلية.'),
        savedPath: result['savedPath']?.toString(),
      );
    } catch (error) {
      return LanSendFileResult(success: false, message: error.toString());
    }
  }

  Future<LanPeerProbeResult> _probeLanTargetIp(String targetIp) async {
    if (!kIsWeb) {
      return ref.read(lanFileTransferServiceProvider).probeTargetIp(targetIp);
    }
    final normalized = normalizeIpAddress(targetIp);
    if (normalized.isEmpty) {
      return const LanPeerProbeResult(
        success: false,
        message: 'عنوان IP مطلوب.',
        peerIp: '',
      );
    }
    try {
      final data = await web_bridge.probeLanPeer(normalized);
      final peerIps = (data['ips'] as List<dynamic>? ?? const <dynamic>[])
          .map((entry) => normalizeIpAddress(entry.toString()))
          .where((entry) => entry.isNotEmpty)
          .toList();
      final success = data['success'] == true;
      return LanPeerProbeResult(
        success: success,
        peerIp: normalized,
        peerIps: peerIps,
        message: success
            ? 'تم الاتصال بالجهاز $normalized بنجاح.'
            : 'الجهاز رد لكن خدمة النقل المحلي غير جاهزة.',
      );
    } catch (error) {
      return LanPeerProbeResult(
        success: false,
        peerIp: normalized,
        message:
            'تعذر الاتصال بالجهاز $normalized عبر خدمة نقل الملفات. '
            'الـ ping قد ينجح حتى لو بورت النقل 27861 مقفول. '
            'تأكد أن تطبيق الديسكتوب مفتوح على الجهاز الآخر وأن Windows Firewall يسمح له. '
            'التفاصيل: $error',
      );
    }
  }

  Future<LanSendFileResult> _sendWebFileToLanIp({
    required String targetIp,
    required String fileName,
    required Uint8List fileBytes,
    required String senderName,
    required String targetLabel,
  }) async {
    try {
      final request = await web_bridge.requestLanTransfer(
        targetIp: targetIp,
        fileName: fileName,
        fileSizeBytes: fileBytes.length,
        senderName: senderName,
        mimeType: _guessMimeType(fileName),
      );
      if (request['accepted'] != true) {
        return LanSendFileResult(
          success: false,
          message: request['message']?.toString() ?? 'تم رفض استقبال الملف.',
        );
      }
      final transferId = request['transferId']?.toString().trim() ?? '';
      final uploadToken = request['uploadToken']?.toString().trim() ?? '';
      if (transferId.isEmpty) {
        return const LanSendFileResult(
          success: false,
          message: 'الجهاز الآخر لم يرجع معرف نقل صالح.',
        );
      }
      _showOutgoingTransfer(
        fileName: fileName,
        targetLabel: targetLabel,
        progress: 0.16,
        status: 'وافق الجهاز الآخر. جاري إرسال الملف...',
      );
      final upload = await web_bridge.uploadLanTransferBytes(
        targetIp: targetIp,
        transferId: transferId,
        uploadToken: uploadToken,
        bytes: fileBytes,
        onProgress: (sent, total) {
          final ratio = total <= 0
              ? 0.0
              : (sent / total).clamp(0, 1).toDouble();
          _showOutgoingTransfer(
            fileName: fileName,
            targetLabel: targetLabel,
            progress: 0.16 + (ratio * 0.84),
            status: 'جاري إرسال الملف ${(ratio * 100).toStringAsFixed(0)}%',
          );
        },
      );
      final success = upload['success'] == true;
      return LanSendFileResult(
        success: success,
        message:
            upload['message']?.toString() ??
            (success
                ? 'تم إرسال الملف بنجاح عبر الشبكة المحلية.'
                : 'فشل إرسال الملف عبر الشبكة المحلية.'),
        savedPath: upload['savedPath']?.toString(),
      );
    } catch (error) {
      return LanSendFileResult(success: false, message: error.toString());
    }
  }

  String _guessMimeType(String fileName) {
    final extension = p.extension(fileName).toLowerCase();
    return switch (extension) {
      '.pdf' => 'application/pdf',
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      '.mp3' => 'audio/mpeg',
      '.wav' => 'audio/wav',
      '.mp4' => 'video/mp4',
      '.zip' => 'application/zip',
      _ => 'application/octet-stream',
    };
  }

  // ignore: unused_element
  Future<void> _sendFileToDesktopViaServer(AppUser user) async {
    if (_preparingLanDesktopSend || _sendingToLanDesktop) {
      return;
    }
    setState(() => _preparingLanDesktopSend = true);
    StreamSubscription? progressSubscription;
    try {
      final branchPeers = await ref
          .read(updateManagementRepositoryProvider)
          .listBranchPeerDevices(branchCode: user.branchCode);
      final availablePeers = _sortPeers(
        branchPeers
            .where((peer) => (peer.lastKnownUserId ?? '').trim().isNotEmpty)
            .toList(),
      );
      if (!mounted) {
        return;
      }

      BranchPeerDevice? selectedPeer;
      if (availablePeers.isNotEmpty) {
        selectedPeer = await showDialog<BranchPeerDevice>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('إرسال ملف لجهاز ديسكتوب'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'على الويب يتم الإرسال عبر السيرفر إلى تطبيق الديسكتوب المتصل، لأن المتصفح لا يسمح بالنقل المباشر عبر IP.',
                  ),
                  const SizedBox(height: 12),
                  ...availablePeers
                      .take(12)
                      .map(
                        (peer) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.computer_rounded),
                          title: Text(peer.displayLabel),
                          subtitle: Text(peer.localIp ?? 'ديسكتوب متصل'),
                          onTap: () => Navigator.of(dialogContext).pop(peer),
                        ),
                      ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        );
      }

      final targetUserId =
          selectedPeer?.lastKnownUserId?.trim().isNotEmpty == true
          ? selectedPeer!.lastKnownUserId!.trim()
          : user.id;

      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
      );
      final file = picked?.files.single;
      final fileBytes = file?.bytes;
      if (file == null || fileBytes == null || fileBytes.isEmpty) {
        return;
      }
      final maxAllowed = user.role == 'admin'
          ? _adminTransferMaxBytes
          : _userTransferMaxBytes;
      if (file.size > maxAllowed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حجم الملف أكبر من الحد المسموح (${formatFileSize(maxAllowed)}).',
            ),
          ),
        );
        return;
      }

      setState(() {
        _preparingLanDesktopSend = false;
        _sendingToLanDesktop = true;
      });
      final targetLabel = selectedPeer?.displayLabel ?? 'ديسكتوب نفس الحساب';
      _showOutgoingTransfer(
        fileName: file.name,
        targetLabel: targetLabel,
        progress: 0.04,
        status: 'جاري رفع الملف للسيرفر...',
      );

      final transfer = await _uploadTemporaryTransfer(
        fileBytes: fileBytes,
        fileName: file.name,
        fileSizeBytes: file.size,
        source: 'web_send_to_desktop',
        onProgress: (sent, total) {
          final ratio = total <= 0
              ? 0.0
              : (sent / total).clamp(0, 1).toDouble();
          _showOutgoingTransfer(
            fileName: file.name,
            targetLabel: targetLabel,
            progress: 0.05 + (ratio * 0.55),
            status: 'جاري رفع الملف للسيرفر...',
          );
        },
      );

      final ack = await ref
          .read(chatSocketServiceProvider)
          .emitWithAck('file_save_request', {
            'transferId': transfer['id']?.toString(),
            'targetUserId': targetUserId,
            'source': 'web_send_to_desktop',
          }, timeout: const Duration(seconds: 45));
      final ackOk = ack['ok'] == true && ack['success'] == true;
      final ackData = ack['data'] is Map<String, dynamic>
          ? ack['data'] as Map<String, dynamic>
          : Map<String, dynamic>.from(ack['data'] as Map? ?? const {});
      final jobId = ackData['jobId']?.toString();
      if (!ackOk || jobId == null || jobId.isEmpty) {
        throw Exception(
          ack['error']?.toString() ?? 'تعذر إرسال الملف إلى الديسكتوب.',
        );
      }

      _showOutgoingTransfer(
        fileName: file.name,
        targetLabel: targetLabel,
        progress: 0.66,
        status: 'تم إرسال الطلب للديسكتوب، بانتظار الحفظ...',
      );

      final socket = ref.read(chatSocketServiceProvider);
      final completer = Completer<Map<String, dynamic>>();
      progressSubscription = socket.events.listen((event) {
        final eventJobId = event.payload['jobId']?.toString();
        if (eventJobId != jobId) {
          return;
        }
        if (event.type == 'file_save_progress') {
          final progress = (event.payload['progress'] as num?)?.toDouble() ?? 0;
          final message = event.payload['message']?.toString();
          _showOutgoingTransfer(
            fileName: file.name,
            targetLabel: targetLabel,
            progress: 0.66 + (progress.clamp(0, 1) * 0.34),
            status: message?.trim().isNotEmpty == true
                ? message!
                : 'جاري الحفظ على الديسكتوب...',
          );
        } else if (event.type == 'file_save_status' && !completer.isCompleted) {
          completer.complete(event.payload);
        }
      });

      final status = await completer.future.timeout(
        const Duration(minutes: 10),
      );
      await progressSubscription.cancel();
      progressSubscription = null;
      final success = status['success'] == true;
      final message = status['message']?.toString().trim();
      _showOutgoingTransfer(
        fileName: file.name,
        targetLabel: targetLabel,
        progress: 1,
        status: message?.isNotEmpty == true
            ? message!
            : (success
                  ? 'تم حفظ الملف على الديسكتوب.'
                  : 'فشل حفظ الملف على الديسكتوب.'),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message?.isNotEmpty == true
                ? message!
                : (success
                      ? 'تم إرسال الملف إلى الديسكتوب.'
                      : 'فشل إرسال الملف إلى الديسكتوب.'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (progressSubscription != null) {
        await progressSubscription.cancel();
      }
      if (mounted) {
        setState(() {
          _preparingLanDesktopSend = false;
          _sendingToLanDesktop = false;
        });
        Future<void>.delayed(
          const Duration(seconds: 3),
          _clearOutgoingTransfer,
        );
      }
    }
  }

  Future<void> _confirmAndLogout() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد تسجيل الخروج'),
        content: const Text(
          'سيتم تسجيل خروجك من هذا الجهاز. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
    if (approved == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final documentsState = ref.watch(documentsControllerProvider);
    final themeMode =
        ref.watch(themeModeControllerProvider).valueOrNull ?? ThemeMode.light;
    final user = auth.valueOrNull;
    final userName = user?.fullName.isNotEmpty == true
        ? user!.fullName
        : user?.username ?? '';
    final canOpenAdmin = user?.canManageChat == true;
    final isAdmin = canOpenAdmin;
    final usersState = canOpenAdmin
        ? ref.watch(usersControllerProvider)
        : const AsyncData(<ManagedUser>[]);
    final announcementsState = ref.watch(announcementsControllerProvider);
    final appServerDefaults = ref.watch(appServerDefaultsProvider).valueOrNull;
    final cachedAppServerDefaults = ref
        .watch(cachedAppServerDefaultsProvider)
        .valueOrNull;
    final showServersShortcut =
        (appServerDefaults ?? cachedAppServerDefaults)?.showServersShortcut ??
        false;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: documentsState.when(
                      loading: () => const _FilesDashboardLoading(),
                      error: (error, _) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.folder_off_outlined,
                              size: 48,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'تعذر تحميل الملفات',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            FilledButton.tonalIcon(
                              onPressed: () => ref
                                  .read(documentsControllerProvider.notifier)
                                  .refresh(),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      ),
                      data: (documents) {
                        final documentFolders = ref.watch(documentFoldersProvider);
                        final folders = documentFolders.valueOrNull ?? [];
                        final rows = _filterAndSort(documents, folders);
                        final visibleFolders = folders.where((f) => f.parentId == _currentFolderId).toList();
                        final totalPages = documents.fold<int>(
                          0,
                          (s, d) => s + d.pageCount,
                        );
                        final totalSize = documents.fold<int>(
                          0,
                          (s, d) => s + d.fileSize,
                        );

                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final isTablet = constraints.maxWidth >= 760;

                            if (!isTablet) {
                              return _MobileLayout(
                                userName: userName,
                                themeMode: themeMode,
                                isAdmin: isAdmin,
                                showServersShortcut: showServersShortcut,
                                usersState: usersState,
                                announcementsState: announcementsState,
                                documents: rows,
                                totalDocuments: documents.length,
                                totalPages: totalPages,
                                totalSize: totalSize,
                                searchController: _searchController,
                                latestFirst: _latestFirst,
                                onSearchChanged: () => setState(() {}),
                                onSortChanged: (v) =>
                                    setState(() => _latestFirst = v),
                                onRefresh: () => ref
                                    .read(documentsControllerProvider.notifier)
                                    .refresh(),
                                onOpenDocument: _openDocument,
                                onPrintDocument: _printDocument,
                                onRenameDocument: _renameDocument,
                                onDeleteDocument: _deleteDocument,
                                folders: visibleFolders,
                                currentFolderId: _currentFolderId,
                                isGridView: _isGridView,
                                onRemoveFromFolder: _removeDocumentFromFolder,
                                onMoveToFolder: _showMoveFolderPicker,
                                onFolderRename: _renameFolder,
                                onFolderDelete: _deleteFolder,
                                onGoBack: _goBack,
                                onFolderTap: (id) => setState(() => _currentFolderId = id),
                                onViewChanged: (v) => setState(() => _isGridView = v),
                                onGoToChat: _goToChat,
                                onGoToProfile: _goToProfile,
                                onGoToServers: _goToServers,
                                onGoToAdmin: _goToAdminPanel,
                                onToggleTheme: () => ref
                                    .read(themeModeControllerProvider.notifier)
                                    .cycleThemeMode(),
                                onLogout: _confirmAndLogout,
                                onSendFileToMobile: user == null
                                    ? null
                                    : () => _sendFileToMobile(user),
                                onSendFileToLanDesktop: user == null
                                    ? null
                                    : () => _sendFileToLanDesktop(user),
                                onOpenTransferCenter: () =>
                                    _openTransferCenter(isAdmin: isAdmin),
                                onOpenPendingLanReceive:
                                    _pendingLanReceiveRequests.isEmpty
                                    ? null
                                    : _openPendingLanReceiveDialog,
                                pendingLanReceiveCount:
                                    _pendingLanReceiveRequests.length,
                                sendingToMobile: _sendingToMobile,
                                preparingLanDesktopSend:
                                    _preparingLanDesktopSend,
                                sendingToLanDesktop: _sendingToLanDesktop,
                                localLanIps: _localLanIps,
                              );
                            }

                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).dividerColor.withValues(alpha: 0.28),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: Row(
                                    children: [
                                      _SideNav(
                                        user: user,
                                        isAdmin: isAdmin,
                                        folders: folders,
                                        currentFolderId: _currentFolderId,
                                        totalFilesCount: documents.length,
                                        onFolderTap: (id) => setState(() => _currentFolderId = id),
                                        onCreateFolder: _createFolder,
                                        onSendFileToMobile: user == null
                                            ? null
                                            : () => _sendFileToMobile(user),
                                        onSendFileToLanDesktop: user == null
                                            ? null
                                            : () => _sendFileToLanDesktop(user),
                                        onOpenTransferCenter: () =>
                                            _openTransferCenter(
                                              isAdmin: isAdmin,
                                            ),
                                        onOpenPendingLanReceive:
                                            _pendingLanReceiveRequests.isEmpty
                                            ? null
                                            : _openPendingLanReceiveDialog,
                                        pendingLanReceiveCount:
                                            _pendingLanReceiveRequests.length,
                                        sendingToMobile: _sendingToMobile,
                                        preparingLanDesktopSend:
                                            _preparingLanDesktopSend,
                                        sendingToLanDesktop:
                                            _sendingToLanDesktop,
                                        localLanIps: _localLanIps,
                                      ),
                                      Expanded(
                                        child: Container(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerLowest,
                                          child: _FilesWorkspace(
                                            totalDocuments: documents.length,
                                            totalPages: totalPages,
                                            totalSize: totalSize,
                                            announcementsState:
                                                announcementsState,
                                            isAdmin: isAdmin,
                                            searchController: _searchController,
                                            latestFirst: _latestFirst,
                                            documents: rows,
                                            onSearchChanged: () =>
                                                setState(() {}),
                                            onSortChanged: (v) => setState(
                                              () => _latestFirst = v,
                                            ),
                                            onRefresh: () => ref
                                                .read(
                                                  documentsControllerProvider
                                                      .notifier,
                                                )
                                                .refresh(),
                                            onOpenDocument: _openDocument,
                                            onPrintDocument: _printDocument,
                                            onRenameDocument: _renameDocument,
                                            onDeleteDocument: _deleteDocument,
                                            folders: visibleFolders,
                                            currentFolderId: _currentFolderId,
                                            currentFolderName: folders.where((f) => f.id == _currentFolderId).firstOrNull?.name,
                                            isGridView: _isGridView,
                                            onRemoveFromFolder: _removeDocumentFromFolder,
                                            onMoveToFolder: _showMoveFolderPicker,
                                            onFolderRename: _renameFolder,
                                            onFolderDelete: _deleteFolder,
                                            onGoBack: _goBack,
                                            onFolderTap: (id) => setState(() => _currentFolderId = id),
                                            onViewChanged: (v) => setState(() => _isGridView = v),
                                            onCreateFolder: _createFolder,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  if (_isDownloading)
                    Positioned(
                      top: 12,
                      left: 16,
                      right: 16,
                      child: _DownloadProgressBanner(
                        fileName: _downloadingFileName,
                        progress: _downloadProgress,
                      ),
                    ),
                  if (_showOutgoingTransferBanner)
                    Positioned(
                      top: _isDownloading ? 92 : 12,
                      left: 16,
                      right: 16,
                      child: _OutgoingTransferBanner(
                        fileName: _outgoingTransferFileName,
                        targetLabel: _outgoingTransferTarget,
                        progress: _outgoingTransferProgress,
                        status: _outgoingTransferStatus,
                      ),
                    ),
                ],
              ),
            ),
            if (!widget.isWrapped)
              DesktopWorkspaceSidebar(
                user: user,
                activeSection: DesktopWorkspaceSection.files,
                currentThemeMode: themeMode,
                isDark: themeMode == ThemeMode.dark,
                accentColor: Theme.of(context).colorScheme.primary,
                onOpenChat: _goToChat,
                onRefresh: () =>
                    ref.read(documentsControllerProvider.notifier).refresh(),
                onOpenFiles: () {},
                showServersShortcut: showServersShortcut,
                onOpenServers: _goToServers,
                onOpenProfile: _goToProfile,
                onOpenUpdates: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UpdateCenterScreen()),
                ),
                onToggleTheme: () => ref
                    .read(themeModeControllerProvider.notifier)
                    .cycleThemeMode(),
                onOpenTickets: _goToTicketsPanel,
                onLogout: _confirmAndLogout,
                onCreateConversation: _goToChat,
                onOpenAdmin: canOpenAdmin ? _goToAdminPanel : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _TransferCenterList extends StatelessWidget {
  const _TransferCenterList({
    required this.emptyText,
    required this.items,
    required this.trailingBuilder,
  });

  final String emptyText;
  final List<Map<String, dynamic>> items;
  final Widget Function(Map<String, dynamic> item)? trailingBuilder;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Text(emptyText));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        final fileName =
            item['fileName']?.toString() ??
            item['title']?.toString() ??
            item['type']?.toString() ??
            'حدث';
        final status = item['status']?.toString();
        final message = item['message']?.toString() ?? item['body']?.toString();
        final createdAt =
            item['createdAt']?.toString() ?? item['receivedAt']?.toString();
        final peer =
            item['peerName']?.toString() ??
            item['senderName']?.toString() ??
            item['actorName']?.toString();
        final size = int.tryParse(item['fileSizeBytes']?.toString() ?? '') ?? 0;
        final subtitle = [
          if (peer != null && peer.trim().isNotEmpty) peer,
          if (status != null && status.trim().isNotEmpty) status,
          if (size > 0) formatFileSize(size),
          if (createdAt != null && createdAt.trim().isNotEmpty) createdAt,
          if (message != null && message.trim().isNotEmpty) message,
        ].join(' • ');
        return ListTile(
          dense: true,
          leading: const Icon(Icons.insert_drive_file_outlined),
          title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            subtitle.isEmpty ? '-' : subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: trailingBuilder?.call(item),
        );
      },
    );
  }
}

class _TransferPolicyEditor extends StatefulWidget {
  const _TransferPolicyEditor({required this.policy, required this.onSave});

  final Map<String, dynamic> policy;
  final Future<void> Function(Map<String, dynamic> policy) onSave;

  @override
  State<_TransferPolicyEditor> createState() => _TransferPolicyEditorState();
}

class _TransferPolicyEditorState extends State<_TransferPolicyEditor> {
  late final TextEditingController _maxSizeMbController;
  late final TextEditingController _extensionsController;
  late final TextEditingController _branchesController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final maxBytes =
        int.tryParse(widget.policy['maxFileSizeBytes']?.toString() ?? '') ??
        500 * 1024 * 1024;
    _maxSizeMbController = TextEditingController(
      text: (maxBytes / (1024 * 1024)).round().toString(),
    );
    _extensionsController = TextEditingController(
      text: (widget.policy['allowedExtensions'] as List<dynamic>? ?? const [])
          .map((entry) => entry.toString())
          .join(', '),
    );
    _branchesController = TextEditingController(
      text: (widget.policy['allowedBranchCodes'] as List<dynamic>? ?? const [])
          .map((entry) => entry.toString())
          .join(', '),
    );
  }

  @override
  void dispose() {
    _maxSizeMbController.dispose();
    _extensionsController.dispose();
    _branchesController.dispose();
    super.dispose();
  }

  List<String> _splitCsv(String value) => value
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(
          controller: _maxSizeMbController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'الحد الأقصى لحجم الملف بالميجابايت',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _extensionsController,
          decoration: const InputDecoration(
            labelText: 'أنواع الملفات المسموحة',
            helperText: 'اتركها فارغة للسماح بكل الأنواع. مثال: pdf, png, zip',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _branchesController,
          decoration: const InputDecoration(
            labelText: 'الفروع المسموح لها بالتبادل',
            helperText: 'اتركها فارغة للسماح لكل الفروع. مثال: MAIN, CAIRO',
          ),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    final maxMb =
                        int.tryParse(_maxSizeMbController.text.trim()) ?? 500;
                    await widget.onSave({
                      'maxFileSizeBytes': maxMb * 1024 * 1024,
                      'allowedExtensions': _splitCsv(
                        _extensionsController.text,
                      ),
                      'allowedBranchCodes': _splitCsv(_branchesController.text),
                    });
                    if (mounted) {
                      setState(() => _saving = false);
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم حفظ سياسة النقل.')),
                      );
                    }
                  },
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: ButtonLoadingIndicator(),
                  )
                : const Icon(Icons.save_rounded),
            label: const Text('حفظ السياسة'),
          ),
        ),
      ],
    );
  }
}

class _FileTypeInfo {
  final IconData icon;
  final Color color;
  final String label;

  const _FileTypeInfo({required this.icon, required this.color, required this.label});
}

_FileTypeInfo _getFileTypeInfo(String fileName) {
  final ext = p.extension(fileName).toLowerCase().replaceAll('.', '');
  switch (ext) {
    case 'pdf':
      return const _FileTypeInfo(
        icon: Icons.picture_as_pdf_rounded,
        color: Color(0xFFFF3B30), // Apple Red
        label: 'PDF',
      );
    case 'doc':
    case 'docx':
    case 'rtf':
      return const _FileTypeInfo(
        icon: Icons.description_rounded,
        color: Color(0xFF007AFF), // Apple Blue
        label: 'DOC',
      );
    case 'xls':
    case 'xlsx':
    case 'csv':
      return const _FileTypeInfo(
        icon: Icons.table_chart_rounded,
        color: Color(0xFF34C759), // Apple Green
        label: 'XLS',
      );
    case 'ppt':
    case 'pptx':
      return const _FileTypeInfo(
        icon: Icons.slideshow_rounded,
        color: Color(0xFFFF9500), // Apple Orange
        label: 'PPT',
      );
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
    case 'svg':
      return const _FileTypeInfo(
        icon: Icons.image_rounded,
        color: Color(0xFFAF52DE), // Apple Purple
        label: 'IMG',
      );
    case 'mp4':
    case 'mov':
    case 'avi':
    case 'mkv':
    case 'wmv':
      return const _FileTypeInfo(
        icon: Icons.movie_rounded,
        color: Color(0xFF5856D6), // Apple Indigo
        label: 'VIDEO',
      );
    case 'mp3':
    case 'wav':
    case 'm4a':
    case 'ogg':
    case 'aac':
      return const _FileTypeInfo(
        icon: Icons.music_note_rounded,
        color: Color(0xFFFF2D55), // Apple Pink
        label: 'AUDIO',
      );
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
      return const _FileTypeInfo(
        icon: Icons.folder_zip_rounded,
        color: Color(0xFFFF9500), // Apple Amber
        label: 'ZIP',
      );
    case 'txt':
    case 'log':
    case 'json':
    case 'xml':
    case 'yaml':
    case 'yml':
      return const _FileTypeInfo(
        icon: Icons.article_rounded,
        color: Color(0xFF64748B), // Apple Slate
        label: 'TXT',
      );
    default:
      return const _FileTypeInfo(
        icon: Icons.insert_drive_file_rounded,
        color: Color(0xFF007AFF),
        label: 'FILE',
      );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.user,
    required this.isAdmin,
    required this.folders,
    required this.currentFolderId,
    required this.totalFilesCount,
    required this.onFolderTap,
    required this.onCreateFolder,
    required this.onSendFileToMobile,
    required this.onSendFileToLanDesktop,
    required this.onOpenTransferCenter,
    required this.onOpenPendingLanReceive,
    required this.pendingLanReceiveCount,
    required this.sendingToMobile,
    required this.preparingLanDesktopSend,
    required this.sendingToLanDesktop,
    required this.localLanIps,
  });

  final AppUser? user;
  final bool isAdmin;
  final List<DocumentFolder> folders;
  final String? currentFolderId;
  final int totalFilesCount;
  final void Function(String?) onFolderTap;
  final VoidCallback onCreateFolder;
  final VoidCallback? onSendFileToMobile;
  final VoidCallback? onSendFileToLanDesktop;
  final VoidCallback onOpenTransferCenter;
  final VoidCallback? onOpenPendingLanReceive;
  final int pendingLanReceiveCount;
  final bool sendingToMobile;
  final bool preparingLanDesktopSend;
  final bool sendingToLanDesktop;
  final List<String> localLanIps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF161618) : const Color(0xFFF9F9FB);

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          left: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Brand / User info
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.folder_shared_rounded,
                            color: cs.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'إدارة الملفات',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                user?.fullName.isNotEmpty == true
                                    ? user!.fullName
                                    : 'المستندات والطباعة',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Library Section
                    _SidebarSectionHeader(title: 'المكتبة'),
                    const SizedBox(height: 4),
                    _SidebarItemTile(
                      icon: Icons.grid_view_rounded,
                      label: 'جميع الملفات',
                      countBadge: '$totalFilesCount',
                      selected: currentFolderId == null,
                      onTap: () => onFolderTap(null),
                    ),

                    // Folders List
                    if (folders.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _SidebarSectionHeader(
                        title: 'المجلدات (${folders.length})',
                        actionIcon: Icons.add_rounded,
                        onActionTap: onCreateFolder,
                      ),
                      const SizedBox(height: 4),
                      ...folders.take(6).map((folder) {
                        final isSelected = currentFolderId == folder.id;
                        final fColor = folder.colorValue != null
                            ? Color(folder.colorValue!)
                            : const Color(0xFFFF9500);
                        return _SidebarItemTile(
                          icon: Icons.folder_rounded,
                          iconColor: fColor,
                          label: folder.name,
                          countBadge: '${folder.documentIds.length}',
                          selected: isSelected,
                          onTap: () => onFolderTap(folder.id),
                        );
                      }),
                      if (folders.length > 6)
                        Padding(
                          padding: const EdgeInsets.only(right: 12, top: 4),
                          child: Text(
                            '+ ${folders.length - 6} مجلدات أخرى',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],

                    const SizedBox(height: 16),
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: theme.dividerColor.withValues(alpha: 0.15),
                    ),
                    const SizedBox(height: 14),

                    // Network & Transfers
                    _SidebarSectionHeader(title: 'النقل والشبكة'),
                    const SizedBox(height: 4),
                    _SidebarItemTile(
                      icon: Icons.phone_iphone_rounded,
                      label: 'إرسال للهاتف',
                      isLoading: sendingToMobile,
                      onTap: sendingToMobile ? null : onSendFileToMobile,
                    ),
                    _SidebarItemTile(
                      icon: Icons.lan_rounded,
                      label: 'إرسال لجهاز محلي',
                      isLoading: preparingLanDesktopSend || sendingToLanDesktop,
                      onTap: (preparingLanDesktopSend || sendingToLanDesktop)
                          ? null
                          : onSendFileToLanDesktop,
                    ),
                    _SidebarItemTile(
                      icon: Icons.swap_horiz_rounded,
                      label: 'مركز النقل',
                      onTap: onOpenTransferCenter,
                    ),

                    if (pendingLanReceiveCount > 0) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: onOpenPendingLanReceive,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF34C759).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF34C759).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.download_rounded,
                                size: 16,
                                color: Color(0xFF34C759),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'طلبات استلام معلقة ($pendingLanReceiveCount)',
                                  style: const TextStyle(
                                    color: Color(0xFF34C759),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const Spacer(),
                    const SizedBox(height: 12),
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: theme.dividerColor.withValues(alpha: 0.15),
                    ),
                    const SizedBox(height: 10),

                    // LAN Status
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF242426)
                            : const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF34C759),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'متصل بالشبكة المحلية',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                          if (localLanIps.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              localLanIps.first,
                              style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SidebarSectionHeader extends StatelessWidget {
  const _SidebarSectionHeader({
    required this.title,
    this.actionIcon,
    this.onActionTap,
  });

  final String title;
  final IconData? actionIcon;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: cs.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ),
        if (actionIcon != null)
          InkWell(
            onTap: onActionTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(actionIcon, size: 16, color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _SidebarItemTile extends StatelessWidget {
  const _SidebarItemTile({
    required this.icon,
    this.iconColor,
    required this.label,
    this.countBadge,
    this.selected = false,
    this.isLoading = false,
    this.onTap,
  });

  final IconData icon;
  final Color? iconColor;
  final String label;
  final String? countBadge;
  final bool selected;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = selected
        ? (isDark
            ? cs.primary.withValues(alpha: 0.22)
            : cs.primary.withValues(alpha: 0.12))
        : Colors.transparent;
    final textColor = selected ? cs.primary : cs.onSurface;
    final effectiveIconColor = iconColor ?? (selected ? cs.primary : cs.onSurfaceVariant);

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Icon(icon, size: 18, color: effectiveIconColor),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (countBadge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.primary
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    countBadge!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? cs.onPrimary
                          : cs.onSurfaceVariant,
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

class _FilesWorkspace extends StatelessWidget {
  const _FilesWorkspace({
    required this.totalDocuments,
    required this.totalPages,
    required this.totalSize,
    required this.announcementsState,
    required this.isAdmin,
    required this.searchController,
    required this.latestFirst,
    required this.documents,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.onRefresh,
    required this.onOpenDocument,
    required this.onPrintDocument,
    required this.onRenameDocument,
    required this.onDeleteDocument,
    required this.folders,
    this.currentFolderId,
    this.currentFolderName,
    this.isGridView = false,
    required this.onRemoveFromFolder,
    required this.onMoveToFolder,
    required this.onFolderRename,
    required this.onFolderDelete,
    required this.onGoBack,
    required this.onFolderTap,
    required this.onViewChanged,
    required this.onCreateFolder,
  });

  final int totalDocuments;
  final int totalPages;
  final int totalSize;
  final AsyncValue<List<AdminAnnouncement>> announcementsState;
  final bool isAdmin;
  final TextEditingController searchController;
  final bool latestFirst;
  final List<RemoteDocument> documents;
  final VoidCallback onSearchChanged;
  final ValueChanged<bool> onSortChanged;
  final VoidCallback onRefresh;
  final Future<void> Function(RemoteDocument) onOpenDocument;
  final Future<void> Function(RemoteDocument) onPrintDocument;
  final Future<void> Function(RemoteDocument) onRenameDocument;
  final Future<void> Function(RemoteDocument) onDeleteDocument;

  final List<DocumentFolder> folders;
  final String? currentFolderId;
  final String? currentFolderName;
  final bool isGridView;
  final Future<void> Function(String) onRemoveFromFolder;
  final Future<void> Function(String) onMoveToFolder;
  final Future<void> Function(DocumentFolder) onFolderRename;
  final Future<void> Function(DocumentFolder) onFolderDelete;
  final VoidCallback onGoBack;
  final void Function(String) onFolderTap;
  final void Function(bool) onViewChanged;
  final VoidCallback onCreateFolder;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _WorkspaceTopBar(
          currentFolderId: currentFolderId,
          currentFolderName: currentFolderName,
          totalDocuments: totalDocuments,
          onGoBack: onGoBack,
          onCreateFolder: onCreateFolder,
          onRefresh: onRefresh,
        ),
        Expanded(
          child: _FilesFeed(
            padding: const EdgeInsets.all(18),
            header: [
              _AnnouncementsSection(announcementsState: announcementsState),
              _StatsRow(
                totalDocuments: totalDocuments,
                totalPages: totalPages,
                totalSize: totalSize,
              ),
              _SearchAndSortBar(
                searchController: searchController,
                latestFirst: latestFirst,
                onSearchChanged: onSearchChanged,
                onSortChanged: onSortChanged,
                isGridView: isGridView,
                onViewChanged: onViewChanged,
              ),
            ],
            documents: documents,
            onRefresh: onRefresh,
            onOpen: onOpenDocument,
            onPrint: onPrintDocument,
            onRename: onRenameDocument,
            onDelete: onDeleteDocument,
            folders: folders,
            currentFolderId: currentFolderId,
            isGridView: isGridView,
            onRemoveFromFolder: onRemoveFromFolder,
            onMoveToFolder: onMoveToFolder,
            onFolderRename: onFolderRename,
            onFolderDelete: onFolderDelete,
            onGoBack: onGoBack,
            onFolderTap: onFolderTap,
          ),
        ),
      ],
    );
  }
}

class _WorkspaceTopBar extends StatelessWidget {
  const _WorkspaceTopBar({
    required this.currentFolderId,
    required this.currentFolderName,
    required this.totalDocuments,
    required this.onGoBack,
    required this.onCreateFolder,
    required this.onRefresh,
  });

  final String? currentFolderId;
  final String? currentFolderName;
  final int totalDocuments;
  final VoidCallback onGoBack;
  final VoidCallback onCreateFolder;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.18),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Breadcrumbs
          if (currentFolderId != null) ...[
            IconButton(
              onPressed: onGoBack,
              tooltip: 'رجوع للملفات',
              icon: const Icon(Icons.arrow_forward_rounded, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF2F2F7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(width: 10),
            InkWell(
              onTap: onGoBack,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  'الملفات',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.chevron_left_rounded,
                size: 18,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9500).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.folder_rounded,
                    size: 16,
                    color: Color(0xFFFF9500),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    currentFolderName ?? 'مجلد',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFFF9500),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              'الملفات',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$totalDocuments ملف',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],

          const Spacer(),

          // Actions
          FilledButton.tonalIcon(
            onPressed: onCreateFolder,
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('مجلد جديد'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onRefresh,
            tooltip: 'تحديث القائمة',
            icon: const Icon(Icons.refresh_rounded, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: isDark
                  ? const Color(0xFF2C2C2E)
                  : const Color(0xFFF2F2F7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminSidePanel extends StatelessWidget {
  const _AdminSidePanel({required this.usersState, required this.onGoToAdmin});

  final AsyncValue<List<ManagedUser>> usersState;
  final VoidCallback onGoToAdmin;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _AdminOverviewCard(
        usersState: usersState,
        onGoToAdmin: onGoToAdmin,
      ),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({
    required this.userName,
    required this.themeMode,
    required this.isAdmin,
    required this.showServersShortcut,
    required this.usersState,
    required this.announcementsState,
    required this.documents,
    required this.totalDocuments,
    required this.totalPages,
    required this.totalSize,
    required this.searchController,
    required this.latestFirst,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.onRefresh,
    required this.onOpenDocument,
    required this.onPrintDocument,
    required this.onRenameDocument,
    required this.onDeleteDocument,
    required this.onGoToChat,
    required this.onGoToAdmin,
    required this.onGoToProfile,
    required this.onGoToServers,
    required this.onToggleTheme,
    required this.onLogout,
    required this.onSendFileToMobile,
    required this.onSendFileToLanDesktop,
    required this.onOpenTransferCenter,
    required this.onOpenPendingLanReceive,
    required this.pendingLanReceiveCount,
    required this.sendingToMobile,
    required this.preparingLanDesktopSend,
    required this.sendingToLanDesktop,
    required this.localLanIps,
    required this.folders,
    this.currentFolderId,
    this.isGridView = false,
    required this.onRemoveFromFolder,
    required this.onMoveToFolder,
    required this.onFolderRename,
    required this.onFolderDelete,
    required this.onGoBack,
    required this.onFolderTap,
    required this.onViewChanged,
  });

  final String userName;
  final ThemeMode themeMode;
  final bool isAdmin;
  final bool showServersShortcut;
  final AsyncValue<List<ManagedUser>> usersState;
  final AsyncValue<List<AdminAnnouncement>> announcementsState;
  final List<RemoteDocument> documents;
  final int totalDocuments;
  final int totalPages;
  final int totalSize;
  final TextEditingController searchController;
  final bool latestFirst;
  final VoidCallback onSearchChanged;
  final ValueChanged<bool> onSortChanged;
  final VoidCallback onRefresh;
  final Future<void> Function(RemoteDocument) onOpenDocument;
  final Future<void> Function(RemoteDocument) onPrintDocument;
  final Future<void> Function(RemoteDocument) onRenameDocument;
  final Future<void> Function(RemoteDocument) onDeleteDocument;

  final List<DocumentFolder> folders;
  final String? currentFolderId;
  final bool isGridView;
  final Future<void> Function(String) onRemoveFromFolder;
  final Future<void> Function(String) onMoveToFolder;
  final Future<void> Function(DocumentFolder) onFolderRename;
  final Future<void> Function(DocumentFolder) onFolderDelete;
  final VoidCallback onGoBack;
  final void Function(String) onFolderTap;
  final void Function(bool) onViewChanged;
  final VoidCallback onGoToChat;
  final VoidCallback onGoToAdmin;
  final VoidCallback onGoToProfile;
  final VoidCallback onGoToServers;
  final VoidCallback onToggleTheme;
  final VoidCallback onLogout;
  final VoidCallback? onSendFileToMobile;
  final VoidCallback? onSendFileToLanDesktop;
  final VoidCallback onOpenTransferCenter;
  final VoidCallback? onOpenPendingLanReceive;
  final int pendingLanReceiveCount;
  final bool sendingToMobile;
  final bool preparingLanDesktopSend;
  final bool sendingToLanDesktop;
  final List<String> localLanIps;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(userName.isNotEmpty ? userName : 'الملفات'),
        actions: [
          IconButton(
            tooltip: 'الشات',
            onPressed: onGoToChat,
            icon: const Icon(Icons.forum_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  onGoToProfile();
                case 'theme':
                  onToggleTheme();
                case 'refresh':
                  onRefresh();
                case 'servers':
                  onGoToServers();
                case 'admin':
                  onGoToAdmin();
                case 'logout':
                  onLogout();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Text('الملف الشخصي'),
              ),
              if (showServersShortcut)
                const PopupMenuItem(value: 'servers', child: Text('السيرفرات')),
              if (isAdmin)
                const PopupMenuItem(
                  value: 'admin',
                  child: Text('لوحة الإدارة'),
                ),
              PopupMenuItem(
                value: 'theme',
                child: Text(switch (themeMode) {
                  ThemeMode.dark => 'الوضع الداكن',
                  ThemeMode.system => 'الوضع الفاتح',
                  ThemeMode.light => 'الوضع الفاتح',
                }),
              ),
              const PopupMenuItem(value: 'refresh', child: Text('تحديث')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'logout', child: Text('تسجيل الخروج')),
            ],
          ),
        ],
      ),
      body: _FilesFeed(
        padding: const EdgeInsets.all(16),
        header: [
          _AnnouncementsSection(announcementsState: announcementsState),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (onSendFileToMobile != null)
                FilledButton.icon(
                  onPressed: onSendFileToMobile,
                  icon: sendingToMobile
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.phone_android_rounded, size: 18),
                  label: Text(
                    sendingToMobile ? 'جارٍ الإرسال...' : 'إرسال للموبايل',
                  ),
                ),
              if (onSendFileToLanDesktop != null)
                FilledButton.tonalIcon(
                  onPressed: (preparingLanDesktopSend || sendingToLanDesktop)
                      ? null
                      : onSendFileToLanDesktop,
                  icon: (preparingLanDesktopSend || sendingToLanDesktop)
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lan_rounded, size: 18),
                  label: Text(
                    preparingLanDesktopSend
                        ? 'جارٍ فتح النافذة...'
                        : sendingToLanDesktop
                        ? 'جارٍ النقل...'
                        : 'إرسال للشبكة (LAN)',
                  ),
                ),
              FilledButton.tonalIcon(
                onPressed: onOpenTransferCenter,
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('مركز النقل'),
              ),
              if (pendingLanReceiveCount > 0)
                FilledButton.icon(
                  onPressed: onOpenPendingLanReceive,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text('طلبات استلام ($pendingLanReceiveCount)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _StatsRow(
            totalDocuments: totalDocuments,
            totalPages: totalPages,
            totalSize: totalSize,
          ),
          const SizedBox(height: 14),
          if (isAdmin) ...[
            _AdminOverviewCard(
              usersState: usersState,
              onGoToAdmin: onGoToAdmin,
            ),
            const SizedBox(height: 14),
          ],
          _SearchAndSortBar(
            searchController: searchController,
            latestFirst: latestFirst,
            onSearchChanged: onSearchChanged,
            onSortChanged: onSortChanged,
            isGridView: isGridView,
            onViewChanged: onViewChanged,
          ),
        ],
        documents: documents,
        onRefresh: onRefresh,
        onOpen: onOpenDocument,
        onPrint: onPrintDocument,
        onRename: onRenameDocument,
        onDelete: onDeleteDocument,
        folders: folders,
        currentFolderId: currentFolderId,
        isGridView: isGridView,
        onRemoveFromFolder: onRemoveFromFolder,
        onMoveToFolder: onMoveToFolder,
        onFolderRename: onFolderRename,
        onFolderDelete: onFolderDelete,
        onGoBack: onGoBack,
        onFolderTap: onFolderTap,
      ),
    );
  }
}

class _FilesFeed extends StatelessWidget {
  const _FilesFeed({
    required this.padding,
    required this.header,
    required this.documents,
    required this.folders,
    required this.currentFolderId,
    required this.isGridView,
    required this.onRefresh,
    required this.onOpen,
    required this.onPrint,
    required this.onRename,
    required this.onDelete,
    required this.onRemoveFromFolder,
    required this.onMoveToFolder,
    required this.onFolderRename,
    required this.onFolderDelete,
    required this.onGoBack,
    required this.onFolderTap,
  });

  final EdgeInsets padding;
  final List<Widget> header;
  final List<RemoteDocument> documents;
  final List<DocumentFolder> folders;
  final String? currentFolderId;
  final bool isGridView;
  final VoidCallback onRefresh;
  final Future<void> Function(RemoteDocument) onOpen;
  final Future<void> Function(RemoteDocument) onPrint;
  final Future<void> Function(RemoteDocument) onRename;
  final Future<void> Function(RemoteDocument) onDelete;
  final Future<void> Function(String) onRemoveFromFolder;
  final Future<void> Function(String) onMoveToFolder;
  final Future<void> Function(DocumentFolder) onFolderRename;
  final Future<void> Function(DocumentFolder) onFolderDelete;
  final VoidCallback onGoBack;
  final void Function(String) onFolderTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleHeader = header.where((entry) => entry is! SizedBox).toList();

    return Padding(
      padding: padding,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...visibleHeader,
                const SizedBox(height: 16),
              ],
            ),
          ),

          // Folders Section
          if (folders.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12, right: 4),
                child: Row(
                  children: [
                    Text(
                      'المجلدات',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${folders.length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isGridView)
              SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.05,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return _FolderGridCard(
                      folder: folders[index],
                      onTap: () => onFolderTap(folders[index].id),
                      onRename: () => onFolderRename(folders[index]),
                      onDelete: () => onFolderDelete(folders[index]),
                    );
                  },
                  childCount: folders.length,
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FolderListCard(
                        folder: folders[index],
                        onTap: () => onFolderTap(folders[index].id),
                        onRename: () => onFolderRename(folders[index]),
                        onDelete: () => onFolderDelete(folders[index]),
                      ),
                    );
                  },
                  childCount: folders.length,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],

          // Documents Section
          if (documents.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12, right: 4),
                child: Row(
                  children: [
                    Text(
                      'الملفات والمستندات',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${documents.length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isGridView)
              SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return _DocumentGridCard(
                      document: documents[index],
                      isInFolder: currentFolderId != null,
                      onOpen: () => onOpen(documents[index]),
                      onPrint: () => onPrint(documents[index]),
                      onRename: () => onRename(documents[index]),
                      onDelete: () => onDelete(documents[index]),
                      onMoveToFolder: () => onMoveToFolder(documents[index].id),
                      onRemoveFromFolder: () =>
                          onRemoveFromFolder(documents[index].id),
                    );
                  },
                  childCount: documents.length,
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FileListItem(
                        document: documents[index],
                        isInFolder: currentFolderId != null,
                        onOpen: () => onOpen(documents[index]),
                        onPrint: () => onPrint(documents[index]),
                        onRename: () => onRename(documents[index]),
                        onDelete: () => onDelete(documents[index]),
                        onMoveToFolder: () => onMoveToFolder(documents[index].id),
                        onRemoveFromFolder: () =>
                            onRemoveFromFolder(documents[index].id),
                      ),
                    );
                  },
                  childCount: documents.length,
                ),
              ),
          ] else if (folders.isEmpty)
            SliverToBoxAdapter(
              child: _EmptyFilesState(onRefresh: onRefresh),
            ),
        ],
      ),
    );
  }
}

class _AnnouncementsSection extends StatelessWidget {
  const _AnnouncementsSection({required this.announcementsState});

  final AsyncValue<List<AdminAnnouncement>> announcementsState;

  Color _toneColor(BuildContext context, String tone) {
    final scheme = Theme.of(context).colorScheme;
    return switch (tone) {
      'success' => const Color(0xFF166534),
      'warning' => const Color(0xFFD97706),
      'critical' => scheme.error,
      _ => scheme.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    return announcementsState.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (announcements) {
        final visible = announcements.where((a) => a.isActive).take(3).toList();
        if (visible.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: visible
                  .map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Container(
                        width: 320,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _toneColor(context, a.tone).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _toneColor(context, a.tone).withValues(alpha: 0.15),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: _toneColor(context, a.tone).withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                a.isPinned
                                    ? Icons.push_pin_rounded
                                    : Icons.campaign_rounded,
                                color: _toneColor(context, a.tone),
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    a.message,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.color
                                              ?.withValues(alpha: 0.8),
                                          fontSize: 12,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.totalDocuments,
    required this.totalPages,
    required this.totalSize,
  });

  final int totalDocuments;
  final int totalPages;
  final int totalSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: _AppleStatCapsule(
              icon: Icons.description_rounded,
              iconColor: const Color(0xFF007AFF), // Apple Blue
              label: 'مستندات',
              value: '$totalDocuments',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _AppleStatCapsule(
              icon: Icons.auto_stories_rounded,
              iconColor: const Color(0xFFAF52DE), // Apple Purple
              label: 'صفحة',
              value: '$totalPages',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _AppleStatCapsule(
              icon: Icons.pie_chart_rounded,
              iconColor: const Color(0xFF34C759), // Apple Green
              label: 'إجمالي الحجم',
              value: formatFileSize(totalSize),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppleStatCapsule extends StatelessWidget {
  const _AppleStatCapsule({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchAndSortBar extends StatelessWidget {
  const _SearchAndSortBar({
    required this.searchController,
    required this.latestFirst,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.isGridView,
    required this.onViewChanged,
  });

  final TextEditingController searchController;
  final bool latestFirst;
  final VoidCallback onSearchChanged;
  final ValueChanged<bool> onSortChanged;
  final bool isGridView;
  final ValueChanged<bool> onViewChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: [
        // View Toggle (Apple segmented pill)
        Container(
          height: 40,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AppleSegmentBtn(
                icon: Icons.grid_view_rounded,
                tooltip: 'عرض شبكي',
                isSelected: isGridView,
                onTap: () => onViewChanged(true),
              ),
              _AppleSegmentBtn(
                icon: Icons.view_list_rounded,
                tooltip: 'عرض كقائمة',
                isSelected: !isGridView,
                onTap: () => onViewChanged(false),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),

        // Apple Search Bar
        Expanded(
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
                width: 0.5,
              ),
            ),
            child: TextField(
              controller: searchController,
              onChanged: (_) => onSearchChanged(),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: InputBorder.none,
                isDense: true,
                hintText: 'بحث في المستندات والملفات...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.cancel_rounded, size: 16),
                        color: cs.onSurfaceVariant,
                        onPressed: () {
                          searchController.clear();
                          onSearchChanged();
                        },
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Sort Pill
        Container(
          height: 40,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AppleTextSegmentBtn(
                label: 'الأحدث',
                isSelected: latestFirst,
                onTap: () => onSortChanged(true),
              ),
              _AppleTextSegmentBtn(
                label: 'الأقدم',
                isSelected: !latestFirst,
                onTap: () => onSortChanged(false),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppleSegmentBtn extends StatelessWidget {
  const _AppleSegmentBtn({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF3A3A3C) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 18,
            color: isSelected ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _AppleTextSegmentBtn extends StatelessWidget {
  const _AppleTextSegmentBtn({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF3A3A3C) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _FolderGridCard extends ConsumerWidget {
  const _FolderGridCard({
    required this.folder,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final DocumentFolder folder;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final docCount = folder.documentIds.length;
    final folderColor = folder.colorValue != null
        ? Color(folder.colorValue!)
        : const Color(0xFFFF9500);

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          !folder.documentIds.contains(details.data),
      onAcceptWithDetails: (details) async {
        await ref
            .read(documentFoldersProvider.notifier)
            .moveDocumentToFolder(details.data, folder.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('تم نقل الملف إلى «${folder.name}»'),
            ),
          );
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isHovered
                  ? const Color(0xFF007AFF).withValues(alpha: 0.10)
                  : (isDark ? const Color(0xFF1C1C1E) : Colors.white),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isHovered
                    ? const Color(0xFF007AFF)
                    : (isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFE5E5EA)),
                width: isHovered ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Top row with color indicator & options
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: folderColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'خيارات المجلد',
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onSelected: (action) {
                        if (action == 'rename') onRename();
                        if (action == 'delete') onDelete();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'rename',
                          child: Row(
                            children: [
                              Icon(Icons.drive_file_rename_outline_rounded,
                                  size: 18),
                              SizedBox(width: 8),
                              Text('إعادة تسمية'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded,
                                  size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('حذف', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),

                // Center Icon
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: folderColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isHovered
                        ? Icons.folder_open_rounded
                        : Icons.folder_rounded,
                    size: 32,
                    color: folderColor,
                  ),
                ),
                const SizedBox(height: 10),

                // Name
                Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),

                // Count or Drop target feedback
                Text(
                  isHovered ? 'أفلت لنقل الملف هنا' : '$docCount ملف',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isHovered
                        ? const Color(0xFF007AFF)
                        : cs.onSurfaceVariant,
                    fontWeight: isHovered ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FolderListCard extends ConsumerWidget {
  const _FolderListCard({
    required this.folder,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final DocumentFolder folder;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final docCount = folder.documentIds.length;
    final folderColor = folder.colorValue != null
        ? Color(folder.colorValue!)
        : const Color(0xFFFF9500);

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          !folder.documentIds.contains(details.data),
      onAcceptWithDetails: (details) async {
        await ref
            .read(documentFoldersProvider.notifier)
            .moveDocumentToFolder(details.data, folder.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('تم نقل الملف إلى «${folder.name}»'),
            ),
          );
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isHovered
                  ? const Color(0xFF007AFF).withValues(alpha: 0.10)
                  : (isDark ? const Color(0xFF1C1C1E) : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isHovered
                    ? const Color(0xFF007AFF)
                    : (isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFE5E5EA)),
                width: isHovered ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: folderColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isHovered
                        ? Icons.folder_open_rounded
                        : Icons.folder_rounded,
                    size: 24,
                    color: folderColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folder.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        isHovered ? 'أفلت للنقل إلى هنا' : '$docCount ملف',
                        style: TextStyle(
                          fontSize: 11,
                          color: isHovered
                              ? const Color(0xFF007AFF)
                              : cs.onSurfaceVariant,
                          fontWeight:
                              isHovered ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'خيارات المجلد',
                  icon: Icon(Icons.more_horiz_rounded,
                      color: cs.onSurfaceVariant),
                  onSelected: (action) {
                    if (action == 'rename') onRename();
                    if (action == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.drive_file_rename_outline_rounded,
                              size: 18),
                          SizedBox(width: 8),
                          Text('إعادة تسمية'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded,
                              size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('حذف', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DocumentGridCard extends StatelessWidget {
  const _DocumentGridCard({
    required this.document,
    required this.isInFolder,
    required this.onOpen,
    required this.onPrint,
    required this.onRename,
    required this.onDelete,
    required this.onMoveToFolder,
    required this.onRemoveFromFolder,
  });

  final RemoteDocument document;
  final bool isInFolder;
  final VoidCallback onOpen;
  final VoidCallback onPrint;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMoveToFolder;
  final VoidCallback onRemoveFromFolder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final typeInfo = _getFileTypeInfo(document.fileName);

    final card = InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Top Row: Type badge + FileMenu
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeInfo.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    typeInfo.label,
                    style: TextStyle(
                      color: typeInfo.color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _FileMenu(
                  isInFolder: isInFolder,
                  onOpen: onOpen,
                  onPrint: onPrint,
                  onRename: onRename,
                  onDelete: onDelete,
                  onMoveToFolder: onMoveToFolder,
                  onRemoveFromFolder: onRemoveFromFolder,
                ),
              ],
            ),
            const Spacer(),

            // Center File Icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: typeInfo.color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(typeInfo.icon, color: typeInfo.color, size: 28),
            ),
            const SizedBox(height: 10),

            // File Name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                document.fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 4),

            // Metadata: Size & Date
            Text(
              '${formatFileSize(document.fileSize)} • ${formatDate(document.createdAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurfaceVariant,
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );

    return Draggable<String>(
      data: document.id,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: SizedBox(width: 160, height: 160, child: card),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: card,
    );
  }
}

class _FileListItem extends StatelessWidget {
  const _FileListItem({
    required this.document,
    required this.isInFolder,
    required this.onOpen,
    required this.onPrint,
    required this.onRename,
    required this.onDelete,
    required this.onMoveToFolder,
    required this.onRemoveFromFolder,
  });

  final RemoteDocument document;
  final bool isInFolder;
  final VoidCallback onOpen;
  final VoidCallback onPrint;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMoveToFolder;
  final VoidCallback onRemoveFromFolder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final typeInfo = _getFileTypeInfo(document.fileName);

    final card = InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: typeInfo.color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(typeInfo.icon, color: typeInfo.color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: typeInfo.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          typeInfo.label,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: typeInfo.color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${formatFileSize(document.fileSize)} • ${formatDate(document.createdAt)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (document.pageCount > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '• ${document.pageCount} صفحة',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'فتح المستند',
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              onPressed: onOpen,
              color: cs.onSurfaceVariant,
            ),
            IconButton(
              tooltip: 'طباعة',
              icon: const Icon(Icons.print_outlined, size: 18),
              onPressed: onPrint,
              color: cs.onSurfaceVariant,
            ),
            _FileMenu(
              isInFolder: isInFolder,
              onOpen: onOpen,
              onPrint: onPrint,
              onRename: onRename,
              onDelete: onDelete,
              onMoveToFolder: onMoveToFolder,
              onRemoveFromFolder: onRemoveFromFolder,
            ),
          ],
        ),
      ),
    );

    return Draggable<String>(
      data: document.id,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.4,
            child: card,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: card,
    );
  }
}

enum _FileAction { open, print, rename, delete, moveToFolder, removeFromFolder }

class _FileMenu extends StatelessWidget {
  const _FileMenu({
    required this.isInFolder,
    required this.onOpen,
    required this.onPrint,
    required this.onRename,
    required this.onDelete,
    required this.onMoveToFolder,
    required this.onRemoveFromFolder,
  });

  final bool isInFolder;
  final VoidCallback onOpen;
  final VoidCallback onPrint;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMoveToFolder;
  final VoidCallback onRemoveFromFolder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<_FileAction>(
      tooltip: 'خيارات الملف',
      icon: Icon(Icons.more_horiz_rounded, size: 18, color: cs.onSurfaceVariant),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onSelected: (value) {
        switch (value) {
          case _FileAction.open:
            onOpen();
          case _FileAction.print:
            onPrint();
          case _FileAction.rename:
            onRename();
          case _FileAction.delete:
            onDelete();
          case _FileAction.moveToFolder:
            onMoveToFolder();
          case _FileAction.removeFromFolder:
            onRemoveFromFolder();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _FileAction.open,
          child: Row(
            children: [
              Icon(Icons.open_in_new_rounded, size: 18),
              SizedBox(width: 8),
              Text('فتح المستند'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: _FileAction.print,
          child: Row(
            children: [
              Icon(Icons.print_outlined, size: 18),
              SizedBox(width: 8),
              Text('طباعة'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: _FileAction.moveToFolder,
          child: Row(
            children: [
              Icon(Icons.drive_file_move_outlined, size: 18),
              SizedBox(width: 8),
              Text('نقل لمجلد...'),
            ],
          ),
        ),
        if (isInFolder)
          const PopupMenuItem(
            value: _FileAction.removeFromFolder,
            child: Row(
              children: [
                Icon(Icons.drive_file_move_rtl_outlined, size: 18),
                SizedBox(width: 8),
                Text('إخراج من المجلد'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: _FileAction.rename,
          child: Row(
            children: [
              Icon(Icons.drive_file_rename_outline_rounded, size: 18),
              SizedBox(width: 8),
              Text('إعادة تسمية'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _FileAction.delete,
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('حذف', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminOverviewCard extends StatelessWidget {
  const _AdminOverviewCard({
    required this.usersState,
    required this.onGoToAdmin,
  });

  final AsyncValue<List<ManagedUser>> usersState;
  final VoidCallback onGoToAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ملخص المستخدمين',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(onPressed: onGoToAdmin, child: const Text('التفاصيل')),
            ],
          ),
          const SizedBox(height: 8),
          usersState.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(10),
              child: ShimmerSkeleton(height: 30, borderRadius: 10),
            ),
            error: (e, _) => Text(e.toString()),
            data: (users) {
              final active = users.where((u) => u.isActive).length;
              final inactive = users.length - active;
              final privileged = users
                  .where((u) => u.role == 'manager' || u.role == 'admin')
                  .length;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _AdminMetricChip(
                    icon: Icons.groups_2_outlined,
                    label: 'الكل',
                    value: '${users.length}',
                  ),
                  _AdminMetricChip(
                    icon: Icons.verified_user_outlined,
                    label: 'نشط',
                    value: '$active',
                  ),
                  _AdminMetricChip(
                    icon: Icons.person_off_outlined,
                    label: 'موقوف',
                    value: '$inactive',
                  ),
                  _AdminMetricChip(
                    icon: Icons.admin_panel_settings_outlined,
                    label: 'مدير',
                    value: '$privileged',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FilesDashboardLoading extends StatelessWidget {
  const _FilesDashboardLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: const [
        ShimmerSkeleton(height: 52, borderRadius: 14),
        SizedBox(height: 12),
        ShimmerSkeleton(height: 72, borderRadius: 14),
        SizedBox(height: 12),
        ShimmerSkeleton(height: 42, borderRadius: 10),
        SizedBox(height: 16),
        ShimmerSkeleton(height: 76, borderRadius: 14),
        SizedBox(height: 10),
        ShimmerSkeleton(height: 76, borderRadius: 14),
        SizedBox(height: 10),
        ShimmerSkeleton(height: 76, borderRadius: 14),
      ],
    );
  }
}

class _AdminMetricChip extends StatelessWidget {
  const _AdminMetricChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyFilesState extends StatelessWidget {
  const _EmptyFilesState({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2C2C2E)
                      : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.folder_open_rounded,
                  size: 32,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'لا توجد ملفات في هذا المجلد',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'يمكنك سحب وإفلات الملفات أو استخدام مركز النقل لاستيراد ملفات جديدة.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.tonalIcon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('تحديث القائمة'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
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

class _DownloadProgressBanner extends StatelessWidget {
  const _DownloadProgressBanner({
    required this.fileName,
    required this.progress,
  });

  final String? fileName;
  final double progress;

  @override
  Widget build(BuildContext context) {
    if (progress >= -1) {
      return AppDownloadProgressBanner(fileName: fileName, progress: progress);
    }
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'جاري تنزيل ${fileName ?? 'الملف'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutgoingTransferBanner extends StatelessWidget {
  const _OutgoingTransferBanner({
    required this.fileName,
    required this.targetLabel,
    required this.progress,
    required this.status,
  });

  final String? fileName;
  final String targetLabel;
  final double progress;
  final String status;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3390EC).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.upload_file_rounded,
                    color: Color(0xFF3390EC),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إرسال ${fileName ?? 'الملف'} إلى $targetLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$percent%',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF3390EC),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: progress <= 0 ? null : progress,
                backgroundColor: scheme.surfaceContainerHighest,
                color: const Color(0xFF3390EC),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
