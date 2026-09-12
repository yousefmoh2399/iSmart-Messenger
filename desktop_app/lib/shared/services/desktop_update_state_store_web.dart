// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;
import 'desktop_update_state.dart';

class DesktopUpdateStateStore {
  static const _key = 'desktop_update_state_json';

  Future<DesktopUpdateState> load() async {
    try {
      final data = html.window.localStorage[_key];
      if (data != null && data.trim().isNotEmpty) {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) {
          return DesktopUpdateState.fromJson(decoded);
        }
      }
    } catch (_) {}
    return DesktopUpdateState.idle();
  }

  Future<void> save(DesktopUpdateState state) async {
    try {
      html.window.localStorage[_key] = jsonEncode(state.toJson());
    } catch (_) {}
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
      ),
    );
  }

  Future<void> markInstalling() async {
    final current = await load();
    await save(current.copyWith(status: 'installing'));
  }

  Future<void> markAwaitingHealthcheck() async {
    final current = await load();
    await save(current.copyWith(status: 'awaiting_healthcheck'));
  }

  Future<void> markCompleted(String currentVersion) async {
    final current = await load();
    await save(
      current.copyWith(status: 'completed', lastKnownVersion: currentVersion),
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
    try {
      html.window.localStorage.remove(_key);
    } catch (_) {}
  }
}
