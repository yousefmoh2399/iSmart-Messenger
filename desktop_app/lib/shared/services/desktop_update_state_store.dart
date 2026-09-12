import 'dart:convert';
import 'dart:io';

import 'desktop_update_paths.dart';
import 'desktop_update_state.dart';

class DesktopUpdateStateStore {
  Future<DesktopUpdateState> load() async {
    await DesktopUpdatePaths.ensureInitialized();
    final file = File(DesktopUpdatePaths.stateFilePath);
    if (!file.existsSync()) {
      return DesktopUpdateState.idle();
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return DesktopUpdateState.fromJson(decoded);
      }
      if (decoded is Map) {
        return DesktopUpdateState.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (_) {}
    return DesktopUpdateState.idle();
  }

  Future<void> save(DesktopUpdateState state) async {
    await DesktopUpdatePaths.ensureInitialized();
    final file = File(DesktopUpdatePaths.stateFilePath);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
      flush: true,
    );
  }

  Future<void> markDownloading({
    required String taskId,
    required String releaseId,
    required String targetVersion,
    required String packageType,
    required String installerKind,
    required String packageLayout,
    required String entryExecutable,
    required String silentInstallArgs,
    required String fileName,
    required String currentVersion,
  }) async {
    final current = await load();
    await save(
      current.copyWith(
        status: 'downloading',
        taskId: taskId,
        releaseId: releaseId,
        targetVersion: targetVersion,
        packageType: packageType,
        installerKind: installerKind,
        packageLayout: packageLayout,
        entryExecutable: entryExecutable,
        silentInstallArgs: silentInstallArgs,
        fileName: fileName,
        lastKnownVersion: currentVersion,
        attemptCount: current.attemptCount + 1,
        clearLastError: true,
      ),
    );
  }

  Future<void> markDownloaded({
    required String artifactPath,
    required String artifactSha256,
  }) async {
    final current = await load();
    await save(
      current.copyWith(
        status: 'downloaded',
        artifactPath: artifactPath,
        artifactSha256: artifactSha256,
        clearLastError: true,
      ),
    );
  }

  Future<void> markInstalling() async {
    final current = await load();
    await save(current.copyWith(status: 'installing', clearLastError: true));
  }

  Future<void> markAwaitingHealthcheck() async {
    final current = await load();
    await save(
      current.copyWith(status: 'awaiting_healthcheck', clearLastError: true),
    );
  }

  Future<void> markCompleted(String currentVersion) async {
    final current = await load();
    await save(
      current.copyWith(
        status: 'completed',
        lastKnownVersion: currentVersion,
        clearLastError: true,
      ),
    );
  }

  Future<void> markFailed(String message) async {
    final current = await load();
    await save(current.copyWith(status: 'failed', lastError: message));
  }

  Future<void> markRolledBack(String message) async {
    final current = await load();
    await save(current.copyWith(status: 'rolled_back', lastError: message));
  }

  Future<void> clear() async {
    await save(DesktopUpdateState.idle());
  }
}
