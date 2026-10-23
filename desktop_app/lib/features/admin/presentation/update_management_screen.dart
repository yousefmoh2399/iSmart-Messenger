import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/providers/providers.dart';
import '../models/update_management_models.dart';
import '../../chat/models/chat_models.dart';

class UpdateManagementScreen extends ConsumerStatefulWidget {
  const UpdateManagementScreen({super.key});

  @override
  ConsumerState<UpdateManagementScreen> createState() =>
      _UpdateManagementScreenState();
}

class _UpdateManagementScreenState
    extends ConsumerState<UpdateManagementScreen> {
  bool _loading = true;
  bool _busy = false;
  String _selectedSection = 'releases';
  final String _deviceStatusFilter = 'all';
  final String _platformFilter = 'all';
  String _deviceSearch = '';
  bool _excludeCurrentDevice = false;
  String? _currentDeviceUid;

  int _uploadProgress = 0;
  int _uploadTotal = 0;

  List<ManagedUpdateDevice> _devices = const [];
  List<ManagedUpdateRelease> _releases = const [];
  List<ManagedUpdateJob> _jobs = const [];
  List<BranchSummary> _availableBranches = const [];

  String? _selectedReleaseId;
  String _targetType = 'all';
  final Set<String> _selectedDeviceIds = <String>{};
  final Set<String> _selectedBranchCodes = <String>{};
  String _targetDeviceSearch = '';

  final _versionController = TextEditingController();
  final _notesController = TextEditingController();
  final _externalUrlController = TextEditingController();
  final _silentArgsController = TextEditingController(text: '');
  final _targetBranchesController = TextEditingController();
  final _noteController = TextEditingController();

  String _releaseChannel = 'stable';
  final String _releasePlatform = 'desktop_windows';
  bool _releaseMandatory = false;
  bool _releaseEnabled = true;
  String? _artifactPath;
  Uint8List? _artifactBytes;
  String? _artifactFileName;

  @override
  void initState() {
    super.initState();
    _loadCurrentDeviceUid();
    _reload();
  }

  @override
  void dispose() {
    _versionController.dispose();
    _notesController.dispose();
    _externalUrlController.dispose();
    _silentArgsController.dispose();
    _targetBranchesController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentDeviceUid() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('desktop_update_device_uid');
    if (!mounted) return;
    setState(() {
      _currentDeviceUid = uid == null || uid.trim().isEmpty ? null : uid.trim();
    });
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final repository = ref.read(updateManagementRepositoryProvider);
      final branchFuture = ref
          .read(chatRepositoryProvider)
          .fetchBranches()
          .catchError((_) => <BranchSummary>[]);
      final results = await Future.wait([
        repository.listDevices(
          status: _deviceStatusFilter,
          platform: _platformFilter == 'all' ? null : _platformFilter,
          search: _deviceSearch,
          limit: 200,
        ),
        repository.listReleases(),
        repository.listUpdateJobs(limit: 150),
        branchFuture,
      ]);
      if (!mounted) return;
      setState(() {
        _devices = results[0] as List<ManagedUpdateDevice>;
        _releases = results[1] as List<ManagedUpdateRelease>;
        _jobs = results[2] as List<ManagedUpdateJob>;
        _availableBranches = results[3] as List<BranchSummary>;
        final selectedExists =
            _selectedReleaseId != null &&
            _releases.any((release) => release.id == _selectedReleaseId);
        if (!selectedExists) {
          _selectedReleaseId = _releases.isEmpty ? null : _releases.first.id;
        }
      });
    } catch (error) {
      _showSnack(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickArtifact() async {
    final extensions = _releasePlatform == 'mobile_android'
        ? const ['apk']
        : const ['exe', 'msi', 'zip'];
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      allowMultiple: false,
      withData: kIsWeb,
    );
    final selected = result?.files.single;
    if (selected == null) return;
    if (!kIsWeb && selected.path == null) return;
    if (kIsWeb && selected.bytes == null) return;
    setState(() {
      _artifactPath = selected.path ?? selected.name;
      _artifactBytes = selected.bytes;
      _artifactFileName = selected.name;
      _externalUrlController.clear();
    });
  }

  Future<void> _createRelease() async {
    final version = _versionController.text.trim();
    final externalUrl = _externalUrlController.text.trim();
    if (version.isEmpty) {
      _showSnack('رقم الإصدار مطلوب.', isError: true);
      return;
    }
    if ((_artifactPath == null || _artifactPath!.isEmpty) &&
        externalUrl.isEmpty) {
      _showSnack('اختر ملف التحديث (.exe أو .msi) أو أدخل رابط مباشر.', isError: true);
      return;
    }

    setState(() {
      _busy = true;
      _uploadProgress = 0;
      _uploadTotal = 0;
    });
    try {
      final created = await ref
          .read(updateManagementRepositoryProvider)
          .createRelease(
            version: version,
            channel: _releaseChannel,
            platform: _releasePlatform,
            notes: _notesController.text,
            mandatory: _releaseMandatory,
            isEnabled: _releaseEnabled,
            silentInstallArgs: _releasePlatform == 'desktop_windows'
                ? _silentArgsController.text
                : '',
            artifactFilePath: _artifactPath,
            artifactBytes: _artifactBytes,
            artifactFileName: _artifactFileName,
            externalDownloadUrl: externalUrl,
            onUploadProgress: (currentBytes, totalBytes) {
              if (!mounted) return;
              setState(() {
                _uploadProgress = currentBytes;
                _uploadTotal = totalBytes;
              });
            },
          );
      _resetReleaseForm();
      await _reload();
      if (!mounted) return;
      setState(() => _selectedReleaseId = created.id);
      _showSnack('تم إضافة الإصدار الجديد بنجاح.');
    } catch (error) {
      _showSnack(error.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _uploadProgress = 0;
          _uploadTotal = 0;
        });
      }
    }
  }

  void _resetReleaseForm() {
    _versionController.clear();
    _notesController.clear();
    _externalUrlController.clear();
    _artifactPath = null;
    _artifactBytes = null;
    _artifactFileName = null;
    _releaseMandatory = false;
    _releaseEnabled = true;
  }

  Future<void> _toggleDeviceActive(
    ManagedUpdateDevice device,
    bool isActive,
  ) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(updateManagementRepositoryProvider)
          .setDeviceActive(device.id, isActive);
      await _reload();
    } catch (error) {
      _showSnack(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleReleaseEnabled(
    ManagedUpdateRelease release,
    bool enabled,
  ) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(updateManagementRepositoryProvider)
          .updateRelease(releaseId: release.id, isEnabled: enabled);
      await _reload();
    } catch (error) {
      _showSnack(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteRelease(ManagedUpdateRelease release) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('حذف الإصدار'),
          content: Text(
            'سيتم حذف الإصدار v${release.version} وملف التحديث الخاص به نهائياً. هل أنت متأكد؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('حذف نهائي'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(updateManagementRepositoryProvider)
          .deleteRelease(release.id);
      if (_selectedReleaseId == release.id) {
        _selectedReleaseId = null;
      }
      await _reload();
      _showSnack('تم حذف الإصدار.');
    } catch (error) {
      _showSnack(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createUpdateJob() async {
    if (_selectedReleaseId == null || _selectedReleaseId!.isEmpty) {
      _showSnack('اختر إصداراً أولاً لإرسال التحديث.', isError: true);
      return;
    }
    final textBranches = _targetBranchesController.text
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty);
    final branches = <String>{
      ..._selectedBranchCodes,
      ...textBranches,
    }.toList();

    final targetDevices = _selectedDeviceIds.toList();
    final excludeUids =
        _excludeCurrentDevice && (_currentDeviceUid?.isNotEmpty ?? false)
        ? <String>[_currentDeviceUid!]
        : const <String>[];

    if (_targetType == 'branch' && branches.isEmpty) {
      _showSnack('اختر فرعاً واحداً على الأقل من القائمة أدناه.', isError: true);
      return;
    }
    if (_targetType == 'devices' && targetDevices.isEmpty) {
      _showSnack('اختر جهازاً واحداً على الأقل من قائمة الأجهزة أدناه.', isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(updateManagementRepositoryProvider)
          .createUpdateJob(
            releaseId: _selectedReleaseId!,
            targetType: _targetType,
            targetBranches: branches,
            targetDeviceIds: targetDevices,
            excludeDeviceUids: excludeUids,
            note: _noteController.text,
          );
      _noteController.clear();
      await _reload();
      _showSnack('تم إطلاق مهمة التوزيع لأجهزة المنظومة بنجاح.');
    } catch (error) {
      _showSnack(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelJob(ManagedUpdateJob job) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(updateManagementRepositoryProvider)
          .cancelUpdateJob(job.id);
      await _reload();
      _showSnack('تم إلغاء مهمة التحديث.');
    } catch (error) {
      _showSnack(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  List<ManagedUpdateRelease> get _filteredReleases {
    final seen = <String>{};
    final unique = <ManagedUpdateRelease>[];
    for (final release in _releases) {
      final key = '${release.version}|${release.platform}|${release.channel}';
      if (seen.add(key)) unique.add(release);
    }
    if (_platformFilter == 'all') return unique;
    return unique
        .where((release) => release.platform == _platformFilter)
        .toList();
  }

  int get _onlineDevices => _devices.where((device) => device.isOnline).length;
  int get _failedDevices =>
      _devices.where((device) => device.updateStatus == 'failed').length;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading && _releases.isEmpty && _devices.isEmpty) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1060;
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                children: [
                  _buildHeader(isDark),
                  const SizedBox(height: 18),
                  _buildMetricsStrip(isDark),
                  const SizedBox(height: 18),
                  _buildSectionTabs(isDark),
                  const SizedBox(height: 18),
                  _buildActiveSectionContent(wide, isDark),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Iconsax.refresh_2,
            color: Theme.of(context).colorScheme.primary,
            size: 26,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'إدارة التحديثات ونشر الإصدارات',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'رفع وتوزيع حزم التحديثات (.exe) ومراقبة أجهزة المنظومة في الشبكة الداخلية',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _reload,
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Iconsax.refresh, size: 18),
          label: const Text('تحديث البيانات'),
        ),
      ],
    );
  }

  Widget _buildMetricsStrip(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final children = [
          _buildMetricCard(
            isDark: isDark,
            icon: Iconsax.monitor,
            iconColor: const Color(0xFF10B981),
            title: 'الأجهزة المتصلة',
            value: '$_onlineDevices / ${_devices.length}',
            subtitle: '${_devices.length - _onlineDevices} غير متصل حالياً',
          ),
          _buildMetricCard(
            isDark: isDark,
            icon: Iconsax.box,
            iconColor: const Color(0xFF38BDF8),
            title: 'إصدارات المنظومة',
            value: '${_releases.length}',
            subtitle: _releases.isNotEmpty ? 'أحدث إصدار: v${_releases.first.version}' : 'لا توجد إصدارات',
          ),
          _buildMetricCard(
            isDark: isDark,
            icon: Iconsax.task,
            iconColor: const Color(0xFFF59E0B),
            title: 'مهام التوزيع',
            value: '${_jobs.length}',
            subtitle: '${_jobs.where((j) => j.status == 'in_progress' || j.status == 'running').length} قيد التشغيل',
          ),
          _buildMetricCard(
            isDark: isDark,
            icon: Iconsax.status,
            iconColor: const Color(0xFF8B5CF6),
            title: 'حالة التحديث',
            value: '${_devices.length - _failedDevices} مستقرة',
            subtitle: _failedDevices > 0 ? '$_failedDevices بحاجة لإعادة محاولة' : 'كل الأجهزة مستقرة',
          ),
        ];

        if (wide) {
          return Row(
            children: children
                .map((card) => Expanded(child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: card,
                    )))
                .toList(),
          );
        } else {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: children
                .map((card) => SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: card,
                    ))
                .toList(),
          );
        }
      },
    );
  }

  Widget _buildMetricCard({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTabs(bool isDark) {
    final tabs = [
      {'id': 'releases', 'label': 'الإصدارات والرفع', 'icon': Iconsax.box},
      {'id': 'jobs', 'label': 'مهام التوزيع (Rollout)', 'icon': Iconsax.send_2},
      {'id': 'devices', 'label': 'أجهزة المنظومة (Fleet)', 'icon': Iconsax.monitor},
    ];

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: tabs.map((tab) {
          final isSelected = _selectedSection == tab['id'];
          final color = isSelected
              ? Theme.of(context).colorScheme.primary
              : (isDark ? Colors.white70 : const Color(0xFF64748B));
          return Expanded(
            child: InkWell(
              onTap: () => setState(() => _selectedSection = tab['id'] as String),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(tab['icon'] as IconData, size: 18, color: color),
                    const SizedBox(width: 8),
                    Text(
                      tab['label'] as String,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActiveSectionContent(bool wide, bool isDark) {
    return switch (_selectedSection) {
      'jobs' => _buildJobsSection(wide, isDark),
      'devices' => _buildDevicesSection(wide, isDark),
      _ => _buildReleasesSection(wide, isDark),
    };
  }

  // --- TAB 1: RELEASES & UPLOAD ---
  Widget _buildReleasesSection(bool wide, bool isDark) {
    if (!wide) {
      return Column(
        children: [
          _buildReleaseUploader(isDark),
          const SizedBox(height: 18),
          _buildReleasesCatalog(isDark),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 5, child: _buildReleaseUploader(isDark)),
        const SizedBox(width: 18),
        Expanded(flex: 6, child: _buildReleasesCatalog(isDark)),
      ],
    );
  }

  Widget _buildReleaseUploader(bool isDark) {
    final hasArtifact = _artifactPath != null && _artifactPath!.isNotEmpty;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Iconsax.cloud_add, color: primaryColor, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'رفع حزمة تحديث جديدة (.exe / .msi)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // File Picker Zone
          InkWell(
            onTap: _busy ? null : _pickArtifact,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: hasArtifact
                    ? const Color(0xFF10B981).withValues(alpha: 0.08)
                    : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasArtifact
                      ? const Color(0xFF10B981).withValues(alpha: 0.4)
                      : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    hasArtifact ? Icons.check_circle_rounded : Iconsax.document_upload,
                    color: hasArtifact ? const Color(0xFF10B981) : primaryColor,
                    size: 38,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    hasArtifact
                        ? (_artifactFileName ?? 'تم تحديد ملف التحديث')
                        : 'انقر لاختيار ملف التحديث من جهازك (.exe أو .msi)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: hasArtifact ? const Color(0xFF10B981) : (isDark ? Colors.white : const Color(0xFF0F172A)),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (hasArtifact) ...[
                    const SizedBox(height: 4),
                    Text(
                      'الملف جاهز للرفع والتحقق الرقمي',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Inputs row: Version + Channel
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _versionController,
                  decoration: InputDecoration(
                    labelText: 'رقم الإصدار (مثل 1.2.0)',
                    prefixIcon: const Icon(Iconsax.tag, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _releaseChannel,
                  decoration: InputDecoration(
                    labelText: 'القناة',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'stable', child: Text('Stable')),
                    DropdownMenuItem(value: 'beta', child: Text('Beta')),
                    DropdownMenuItem(value: 'internal', child: Text('Internal')),
                  ],
                  onChanged: (val) => setState(() => _releaseChannel = val ?? 'stable'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Release Notes
          TextField(
            controller: _notesController,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'سجل التغييرات ومميزات التحديث',
              hintText: 'اكتب ما تم إضافته أو إصلاحه في هذا الإصدار...',
              alignLabelWithHint: true,
              prefixIcon: const Icon(Iconsax.note_text, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),

          // Toggles: Mandatory & Enabled
          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  title: const Text('تفعيل الإصدار فوراً', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  value: _releaseEnabled,
                  contentPadding: EdgeInsets.zero,
                  onChanged: _busy ? null : (v) => setState(() => _releaseEnabled = v),
                ),
              ),
              Expanded(
                child: SwitchListTile(
                  title: const Text('تحديث إجباري', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  value: _releaseMandatory,
                  contentPadding: EdgeInsets.zero,
                  onChanged: _busy ? null : (v) => setState(() => _releaseMandatory = v),
                ),
              ),
            ],
          ),

          // Upload progress bar if busy
          if (_busy && _uploadTotal > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: _uploadProgress / _uploadTotal,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'جارٍ الرفع: ${formatFileSize(_uploadProgress)} من ${formatFileSize(_uploadTotal)}',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
            ),
          ],
          const SizedBox(height: 16),

          // Submit Button
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _busy ? null : _createRelease,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Iconsax.direct_up, size: 20),
              label: Text(
                _busy ? 'جارٍ رفع الحزمة وحفظ الإصدار...' : 'نشر الإصدار الجديد',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReleasesCatalog(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Iconsax.box, size: 20, color: Color(0xFF38BDF8)),
              const SizedBox(width: 10),
              Text(
                'قائمة الإصدارات المتوفرة (${_filteredReleases.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_filteredReleases.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: Text(
                'لا توجد إصدارات مسجلة حتى الآن.',
                style: TextStyle(color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
              ),
            )
          else
            ..._filteredReleases.map((release) => _buildReleaseCard(release, isDark)),
        ],
      ),
    );
  }

  Widget _buildReleaseCard(ManagedUpdateRelease release, bool isDark) {
    final isSelected = release.id == _selectedReleaseId;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
            : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
              : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'v${release.version}',
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ),
              const SizedBox(width: 8),
              if (release.mandatory)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'إجباري',
                    style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              const Spacer(),
              Tooltip(
                message: release.isEnabled ? 'الإصدار مفعل' : 'الإصدار متوقف',
                child: Switch(
                  value: release.isEnabled,
                  onChanged: _busy ? null : (v) => _toggleReleaseEnabled(release, v),
                ),
              ),
              IconButton(
                tooltip: 'حذف الإصدار',
                icon: const Icon(Iconsax.trash, size: 18, color: Color(0xFFEF4444)),
                onPressed: _busy ? null : () => _deleteRelease(release),
              ),
            ],
          ),
          if (release.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              release.notes.trim(),
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : const Color(0xFF475569),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'المنصة: ${release.platform} • الحجم: ${formatFileSize(release.fileSize)}',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                ),
              ),
              const Spacer(),
              FilledButton.tonal(
                onPressed: _busy
                    ? null
                    : () {
                        setState(() {
                          _selectedReleaseId = release.id;
                          _selectedSection = 'jobs';
                        });
                      },
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                ),
                child: const Text('توزيع هذا الإصدار', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- TAB 2: ROLLOUT JOBS ---
  Widget _buildJobsSection(bool wide, bool isDark) {
    return Column(
      children: [
        _buildRolloutLauncher(isDark),
        const SizedBox(height: 18),
        _buildJobsHistory(isDark),
      ],
    );
  }

  Widget _buildRolloutLauncher(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Iconsax.send_square, size: 20, color: Color(0xFFF59E0B)),
              const SizedBox(width: 10),
              const Text(
                'إطلاق مهمة ترقية جديدة لأجهزة المنظومة',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _selectedReleaseId,
                  decoration: InputDecoration(
                    labelText: 'الإصدار المراد توزيعه',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _releases.map((release) {
                    return DropdownMenuItem(
                      value: release.id,
                      child: Text('v${release.version} (${release.platform})'),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedReleaseId = val),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _targetType,
                  decoration: InputDecoration(
                    labelText: 'نطاق التوزيع',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('كل أجهزة المنظومة')),
                    DropdownMenuItem(value: 'branch', child: Text('فروع محددة')),
                    DropdownMenuItem(value: 'devices', child: Text('أجهزة محددة')),
                  ],
                  onChanged: (val) => setState(() => _targetType = val ?? 'all'),
                ),
              ),
            ],
          ),
          if (_targetType == 'branch') ...[
            const SizedBox(height: 16),
            _buildBranchSelector(isDark),
          ],
          if (_targetType == 'devices') ...[
            const SizedBox(height: 16),
            _buildDeviceSelector(isDark),
          ],
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: const Color(0xFF8B5CF6),
            title: const Text(
              'استثناء جهازي الحالي من التحديث التلقائي',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Text(
              _currentDeviceUid != null && _currentDeviceUid!.isNotEmpty
                  ? 'معرف جهازك: $_currentDeviceUid'
                  : 'تفعيل هذا الخيار يمنع تحديث جهاز الإدارة الحالي',
              style: const TextStyle(fontSize: 12),
            ),
            value: _excludeCurrentDevice,
            onChanged: (val) => setState(() => _excludeCurrentDevice = val),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            decoration: InputDecoration(
              labelText: 'ملاحظة أو تعليمات التوزيع (اختياري)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _createUpdateJob,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Iconsax.play, size: 18),
            label: const Text('بدء مهمة التوزيع الآن', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildJobsHistory(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Iconsax.activity, size: 20, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 10),
              Text(
                'سجل مهام التوزيع السابقة والجارية (${_jobs.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_jobs.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: Text(
                'لا توجد مهام توزيع مسجلة.',
                style: TextStyle(color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
              ),
            )
          else
            ..._jobs.map((job) => _buildJobCard(job, isDark)),
        ],
      ),
    );
  }

  Widget _buildJobCard(ManagedUpdateJob job, bool isDark) {
    final isRunning = job.status == 'running' || job.status == 'in_progress';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRunning
              ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
              : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (isRunning ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isRunning ? Iconsax.refresh_right_square : Icons.check_circle_outline_rounded,
              color: isRunning ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'المهمة: ${job.id.substring(0, job.id.length > 8 ? 8 : job.id.length)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (isRunning ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isRunning ? 'قيد التنفيذ' : (job.status == 'cancelled' ? 'ملغية' : 'مكتملة'),
                        style: TextStyle(
                          color: isRunning ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'النطاق: ${job.targetType} • الأجهزة: ${job.total} (مكتمل: ${job.completed} • قيد التنزيل: ${job.downloading})',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          if (isRunning)
            TextButton(
              onPressed: _busy ? null : () => _cancelJob(job),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('إلغاء المهمة'),
            ),
        ],
      ),
    );
  }

  // --- TAB 3: FLEET DEVICES ---
  Widget _buildDevicesSection(bool wide, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Iconsax.monitor, size: 20, color: Color(0xFF10B981)),
              const SizedBox(width: 10),
              Text(
                'أجهزة المنظومة في الشبكة (${_devices.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              // Search field
              SizedBox(
                width: 280,
                height: 42,
                child: TextField(
                  onChanged: (v) {
                    _deviceSearch = v.trim();
                  },
                  onSubmitted: (_) => _reload(),
                  decoration: InputDecoration(
                    hintText: 'بحث باسم الجهاز أو المستخدم...',
                    prefixIcon: const Icon(Iconsax.search_normal, size: 16),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_devices.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: Text(
                'لم يتم العثور على أجهزة مطابقة للبحث.',
                style: TextStyle(color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
              ),
            )
          else
            ..._devices.map((device) => _buildDeviceCard(device, isDark)),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(ManagedUpdateDevice device, bool isDark) {
    final name = (device.deviceName?.isNotEmpty == true)
        ? device.deviceName!
        : (device.hostName?.isNotEmpty == true ? device.hostName! : 'جهاز غير مسمى');
    final userName = device.lastKnownFullName ?? device.lastKnownUsername ?? '-';
    final ip = device.localIp ?? '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          // Online dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: device.isOnline ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'v${device.appVersion}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF38BDF8),
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'المستخدم: ' + userName + ' • الفرع: ' + device.branchCode + ' • IP: ' + ip,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Tooltip(
            message: device.isActive ? 'تعطيل الجهاز من التحديثات' : 'تفعيل الجهاز',
            child: Switch(
              value: device.isActive,
              onChanged: _busy ? null : (v) => _toggleDeviceActive(device, v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchSelector(bool isDark) {
    // Gather all unique branch codes from both _availableBranches and _devices
    final branchMap = <String, String>{};
    for (final b in _availableBranches) {
      if (b.code.isNotEmpty) {
        branchMap[b.code] = b.name.isNotEmpty ? b.name : b.code;
      }
    }
    for (final d in _devices) {
      if (d.branchCode.isNotEmpty && !branchMap.containsKey(d.branchCode)) {
        branchMap[d.branchCode] = d.branchCode;
      }
    }
    if (branchMap.isEmpty) {
      branchMap['main'] = 'الفرع الرئيسي (main)';
    }

    final allCodes = branchMap.keys.toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Iconsax.buildings, size: 18, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 8),
              const Text(
                'اختر الفروع المستهدفة بالتحديث:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_selectedBranchCodes.length == allCodes.length) {
                      _selectedBranchCodes.clear();
                    } else {
                      _selectedBranchCodes.addAll(allCodes);
                    }
                  });
                },
                child: Text(
                  _selectedBranchCodes.length == allCodes.length
                      ? 'إلغاء تحديد الكل'
                      : 'تحديد كل الفروع (${allCodes.length})',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: allCodes.map((code) {
              final name = branchMap[code]!;
              final deviceCount = _devices.where((d) => d.branchCode == code).length;
              final isSelected = _selectedBranchCodes.contains(code);
              return FilterChip(
                selected: isSelected,
                selectedColor: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                checkmarkColor: const Color(0xFF8B5CF6),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name == code ? code : '$name ($code)',
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? const Color(0xFF8B5CF6) : null,
                      ),
                    ),
                    if (deviceCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF8B5CF6)
                              : (isDark ? Colors.white12 : Colors.black12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$deviceCount أجهزة',
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected ? Colors.white : null,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedBranchCodes.add(code);
                    } else {
                      _selectedBranchCodes.remove(code);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _targetBranchesController,
            decoration: InputDecoration(
              labelText: 'إضافة فروع إضافية يدويًا (اختياري، مفصولة بفاصلة)',
              hintText: 'مثال: branch1, branch2',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceSelector(bool isDark) {
    final query = _targetDeviceSearch.trim().toLowerCase();
    final filtered = _devices.where((d) {
      if (query.isEmpty) return true;
      final name = (d.deviceName ?? '').toLowerCase();
      final host = (d.hostName ?? '').toLowerCase();
      final user = (d.lastKnownUsername ?? '').toLowerCase();
      final branch = d.branchCode.toLowerCase();
      final ip = (d.localIp ?? '').toLowerCase();
      return name.contains(query) ||
          host.contains(query) ||
          user.contains(query) ||
          branch.contains(query) ||
          ip.contains(query);
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Iconsax.monitor, size: 18, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 8),
              const Text(
                'اختر الأجهزة المستهدفة بالتحديث:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'تم اختيار ${_selectedDeviceIds.length} من أصل ${_devices.length} جهاز',
                  style: const TextStyle(
                    color: Color(0xFF8B5CF6),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (val) => setState(() => _targetDeviceSearch = val),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Iconsax.search_normal, size: 18),
                    hintText: 'بحث باسم الجهاز أو الموظف أو الفرع أو IP...',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    final allVisibleIds = filtered.map((d) => d.id).toSet();
                    if (_selectedDeviceIds.containsAll(allVisibleIds)) {
                      _selectedDeviceIds.removeAll(allVisibleIds);
                    } else {
                      _selectedDeviceIds.addAll(allVisibleIds);
                    }
                  });
                },
                child: Text(
                  _selectedDeviceIds.containsAll(filtered.map((d) => d.id).toSet()) && filtered.isNotEmpty
                      ? 'إلغاء تحديد الكل'
                      : 'تحديد الكل',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _devices.isEmpty
                            ? 'لا توجد أجهزة مسجلة في النظام حتى الآن.'
                            : 'لا توجد أجهزة مطابقة للبحث.',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final device = filtered[index];
                        final isSelected = _selectedDeviceIds.contains(device.id);
                        final displayName = device.deviceName?.isNotEmpty == true
                            ? device.deviceName!
                            : (device.hostName ?? 'جهاز بدون اسم');
                        final userName = device.lastKnownFullName?.isNotEmpty == true
                            ? device.lastKnownFullName!
                            : (device.lastKnownUsername ?? 'غير معروف');

                        return CheckboxListTile(
                          dense: true,
                          value: isSelected,
                          activeColor: const Color(0xFF8B5CF6),
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedDeviceIds.add(device.id);
                              } else {
                                _selectedDeviceIds.remove(device.id);
                              }
                            });
                          },
                          secondary: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.15)
                                  : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.computer_rounded,
                              size: 20,
                              color: isSelected ? const Color(0xFF8B5CF6) : (device.isOnline ? Colors.green : Colors.grey),
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                displayName,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: device.isOnline ? Colors.green : Colors.grey.shade400,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white10 : Colors.black12,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'الإصدار: ${device.appVersion}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            'الموظف: $userName • الفرع: ${device.branchCode} • IP: ${device.localIp ?? "غير معروف"}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
