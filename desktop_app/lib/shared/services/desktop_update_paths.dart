import 'dart:io';

import 'package:path/path.dart' as path;

class DesktopUpdatePaths {
  DesktopUpdatePaths._();

  static String get installRoot => path.dirname(Platform.resolvedExecutable);

  static String get updateDataRoot => path.join(installRoot, 'update-data');

  static String get downloadsRoot => path.join(updateDataRoot, 'downloads');

  static String get backupRoot => path.join(updateDataRoot, 'backup');

  static String get logsRoot => path.join(updateDataRoot, 'logs');

  static String get runtimeHelperRoot =>
      path.join(updateDataRoot, 'runtime-helper');

  static String get stateFilePath => path.join(updateDataRoot, 'state.json');

  static String get helperResultFilePath =>
      path.join(updateDataRoot, 'helper-result.json');

  static Future<void> ensureInitialized() async {
    for (final target in <String>[
      updateDataRoot,
      downloadsRoot,
      backupRoot,
      logsRoot,
      runtimeHelperRoot,
    ]) {
      await Directory(target).create(recursive: true);
    }
  }
}
