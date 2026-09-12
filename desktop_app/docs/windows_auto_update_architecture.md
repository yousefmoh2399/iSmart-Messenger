# Windows Auto Update Architecture

## 1. Final Technical Decision

- Use `Inno Setup` or the existing installer generator only for the first install.
- Stop shipping installer-per-update for normal desktop updates.
- Ship a `full package ZIP` for each update, generated from the complete Flutter Windows release bundle.
- Keep the existing `Node.js + MongoDB + socket` coordination layer.
- Perform Windows updates through a separate helper executable: `ismart_messenger_updater.exe`.
- Install under a user-writable path such as `%LocalAppData%\iSmart Messenger\` so updates do not need UAC.

## 2. Why the Old Design Causes Problems

- Installer-based updates reopen the UAC/install wizard path and break silent UX.
- Replacing files while `iSmartMessenger.exe` is running creates file-lock races.
- The app currently knows how to launch an installer, but it does not own a reliable local update state machine.
- The previous helper could copy a ZIP, but it had no proper backup, rollback, mutex, or post-restart confirmation.

## 3. New Architecture

### Client app

- `DesktopUpdateAgent` remains the orchestrator.
- It receives pending update tasks through the existing heartbeat/socket flow.
- It downloads the update package into `update-data/downloads/`.
- It records local update state in `update-data/state.json`.
- It hands over installation to `ismart_messenger_updater.exe`.
- It marks the update as successful only after the app restarts on the target version.

### Updater helper

- Runs outside the main app process.
- Waits for the app to exit.
- Kills any stray old app process with the same executable name.
- Extracts the ZIP package into a temp directory.
- Backs up the current installed bundle.
- Applies the new bundle in place.
- Rolls back from backup if copy/apply fails.
- Relaunches the app automatically.

### Backend

- Releases now carry package metadata in addition to the binary artifact.
- The heartbeat response already acts as the authoritative update assignment channel.
- Each serialized release now exposes a `manifest` object ready for dashboards/clients.
- Jobs still target `all`, `branch`, or specific devices.

## 4. Package Format

- Start with `Full package update`.
- Package kind: `zip`
- Layout inside ZIP:

```text
manifest.json
app/
  iSmartMessenger.exe
  ismart_messenger_updater.exe
  flutter_windows.dll
  *.dll
  data/
  ...
```

- Do not upload only the main `.exe`.
- Upload the full Windows release bundle because Flutter Desktop depends on:
  - `flutter_windows.dll`
  - plugin DLLs
  - `data/flutter_assets`
  - ICU data
  - AOT/runtime data

## 5. Exact Flutter Build Output to Package

- Primary source folder after build:

```text
build/windows/x64/runner/Release/
```

- Package the whole contents of that directory.
- Exclude generated installer artifacts and runtime update working folders such as:
  - `update-data/`
  - `*.zip`
  - installer EXEs

## 6. Runtime Folder Structure

For current installs that already use `%LocalAppData%\iSmart Messenger\`:

```text
%LocalAppData%\iSmart Messenger\
  iSmartMessenger.exe
  ismart_messenger_updater.exe
  flutter_windows.dll
  data\
  update-data\
    downloads\
    backup\
    logs\
    runtime-helper\
    state.json
    helper-result.json
```

## 7. Manifest Shape

Example release manifest now exposed by the backend:

```json
{
  "schemaVersion": 1,
  "version": "1.5.13",
  "buildNumber": "3",
  "releaseNotes": "Scanner fixes and update engine migration.",
  "required": true,
  "minSupportedVersion": "1.5.0",
  "packageUrl": "http://intranet-server/api/updates/releases/abc123/download?token=...",
  "packageSize": 183442991,
  "sha256": "0f4f1d2f...",
  "packageType": "full",
  "packageLayout": "bundle_zip",
  "targetChannel": "stable",
  "targetPlatform": "desktop_windows",
  "targetArchitecture": "x64",
  "minWindowsBuild": "17763",
  "entryExecutable": "iSmartMessenger.exe",
  "rollout": {
    "percentage": 100
  },
  "createdAt": "2026-04-15T12:00:00.000Z",
  "publishedAt": "2026-04-15T12:05:00.000Z"
}
```

## 8. Build / Release Workflow

1. Update `desktop_app/pubspec.yaml` version.
2. Build the Windows app:

```powershell
flutter build windows
```

3. Use the generated bundle from:

```powershell
desktop_app\build\windows\x64\runner\Release\
```

4. Generate installer + update package:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\desktop_app\windows\packaging\create_release_package.ps1 `
  -BundleDir .\desktop_app\build\windows\x64\runner\Release `
  -OutputDir .\desktop_app\build\windows\release_artifacts `
  -AppName "iSmart Messenger" `
  -ExeName "iSmartMessenger.exe" `
  -Version "1.5.13" `
  -BuildNumber "3" `
  -Channel "stable" `
  -PackageType "full" `
  -PackageLayout "bundle_zip" `
  -TargetArchitecture "x64" `
  -MinSupportedVersion "1.5.0" `
  -MinWindowsBuild "17763"
```

5. Upload the generated ZIP artifact.
6. Create the release record in the dashboard/backend with the generated metadata.
7. Create an update job targeting `all`, `branch`, or specific devices.
8. Devices receive the task via heartbeat/socket.
9. Dashboard monitors statuses from task progress updates.

## 9. Migration Plan

### Phase 1

- Ship one migration release using the current update system if needed.
- That release must include:
  - the new `ismart_messenger_updater.exe`
  - the new Flutter client update state logic
  - ZIP package handling enabled server-side

### Phase 2

- After most clients are on the migration release, switch dashboard releases to ZIP full-package updates.
- Keep installer uploads only for first-time installs or emergency recovery.

### Phase 3

- Once migration is complete, treat installer-based updates as a fallback path only.

## 10. Failure Handling

- Repeated same-version install is blocked by local state + server version checks.
- Download corruption is blocked by SHA-256 verification.
- Network interruptions use retry and partial-file resume.
- File-lock issues are reduced by process handoff and stray-process termination.
- Half-applied updates are handled by copying from a backup snapshot.
- Update success is confirmed only after restart on the target version.
- If restart returns on the old version, the client reports failure/rollback instead of looping forever.

## 11. Acceptance Criteria

- No installer UI for normal updates.
- No admin prompt for normal updates when installed under `%LocalAppData%`.
- App closes and reopens automatically on the new version.
- Same update is not re-downloaded endlessly.
- Failed bundle application restores the old version and relaunches safely.
- One uploaded update can be assigned from the existing dashboard to many branches/devices.



