import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/button_loading_indicator.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../models/update_management_models.dart';

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
  String _deviceStatusFilter = 'all';
  String _platformFilter = 'all';
  String _deviceSearch = '';
  bool _excludeCurrentDevice = true;
  String? _currentDeviceUid;

  int _uploadProgress = 0;
  int _uploadTotal = 0;

  List<ManagedUpdateDevice> _devices = const [];
  List<ManagedUpdateRelease> _releases = const [];
  List<ManagedUpdateJob> _jobs = const [];

  String? _selectedReleaseId;
  String _targetType = 'all';
  final Set<String> _selectedDeviceIds = <String>{};

  final _versionController = TextEditingController();
  final _notesController = TextEditingController();
  final _externalUrlController = TextEditingController();
  final _silentArgsController = TextEditingController(
    text: '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-',
  );
  final _targetBranchesController = TextEditingController();
  final _noteController = TextEditingController();

  String _releaseChannel = 'stable';
  String _releasePlatform = 'desktop_windows';
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
      final results = await Future.wait([
        repository.listDevices(
          status: _deviceStatusFilter,
          platform: _platformFilter == 'all' ? null : _platformFilter,
          search: _deviceSearch,
          limit: 200,
        ),
        repository.listReleases(),
        repository.listUpdateJobs(limit: 150),
      ]);
      if (!mounted) return;
      setState(() {
        _devices = results[0] as List<ManagedUpdateDevice>;
        _releases = results[1] as List<ManagedUpdateRelease>;
        _jobs = results[2] as List<ManagedUpdateJob>;
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
        : const ['zip', 'msi', 'exe'];
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
      _showSnack('اختر ملف التحديث أو أدخل رابط تحميل مباشر.', isError: true);
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
      _showSnack('تم إضافة الإصدار وتحديده للتوزيع.');
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
          title: const Text('حذف الإصدار'),
          content: Text(
            'سيتم حذف الإصدار v${release.version} وملف التحديث الخاص به. هل تريد المتابعة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('حذف'),
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
      _showSnack('اختر إصدارا قبل إرسال التحديث.', isError: true);
      return;
    }
    final branches = _targetBranchesController.text
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList();
    final targetDevices = _selectedDeviceIds.toList();
    final excludeUids =
        _excludeCurrentDevice && (_currentDeviceUid?.isNotEmpty ?? false)
        ? <String>[_currentDeviceUid!]
        : const <String>[];

    if (_targetType == 'branch' && branches.isEmpty) {
      _showSnack('أدخل فرعا واحدا على الأقل.', isError: true);
      return;
    }
    if (_targetType == 'devices' && targetDevices.isEmpty) {
      _showSnack('اختر جهازا واحدا على الأقل.', isError: true);
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
      _showSnack('تم إنشاء مهمة التحديث للأجهزة المستهدفة.');
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
        backgroundColor: isError ? const Color(0xFFB42318) : null,
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
  int get _updatingDevices => _devices
      .where((device) => !['idle', 'completed'].contains(device.updateStatus))
      .length;
  int get _failedDevices =>
      _devices.where((device) => device.updateStatus == 'failed').length;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(18),
        children: const [
          ShimmerSkeleton(height: 84, borderRadius: 16),
          SizedBox(height: 12),
          ShimmerSkeleton(height: 260, borderRadius: 16),
          SizedBox(height: 12),
          ShimmerSkeleton(height: 360, borderRadius: 16),
        ],
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1180;
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  _HeaderBar(busy: _busy, onRefresh: _reload),
                  const SizedBox(height: 16),
                  _SectionTabs(
                    value: _selectedSection,
                    onChanged: (value) =>
                        setState(() => _selectedSection = value),
                  ),
                  const SizedBox(height: 16),
                  _buildSelectedSection(wide),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSelectedSection(bool wide) {
    return switch (_selectedSection) {
      'send' => _buildSendSection(wide),
      'devices' => _buildDevicesSection(wide),
      'jobs' => _buildJobsSection(),
      _ => _buildReleasesSection(wide),
    };
  }

  Widget _buildReleasesSection(bool wide) {
    if (!wide) {
      return Column(
        children: [
          _buildReleaseComposer(),
          const SizedBox(height: 16),
          _buildReleaseListPanel(),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 5, child: _buildReleaseComposer()),
        const SizedBox(width: 16),
        Expanded(flex: 6, child: _buildReleaseListPanel()),
      ],
    );
  }

  Widget _buildSendSection(bool wide) {
    if (!wide) {
      return Column(
        children: [
          _buildDistributionPanel(),
          const SizedBox(height: 16),
          _buildDevicesPanel(),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 5, child: _buildDistributionPanel()),
        const SizedBox(width: 16),
        Expanded(flex: 6, child: _buildDevicesPanel()),
      ],
    );
  }

  Widget _buildDevicesSection(bool wide) {
    if (!wide) {
      return Column(
        children: [
          _buildControls(),
          const SizedBox(height: 16),
          _buildDevicesPanel(showAll: true),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 360, child: _buildControls()),
        const SizedBox(width: 16),
        Expanded(child: _buildDevicesPanel(showAll: true)),
      ],
    );
  }

  Widget _buildJobsSection() {
    return Column(
      children: [
        _SummaryStrip(
          devices: _devices.length,
          online: _onlineDevices,
          releases: _filteredReleases.length,
          updating: _updatingDevices,
          failed: _failedDevices,
        ),
        const SizedBox(height: 16),
        _buildJobsPanel(showAll: true),
      ],
    );
  }

  Widget _buildWorkflowColumn() {
    return Column(
      children: [
        _buildReleaseComposer(),
        const SizedBox(height: 16),
        _buildDistributionPanel(),
        const SizedBox(height: 16),
        _buildJobsPanel(),
      ],
    );
  }

  Widget _buildStatusColumn() {
    return Column(
      children: [
        _SummaryStrip(
          devices: _devices.length,
          online: _onlineDevices,
          releases: _filteredReleases.length,
          updating: _updatingDevices,
          failed: _failedDevices,
        ),
        const SizedBox(height: 16),
        _buildControls(),
        const SizedBox(height: 16),
        _buildDevicesPanel(),
      ],
    );
  }

  Widget _buildControls() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(
            icon: Iconsax.filter_search,
            title: 'فلترة الأجهزة',
            subtitle: 'استخدمها عند الإرسال لأجهزة محددة.',
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => _deviceSearch = value.trim(),
            onSubmitted: (_) => _reload(),
            decoration: const InputDecoration(
              hintText: 'بحث باسم الجهاز أو المستخدم',
              prefixIcon: Icon(Iconsax.search_normal),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _FilterMenu(
                  value: _platformFilter,
                  label: 'المنصة',
                  items: const {
                    'all': 'كل المنصات',
                    'desktop_windows': 'Windows',
                    'mobile_android': 'Android',
                  },
                  onChanged: (value) {
                    setState(() => _platformFilter = value);
                    _reload();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FilterMenu(
                  value: _deviceStatusFilter,
                  label: 'الحالة',
                  items: const {
                    'all': 'كل الحالات',
                    'online': 'متصل',
                    'offline': 'غير متصل',
                  },
                  onChanged: (value) {
                    setState(() => _deviceStatusFilter = value);
                    _reload();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _reload,
              icon: const Icon(Iconsax.refresh, size: 18),
              label: const Text('تحديث القائمة'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReleaseComposer() {
    final hasArtifact = _artifactPath != null && _artifactPath!.isNotEmpty;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepHeader(
            number: 1,
            title: 'أضف ملف التحديث',
            subtitle:
                'اكتب رقم الإصدار وارفع الملف. بعد الحفظ سيظهر الإصدار في خطوة الإرسال.',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _versionController,
                  decoration: const InputDecoration(
                    labelText: 'رقم الإصدار',
                    hintText: 'مثال 1.2.0',
                    prefixIcon: Icon(Iconsax.tag),
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FilterMenu(
                  value: _releaseChannel,
                  label: 'القناة',
                  items: const {
                    'stable': 'Stable',
                    'beta': 'Beta',
                    'alpha': 'Alpha',
                    'internal': 'Internal',
                  },
                  onChanged: (value) => setState(() => _releaseChannel = value),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FilterMenu(
                  value: _releasePlatform,
                  label: 'المنصة',
                  items: const {
                    'desktop_windows': 'Windows',
                    'mobile_android': 'Android',
                  },
                  onChanged: (value) {
                    setState(() {
                      _releasePlatform = value;
                      _artifactPath = null;
                      _artifactBytes = null;
                      _artifactFileName = null;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _FileDropSurface(
            fileName: _artifactFileName,
            filePath: _artifactPath,
            platform: _releasePlatform,
            onPick: _busy ? null : _pickArtifact,
            onClear: hasArtifact && !_busy
                ? () {
                    setState(() {
                      _artifactPath = null;
                      _artifactBytes = null;
                      _artifactFileName = null;
                    });
                  }
                : null,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _externalUrlController,
            enabled: !hasArtifact,
            decoration: const InputDecoration(
              labelText: 'رابط تحميل مباشر بديل',
              hintText: 'https://example.com/update.zip',
              prefixIcon: Icon(Iconsax.link),
            ),
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'ملاحظات الإصدار',
              alignLabelWithHint: true,
              prefixIcon: Icon(Iconsax.note_text),
            ),
          ),
          if (_releasePlatform == 'desktop_windows') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _silentArgsController,
              decoration: const InputDecoration(
                labelText: 'وسائط التثبيت الصامت',
                prefixIcon: Icon(Iconsax.code),
              ),
              textDirection: TextDirection.ltr,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InlineSwitch(
                label: 'تفعيل بعد الحفظ',
                value: _releaseEnabled,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _releaseEnabled = value),
              ),
              _InlineSwitch(
                label: 'إجباري',
                value: _releaseMandatory,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _releaseMandatory = value),
              ),
            ],
          ),
          if (_busy && _uploadTotal > 0) ...[
            const SizedBox(height: 12),
            _UploadProgress(current: _uploadProgress, total: _uploadTotal),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _busy ? null : _createRelease,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ButtonLoadingIndicator(),
                    )
                  : const Icon(Iconsax.archive_tick, size: 18),
              label: Text(_busy ? 'جاري الحفظ...' : 'حفظ الإصدار'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReleaseListPanel() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(
            icon: Iconsax.box,
            title: 'الإصدارات المرفوعة',
            subtitle:
                'عدد الإصدارات: ${_filteredReleases.length}. يمكنك اختيار إصدار للإرسال أو إيقافه أو حذفه.',
          ),
          const SizedBox(height: 12),
          if (_filteredReleases.isEmpty)
            const _EmptyState(message: 'لا توجد إصدارات مرفوعة بعد.')
          else
            ..._filteredReleases.map(_buildReleaseTile),
        ],
      ),
    );
  }

  Widget _buildReleaseTile(ManagedUpdateRelease release) {
    final selected = release.id == _selectedReleaseId;
    final statusColor = release.isEnabled
        ? const Color(0xFF16A34A)
        : const Color(0xFF64748B);
    final subtitleParts = <String>[
      release.platform,
      release.channel,
      if (release.fileSize > 0) formatFileSize(release.fileSize),
      if (release.createdAt != null) formatDate(release.createdAt!),
    ];
    return _InsetTile(
      leading: Radio<String>(
        value: release.id,
        groupValue: _selectedReleaseId,
        onChanged: _busy
            ? null
            : (value) => setState(() => _selectedReleaseId = value),
      ),
      title: 'v${release.version}${release.mandatory ? '  •  إجباري' : ''}',
      subtitle: subtitleParts.join('  •  '),
      trailing: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _StatusPill(
            label: release.isEnabled ? 'مفعل' : 'متوقف',
            color: statusColor,
          ),
          Tooltip(
            message: release.isEnabled ? 'إيقاف الإصدار' : 'تفعيل الإصدار',
            child: Switch(
              value: release.isEnabled,
              onChanged: _busy
                  ? null
                  : (value) => _toggleReleaseEnabled(release, value),
            ),
          ),
          IconButton(
            tooltip: selected ? 'الإصدار محدد للإرسال' : 'اختيار للإرسال',
            onPressed: _busy
                ? null
                : () => setState(() => _selectedReleaseId = release.id),
            icon: Icon(
              selected ? Iconsax.tick_circle : Iconsax.send_2,
              color: selected ? const Color(0xFF16A34A) : null,
            ),
          ),
          IconButton(
            tooltip: 'حذف الإصدار',
            onPressed: _busy ? null : () => _deleteRelease(release),
            icon: const Icon(Iconsax.trash, color: Color(0xFFDC2626)),
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionPanel() {
    final releases = _filteredReleases;
    final validSelected =
        _selectedReleaseId != null &&
        releases.any((release) => release.id == _selectedReleaseId);
    if (!validSelected && releases.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedReleaseId = releases.first.id);
      });
    }

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepHeader(
            number: 2,
            title: 'ارسل التحديث',
            subtitle:
                'اختر الإصدار والنطاق. لو اخترت أجهزة محددة، حددها من القائمة الجانبية.',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: releases.isEmpty
                      ? null
                      : (validSelected
                            ? _selectedReleaseId
                            : releases.first.id),
                  decoration: const InputDecoration(
                    labelText: 'الإصدار',
                    prefixIcon: Icon(Iconsax.box),
                  ),
                  items: releases
                      .map(
                        (release) => DropdownMenuItem(
                          value: release.id,
                          child: Text(
                            'v${release.version}  ${release.platform}  ${release.channel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _selectedReleaseId = value),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 190,
                child: _FilterMenu(
                  value: _targetType,
                  label: 'النطاق',
                  items: const {
                    'all': 'كل الأجهزة',
                    'branch': 'حسب الفرع',
                    'devices': 'أجهزة محددة',
                  },
                  onChanged: (value) => setState(() => _targetType = value),
                ),
              ),
            ],
          ),
          if (_targetType == 'branch') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _targetBranchesController,
              decoration: const InputDecoration(
                labelText: 'الفروع',
                hintText: 'main,cairo,alex',
                prefixIcon: Icon(Iconsax.routing),
              ),
              textDirection: TextDirection.ltr,
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'ملاحظة اختيارية للمهمة',
              prefixIcon: Icon(Iconsax.message_text),
            ),
          ),
          if (_currentDeviceUid != null) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _excludeCurrentDevice,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: _busy
                  ? null
                  : (value) =>
                        setState(() => _excludeCurrentDevice = value == true),
              title: const Text('استثناء هذا الجهاز من المهمة'),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _busy ? null : _createUpdateJob,
              icon: const Icon(Iconsax.send_2, size: 18),
              label: const Text('إرسال التحديث الآن'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesPanel({bool showAll = false}) {
    final visibleDevices = showAll ? _devices : _devices.take(12).toList();
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(
            icon: Iconsax.monitor,
            title: 'الأجهزة',
            subtitle: showAll
                ? 'كل الأجهزة المسجلة وحالة كل جهاز.'
                : _targetType == 'devices'
                ? 'حدد الأجهزة التي ستستقبل التحديث.'
                : 'اختيار الأجهزة يعمل عند تحديد نطاق أجهزة محددة.',
          ),
          const SizedBox(height: 10),
          if (_devices.isEmpty)
            const _EmptyState(message: 'لا توجد أجهزة مطابقة للفلاتر الحالية.')
          else ...[
            ...visibleDevices.map(_buildDeviceTile),
            if (!showAll && _devices.length > visibleDevices.length)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'يعرض أول ${visibleDevices.length} جهاز من ${_devices.length}. استخدم البحث للوصول لجهاز معين.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceTile(ManagedUpdateDevice device) {
    final selected = _selectedDeviceIds.contains(device.id);
    final canSelect = _targetType == 'devices';
    final name = device.deviceName ?? device.hostName ?? 'Desktop';
    final user = device.lastKnownFullName ?? device.lastKnownUsername ?? '-';
    return _InsetTile(
      leading: Checkbox(
        value: selected,
        onChanged: canSelect
            ? (value) {
                setState(() {
                  if (value == true) {
                    _selectedDeviceIds.add(device.id);
                  } else {
                    _selectedDeviceIds.remove(device.id);
                  }
                });
              }
            : null,
      ),
      title: '$name  v${device.appVersion}',
      subtitle:
          '$user • ${device.branchCode} • ${device.isOnline ? 'متصل' : 'غير متصل'} • آخر نبضة ${device.lastHeartbeatAt == null ? '-' : formatDate(device.lastHeartbeatAt!)}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusPill(
            label: _statusLabel(device.updateStatus),
            color: _statusColor(device.updateStatus),
          ),
          const SizedBox(width: 8),
          Switch(
            value: device.isActive,
            onChanged: _busy
                ? null
                : (value) => _toggleDeviceActive(device, value),
          ),
        ],
      ),
    );
  }

  Widget _buildJobsPanel({bool showAll = false}) {
    final visibleJobs = showAll ? _jobs : _jobs.take(8).toList();
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepHeader(
            number: 3,
            title: 'تابع التنفيذ',
            subtitle: 'راقب آخر مهام التحديث ونسبة اكتمالها.',
          ),
          const SizedBox(height: 12),
          if (_jobs.isEmpty)
            const _EmptyState(message: 'لم يتم إرسال مهام تحديث بعد.')
          else
            ...visibleJobs.map(_buildJobTile),
        ],
      ),
    );
  }

  Widget _buildJobTile(ManagedUpdateJob job) {
    final completedRatio = job.total <= 0 ? 0.0 : job.completed / job.total;
    final canCancel = job.status == 'running' || job.status == 'queued';
    return _InsetTile(
      leading: _IconBadge(
        icon: Iconsax.flash_1,
        color: _statusColor(job.status),
      ),
      title: 'v${job.releaseVersion} • ${_targetLabel(job.targetType)}',
      subtitle:
          'الإجمالي ${job.total} • اكتمل ${job.completed} • فشل ${job.failed} • ${job.createdAt == null ? '-' : formatDate(job.createdAt!)}',
      trailing: SizedBox(
        width: 180,
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: completedRatio.clamp(0, 1),
                  minHeight: 7,
                ),
              ),
            ),
            if (canCancel) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'إلغاء المهمة',
                onPressed: _busy ? null : () => _cancelJob(job),
                icon: const Icon(Icons.cancel_outlined),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
    'pending' => 'منتظر',
    'acknowledged' => 'تم الاستلام',
    'downloading' => 'تحميل',
    'installing' => 'تثبيت',
    'completed' => 'مكتمل',
    'failed' => 'فشل',
    'cancelled' => 'ملغي',
    'running' => 'قيد التشغيل',
    'queued' => 'في الانتظار',
    'partial_failed' => 'فشل جزئي',
    _ => 'خامل',
  };

  String _targetLabel(String value) => switch (value) {
    'branch' => 'حسب الفرع',
    'devices' => 'أجهزة محددة',
    _ => 'كل الأجهزة',
  };
  Color _statusColor(String status) => switch (status) {
    'completed' => const Color(0xFF16A34A),
    'failed' || 'partial_failed' => const Color(0xFFDC2626),
    'downloading' || 'installing' || 'running' => const Color(0xFF2563EB),
    'cancelled' => const Color(0xFF64748B),
    _ => const Color(0xFF7C3AED),
  };
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.busy, required this.onRefresh});

  final bool busy;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _IconBadge(icon: Iconsax.cloud_change, color: Color(0xFF2563EB)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تحديثات التطبيق',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'أضف إصدار، اختار الأجهزة، وتابع التثبيت من نفس الصفحة.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : onRefresh,
          icon: const Icon(Iconsax.refresh, size: 18),
          label: const Text('تحديث'),
        ),
      ],
    );
  }
}

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = [
      _SectionTabData('releases', 'الإصدارات', Iconsax.box),
      _SectionTabData('send', 'إرسال تحديث', Iconsax.send_2),
      _SectionTabData('devices', 'الأجهزة', Iconsax.monitor),
      _SectionTabData('jobs', 'المهام', Iconsax.activity),
    ];
    return _Panel(
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in items)
            _SectionTabButton(
              data: item,
              selected: value == item.value,
              onTap: () => onChanged(item.value),
            ),
        ],
      ),
    );
  }
}

