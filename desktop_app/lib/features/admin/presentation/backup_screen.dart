import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/button_loading_indicator.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../models/backup_archive.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  late Future<List<BackupArchive>> _backupsFuture;
  bool _creating = false;
  String? _busyBackupName;
  int _downloadedBytes = 0;
  int _downloadTotalBytes = 0;
  bool _restoringUpload = false;
  int _restoreUploadedBytes = 0;
  int _restoreTotalBytes = 0;
  String? _restoreFileName;

  @override
  void initState() {
    super.initState();
    _backupsFuture = _loadBackups();
  }

  Future<List<BackupArchive>> _loadBackups() {
    return ref.read(backupRepositoryProvider).listBackups();
  }

  Future<void> _refresh() async {
    setState(() {
      _backupsFuture = _loadBackups();
    });
    await _backupsFuture;
  }

  Future<void> _createBackup() async {
    if (_creating) {
      return;
    }
    setState(() => _creating = true);
    try {
      final backup = await ref.read(backupRepositoryProvider).createBackup();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup created: ${backup.name}')));
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  Future<void> _restoreBackupFromFile() async {
    if (_restoringUpload || _busyBackupName != null) {
      return;
    }
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      allowMultiple: false,
      withData: kIsWeb,
    );
    final pickedFile = picked?.files.single;
    final filePath = pickedFile?.path;
    if (pickedFile == null) {
      return;
    }
    if (!kIsWeb && (filePath == null || filePath.trim().isEmpty)) {
      return;
    }
    if (kIsWeb && pickedFile.bytes == null) {
      return;
    }
    if (!mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup'),
        content: Text('This will restore from:\n${pickedFile.name}\nContinue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      _restoringUpload = true;
      _restoreUploadedBytes = 0;
      _restoreTotalBytes = 0;
      _restoreFileName = pickedFile.name;
    });
    try {
      await ref
          .read(backupRepositoryProvider)
          .restoreBackupFromFile(
            filePath ?? pickedFile.name,
            fileBytes: pickedFile.bytes,
            fileName: pickedFile.name,
            onProgress: (sent, total) {
              if (!mounted) return;
              setState(() {
                _restoreUploadedBytes = sent;
                _restoreTotalBytes = total;
              });
            },
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup restored successfully.')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _restoringUpload = false;
          _restoreUploadedBytes = 0;
          _restoreTotalBytes = 0;
          _restoreFileName = null;
        });
      }
    }
  }

  Future<void> _downloadBackup(BackupArchive backup) async {
    if (_busyBackupName != null) {
      return;
    }
    setState(() {
      _busyBackupName = backup.name;
      _downloadedBytes = 0;
      _downloadTotalBytes = 0;
    });
    try {
      final filePath = await ref
          .read(backupRepositoryProvider)
          .downloadBackup(
            backup.name,
            onProgress: (received, total) {
              if (!mounted) {
                return;
              }
              setState(() {
                _downloadedBytes = received;
                _downloadTotalBytes = total;
              });
            },
          );
      if (filePath.isEmpty) {
        return;
      }
      if (!kIsWeb) {
        await OpenFilex.open(filePath);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم حفظ النسخة: ${backup.name}')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _busyBackupName = null;
          _downloadedBytes = 0;
          _downloadTotalBytes = 0;
        });
      }
    }
  }

  Future<void> _restoreBackup(BackupArchive backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup'),
        content: Text(
          'This will replace database and stored files with "${backup.name}". Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() => _busyBackupName = backup.name);
    try {
      await ref
          .read(backupRepositoryProvider)
          .restoreBackup(backupFileName: backup.name, confirmRestore: true);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup restored successfully.')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _busyBackupName = null);
      }
    }
  }

  Future<void> _deleteBackup(BackupArchive backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete backup'),
        content: Text('Delete "${backup.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() => _busyBackupName = backup.name);
    try {
      await ref.read(backupRepositoryProvider).deleteBackup(backup.name);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup deleted: ${backup.name}')));
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _busyBackupName = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: _creating ? null : _createBackup,
                icon: _creating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ButtonLoadingIndicator(),
                      )
                    : const Icon(Iconsax.document_upload5),
                label: Text(_creating ? 'Creating backup...' : 'Create Backup'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _restoringUpload ? null : _restoreBackupFromFile,
                icon: _restoringUpload
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ButtonLoadingIndicator(),
                      )
                    : const Icon(Iconsax.import_1),
                label: Text(
                  _restoringUpload ? 'Restoring...' : 'Restore from File',
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Iconsax.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          if (_restoringUpload)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _restoreFileName == null
                            ? 'Uploading backup...'
                            : 'Uploading ${_restoreFileName!}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _restoreTotalBytes > 0
                            ? _restoreUploadedBytes / _restoreTotalBytes
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _restoreTotalBytes > 0
                            ? '${formatFileSize(_restoreUploadedBytes)} / ${formatFileSize(_restoreTotalBytes)} (${((_restoreUploadedBytes / _restoreTotalBytes) * 100).clamp(0, 100).toStringAsFixed(1)}%)'
                            : 'Uploading...',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<BackupArchive>>(
              future: _backupsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return ListView(
                    children: const [
                      ShimmerSkeleton(height: 74, borderRadius: 12),
                      SizedBox(height: 10),
                      ShimmerSkeleton(height: 74, borderRadius: 12),
                      SizedBox(height: 10),
                      ShimmerSkeleton(height: 74, borderRadius: 12),
                    ],
                  );
                }
                if (snapshot.hasError) {
                  return Center(child: Text(snapshot.error.toString()));
                }

                final backups = snapshot.data ?? const <BackupArchive>[];
                if (backups.isEmpty) {
                  return const Center(child: Text('No backups found.'));
                }

                return ListView.separated(
                  itemCount: backups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final backup = backups[index];
                    final busy = _busyBackupName == backup.name;
                    return Card(
                      child: Column(
                        children: [
                          ListTile(
                            title: Text(
                              backup.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${formatDate(backup.createdAt)} • ${formatFileSize(backup.size)}',
                            ),
                            trailing: Wrap(
                              spacing: 8,
                              children: [
                                TextButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => _downloadBackup(backup),
                                  icon: const Icon(Iconsax.document_download5),
                                  label: const Text('Download'),
                                ),
                                TextButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => _restoreBackup(backup),
                                  icon: const Icon(Iconsax.refresh5),
                                  label: const Text('Restore'),
                                ),
                                TextButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => _deleteBackup(backup),
                                  icon: const Icon(Iconsax.save_remove),
                                  label: const Text('Delete'),
                                ),
                              ],
                            ),
                          ),
                          if (busy)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LinearProgressIndicator(
                                    value: _downloadTotalBytes > 0
                                        ? _downloadedBytes / _downloadTotalBytes
                                        : null,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _downloadTotalBytes > 0
                                        ? '${formatFileSize(_downloadedBytes)} / ${formatFileSize(_downloadTotalBytes)} (${((_downloadedBytes / _downloadTotalBytes) * 100).clamp(0, 100).toStringAsFixed(1)}%)'
                                        : 'Downloading...',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