class _SectionTabData {
  const _SectionTabData(this.value, this.label, this.icon);

  final String value;
  final String label;
  final IconData icon;
}

class _SectionTabButton extends StatelessWidget {
  const _SectionTabButton({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _SectionTabData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF2563EB) : const Color(0xFF475569);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF2563EB).withValues(alpha: 0.12)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF93C5FD) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(data.icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              data.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.devices,
    required this.online,
    required this.releases,
    required this.updating,
    required this.failed,
  });

  final int devices;
  final int online;
  final int releases;
  final int updating;
  final int failed;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(
            icon: Iconsax.status_up,
            title: 'ملخص سريع',
            subtitle: 'أرقام تساعدك قبل إرسال أي تحديث.',
          ),
          const SizedBox(height: 12),
          _MetricRow(
            label: 'الأجهزة',
            value: '$devices',
            icon: Iconsax.monitor,
          ),
          _MetricRow(label: 'متصل الآن', value: '$online', icon: Iconsax.wifi),
          _MetricRow(label: 'الإصدارات', value: '$releases', icon: Iconsax.box),
          _MetricRow(
            label: 'قيد التحديث',
            value: '$updating',
            icon: Iconsax.refresh,
          ),
          _MetricRow(
            label: 'فشل',
            value: '$failed',
            icon: Iconsax.warning_2,
            color: const Color(0xFFDC2626),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    required this.icon,
    this.color = const Color(0xFF2563EB),
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          _IconBadge(icon: icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.color = const Color(0xFF2563EB),
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      width: 180,
      child: Row(
        children: [
          _IconBadge(icon: icon, color: color),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.width});

  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E7EB),
        ),
      ),
      child: child,
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  final int number;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _IconBadge(icon: icon, color: const Color(0xFF2563EB)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InlineSwitch extends StatelessWidget {
  const _InlineSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
  });

  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      items: items.entries
          .map(
            (entry) => DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

class _FileDropSurface extends StatelessWidget {
  const _FileDropSurface({
    required this.fileName,
    required this.filePath,
    required this.platform,
    required this.onPick,
    required this.onClear,
  });

  final String? fileName;
  final String? filePath;
  final String platform;
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasFile = filePath != null && filePath!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const _IconBadge(
            icon: Iconsax.document_upload,
            color: Color(0xFF2563EB),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasFile ? fileName ?? 'ملف تحديث' : 'ملف التحديث',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  hasFile
                      ? filePath!
                      : platform == 'mobile_android'
                      ? 'APK فقط'
                      : 'ZIP أو MSI أو Setup EXE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: hasFile
                      ? TextDirection.ltr
                      : TextDirection.rtl,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          if (onClear != null)
            IconButton(
              tooltip: 'إزالة الملف',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Iconsax.folder_open, size: 18),
            label: Text(hasFile ? 'تغيير' : 'اختيار'),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      onChanged: onChanged,
    );
  }
}

class _UploadProgress extends StatelessWidget {
  const _UploadProgress({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total <= 0 ? 0.0 : current / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Text('جار رفع الإصدار')),
            Text('${formatFileSize(current)} / ${formatFileSize(total)}'),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio.clamp(0, 1),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}

class _InsetTile extends StatelessWidget {
  const _InsetTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 0.6),
        ),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
        ),
      ),
    );
  }
}
