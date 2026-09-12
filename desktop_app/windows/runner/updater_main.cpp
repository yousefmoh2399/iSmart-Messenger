#include <windows.h>
#include <shellapi.h>
#include <tlhelp32.h>

#include <cwctype>
#include <filesystem>
#include <fstream>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

namespace {

std::optional<std::filesystem::path> g_log_path;

std::wstring Trim(const std::wstring& value) {
  const auto start = value.find_first_not_of(L" \t\r\n");
  if (start == std::wstring::npos) {
    return L"";
  }
  const auto end = value.find_last_not_of(L" \t\r\n");
  return value.substr(start, end - start + 1);
}

std::wstring QuoteIfNeeded(const std::wstring& value) {
  if (value.find_first_of(L" \t\"") == std::wstring::npos) {
    return value;
  }
  std::wstring escaped = L"\"";
  for (const wchar_t ch : value) {
    if (ch == L'"') {
      escaped += L"\\\"";
    } else {
      escaped += ch;
    }
  }
  escaped += L"\"";
  return escaped;
}

std::vector<std::wstring> SplitWhitespace(const std::wstring& value) {
  std::vector<std::wstring> result;
  std::wstring current;
  bool in_quotes = false;
  for (const wchar_t ch : value) {
    if (ch == L'"') {
      in_quotes = !in_quotes;
      continue;
    }
    if (!in_quotes && iswspace(ch)) {
      if (!current.empty()) {
        result.push_back(current);
        current.clear();
      }
      continue;
    }
    current += ch;
  }
  if (!current.empty()) {
    result.push_back(current);
  }
  return result;
}

std::wstring BuildParameterString(const std::vector<std::wstring>& args) {
  std::wstring command_line;
  for (size_t i = 0; i < args.size(); ++i) {
    if (i > 0) {
      command_line += L" ";
    }
    command_line += QuoteIfNeeded(args[i]);
  }
  return command_line;
}

std::filesystem::path DefaultLogPath() {
  wchar_t temp_path[MAX_PATH];
  const DWORD length = GetTempPathW(MAX_PATH, temp_path);
  if (length == 0 || length > MAX_PATH) {
    return std::filesystem::path(L"ismart_messenger_updater.log");
  }
  return std::filesystem::path(temp_path) / L"ismart_messenger_updater.log";
}

void InitializeLogPath(const std::wstring& log_dir) {
  if (Trim(log_dir).empty()) {
    g_log_path = DefaultLogPath();
    return;
  }
  try {
    const std::filesystem::path directory(log_dir);
    std::filesystem::create_directories(directory);
    g_log_path = directory / L"ismart_messenger_updater.log";
  } catch (...) {
    g_log_path = DefaultLogPath();
  }
}

const std::filesystem::path& LogPath() {
  if (!g_log_path.has_value()) {
    g_log_path = DefaultLogPath();
  }
  return *g_log_path;
}

void AppendLog(const std::wstring& line) {
  std::wofstream stream(LogPath(), std::ios::app);
  if (!stream.is_open()) {
    return;
  }
  SYSTEMTIME st;
  GetLocalTime(&st);
  stream << L"["
         << st.wYear << L"-"
         << st.wMonth << L"-"
         << st.wDay << L" "
         << st.wHour << L":"
         << st.wMinute << L":"
         << st.wSecond << L"] "
         << line << std::endl;
}

std::optional<std::wstring> ReadFlagValue(
    const std::vector<std::wstring>& args,
    const std::wstring& flag) {
  for (size_t i = 0; i + 1 < args.size(); ++i) {
    if (args[i] == flag) {
      return args[i + 1];
    }
  }
  return std::nullopt;
}

void WaitForParentExit(DWORD parent_pid) {
  if (parent_pid == 0) {
    Sleep(1500);
    return;
  }
  HANDLE process =
      OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, parent_pid);
  if (process == nullptr) {
    Sleep(2000);
    return;
  }
  WaitForSingleObject(process, 600000);
  CloseHandle(process);
}

bool LaunchAndWaitElevated(
    const std::wstring& executable,
    const std::wstring& parameters,
    DWORD* exit_code) {
  SHELLEXECUTEINFOW info{};
  info.cbSize = sizeof(info);
  info.fMask = SEE_MASK_NOCLOSEPROCESS;
  info.lpVerb = L"runas";
  info.lpFile = executable.c_str();
  info.lpParameters = parameters.empty() ? nullptr : parameters.c_str();
  info.nShow = SW_SHOWNORMAL;

  if (!ShellExecuteExW(&info)) {
    *exit_code = GetLastError();
    return false;
  }
  if (info.hProcess == nullptr) {
    *exit_code = ERROR_INVALID_HANDLE;
    return false;
  }
  WaitForSingleObject(info.hProcess, INFINITE);
  DWORD result = 1;
  GetExitCodeProcess(info.hProcess, &result);
  CloseHandle(info.hProcess);
  *exit_code = result;
  return true;
}

bool RelaunchApplication(const std::wstring& executable_path) {
  if (Trim(executable_path).empty()) {
    return false;
  }
  SHELLEXECUTEINFOW info{};
  info.cbSize = sizeof(info);
  info.lpFile = executable_path.c_str();
  info.nShow = SW_SHOWNORMAL;
  return ShellExecuteExW(&info) == TRUE;
}

std::wstring FileNameFromPath(const std::wstring& input) {
  const std::filesystem::path path_value(input);
  return path_value.filename().wstring();
}

void TerminateRemainingAppProcesses(const std::wstring& executable_path,
                                    DWORD self_pid,
                                    DWORD parent_pid) {
  const std::wstring target_name = FileNameFromPath(executable_path);
  if (target_name.empty()) {
    return;
  }

  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) {
    AppendLog(L"Failed to create process snapshot.");
    return;
  }

  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  if (!Process32FirstW(snapshot, &entry)) {
    CloseHandle(snapshot);
    return;
  }

  do {
    const DWORD pid = entry.th32ProcessID;
    if (pid == 0 || pid == self_pid || pid == parent_pid) {
      continue;
    }

    const std::wstring process_name = entry.szExeFile;
    if (_wcsicmp(process_name.c_str(), target_name.c_str()) != 0) {
      continue;
    }

    HANDLE process = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE, FALSE, pid);
    if (process == nullptr) {
      AppendLog(L"Could not open background app process " +
                std::to_wstring(pid));
      continue;
    }

    AppendLog(L"Terminating background app process " + std::to_wstring(pid));
    TerminateProcess(process, 0);
    WaitForSingleObject(process, 10000);
    CloseHandle(process);
  } while (Process32NextW(snapshot, &entry));

  CloseHandle(snapshot);
}

std::vector<std::vector<std::wstring>> BuildAttempts(
    const std::wstring& installer_kind,
    const std::wstring& installer_path,
    const std::wstring& raw_silent_args) {
  const std::vector<std::wstring> extra_args = SplitWhitespace(raw_silent_args);
  if (installer_kind == L"msi") {
    std::vector<std::wstring> args = {L"/i", installer_path, L"/qn", L"/norestart"};
    args.insert(args.end(), extra_args.begin(), extra_args.end());
    return {args};
  }

  std::vector<std::vector<std::wstring>> attempts;
  if (!extra_args.empty()) {
    attempts.push_back(extra_args);
  }
  attempts.push_back({L"/VERYSILENT", L"/SUPPRESSMSGBOXES", L"/NORESTART", L"/SP-"});
  attempts.push_back({L"/S"});
  attempts.push_back({L"/silent"});
  attempts.push_back({L"/quiet"});
  attempts.push_back({L"/qn"});
  attempts.push_back({L"-s"});
  attempts.push_back({L"--silent"});
  return attempts;
}

bool ExtractZipWithPowerShell(const std::wstring& zip_path,
                              const std::wstring& destination_dir) {
  std::wstring command =
      L"Expand-Archive -LiteralPath " + QuoteIfNeeded(zip_path) +
      L" -DestinationPath " + QuoteIfNeeded(destination_dir) + L" -Force";
  std::wstring parameters =
      L"-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command " +
      QuoteIfNeeded(command);
  SHELLEXECUTEINFOW info{};
  info.cbSize = sizeof(info);
  info.fMask = SEE_MASK_NOCLOSEPROCESS;
  info.lpFile = L"powershell.exe";
  info.lpParameters = parameters.c_str();
  info.nShow = SW_HIDE;
  if (!ShellExecuteExW(&info) || info.hProcess == nullptr) {
    return false;
  }
  WaitForSingleObject(info.hProcess, INFINITE);
  DWORD exit_code = 1;
  GetExitCodeProcess(info.hProcess, &exit_code);
  CloseHandle(info.hProcess);
  return exit_code == 0;
}

std::optional<std::filesystem::path> FindBundleRoot(
    const std::filesystem::path& extracted_root,
    const std::wstring& executable_name) {
  const auto packaged_app_root = extracted_root / L"app";
  if (std::filesystem::exists(packaged_app_root / executable_name)) {
    return packaged_app_root;
  }

  const auto direct = extracted_root / executable_name;
  if (std::filesystem::exists(direct)) {
    return extracted_root;
  }

  for (const auto& entry : std::filesystem::directory_iterator(extracted_root)) {
    if (!entry.is_directory()) {
      continue;
    }
    if (std::filesystem::exists(entry.path() / executable_name)) {
      return entry.path();
    }
    if (std::filesystem::exists(entry.path() / L"app" / executable_name)) {
      return entry.path() / L"app";
    }
  }

  return std::nullopt;
}

bool ShouldSkipRelativePath(const std::filesystem::path& relative_path) {
  if (relative_path.empty()) {
    return false;
  }
  const auto normalized = relative_path.lexically_normal();
  if (normalized.empty()) {
    return false;
  }
  const auto first = normalized.begin()->wstring();
  return _wcsicmp(first.c_str(), L"update-data") == 0;
}

bool RemoveDirectoryContents(const std::filesystem::path& root) {
  try {
    if (!std::filesystem::exists(root)) {
      return true;
    }
    for (const auto& entry : std::filesystem::directory_iterator(root)) {
      std::filesystem::remove_all(entry.path());
    }
    return true;
  } catch (...) {
    return false;
  }
}

bool CopyTree(const std::filesystem::path& source_root,
              const std::filesystem::path& destination_root) {
  try {
    std::filesystem::create_directories(destination_root);
    for (const auto& entry :
         std::filesystem::recursive_directory_iterator(source_root)) {
      const auto relative = std::filesystem::relative(entry.path(), source_root);
      if (ShouldSkipRelativePath(relative)) {
        continue;
      }

      const auto destination = destination_root / relative;
      if (entry.is_directory()) {
        std::filesystem::create_directories(destination);
        continue;
      }
      if (!entry.is_regular_file()) {
        continue;
      }

      std::filesystem::create_directories(destination.parent_path());
      std::filesystem::copy_file(
          entry.path(),
          destination,
          std::filesystem::copy_options::overwrite_existing);
    }
    return true;
  } catch (...) {
    return false;
  }
}

bool BackupCurrentBundle(const std::filesystem::path& app_directory,
                         const std::filesystem::path& backup_snapshot) {
  AppendLog(L"Backing up current app to " + backup_snapshot.wstring());
  if (!RemoveDirectoryContents(backup_snapshot.parent_path())) {
    AppendLog(L"Failed to clear previous backup directory.");
    return false;
  }
  return CopyTree(app_directory, backup_snapshot);
}

bool RestoreBackup(const std::filesystem::path& backup_snapshot,
                   const std::filesystem::path& app_directory) {
  AppendLog(L"Restoring backup from " + backup_snapshot.wstring());
  return CopyTree(backup_snapshot, app_directory);
}

void WriteResultFile(const std::wstring& result_file,
                     const std::wstring& outcome,
                     const std::wstring& target_version,
                     const std::wstring& message) {
  if (Trim(result_file).empty()) {
    return;
  }
  try {
    const std::filesystem::path file_path(result_file);
    std::filesystem::create_directories(file_path.parent_path());
    std::wofstream stream(file_path, std::ios::trunc);
    if (!stream.is_open()) {
      return;
    }
    stream << L"outcome=" << outcome << L"\n";
    stream << L"target_version=" << target_version << L"\n";
    stream << L"message=" << message << L"\n";
  } catch (...) {
  }
}

bool ApplyZipBundle(const std::wstring& zip_path,
                    const std::wstring& relaunch_path,
                    const std::wstring& install_dir,
                    const std::wstring& backup_dir,
                    const std::wstring& target_version,
                    const std::wstring& result_file) {
  const std::filesystem::path app_executable_path(relaunch_path);
  const std::filesystem::path app_directory =
      Trim(install_dir).empty() ? app_executable_path.parent_path()
                                : std::filesystem::path(install_dir);
  const std::filesystem::path temp_root = std::filesystem::temp_directory_path();
  const std::filesystem::path extract_dir =
      temp_root / (L"dbacd_update_extract_" + std::to_wstring(GetTickCount64()));
  const std::filesystem::path backup_root =
      Trim(backup_dir).empty()
          ? (app_directory / L"update-data" / L"backup")
          : std::filesystem::path(backup_dir);
  const std::filesystem::path backup_snapshot =
      backup_root / (L"snapshot_" + std::to_wstring(GetTickCount64()));

  try {
    std::filesystem::create_directories(extract_dir);
    std::filesystem::create_directories(backup_root);
  } catch (...) {
    AppendLog(L"Failed to create extraction or backup directory.");
    WriteResultFile(result_file, L"failed", target_version,
                    L"Failed to create extraction or backup directory.");
    return false;
  }

  if (!ExtractZipWithPowerShell(zip_path, extract_dir.wstring())) {
    AppendLog(L"Failed to extract ZIP update package.");
    WriteResultFile(result_file, L"failed", target_version,
                    L"Failed to extract ZIP update package.");
    return false;
  }

  const std::wstring executable_name = app_executable_path.filename().wstring();
  const auto bundle_root = FindBundleRoot(extract_dir, executable_name);
  if (!bundle_root.has_value()) {
    AppendLog(L"Extracted ZIP does not contain the target application executable.");
    WriteResultFile(result_file, L"failed", target_version,
                    L"Missing executable in extracted ZIP package.");
    return false;
  }

  if (!BackupCurrentBundle(app_directory, backup_snapshot)) {
    AppendLog(L"Failed to back up current application files.");
    WriteResultFile(result_file, L"failed", target_version,
                    L"Failed to back up current application files.");
    return false;
  }

  if (!CopyTree(*bundle_root, app_directory)) {
    AppendLog(L"Failed to apply ZIP update package. Starting rollback.");
    const bool restored = RestoreBackup(backup_snapshot, app_directory);
    WriteResultFile(result_file,
                    restored ? L"rolled_back" : L"failed",
                    target_version,
                    restored ? L"Update failed and backup was restored."
                             : L"Update failed and rollback did not complete.");
    return false;
  }

  AppendLog(L"ZIP update package applied successfully.");
  WriteResultFile(result_file, L"success", target_version,
                  L"ZIP update package applied successfully.");
  return true;
}

HANDLE AcquireUpdaterMutex() {
  HANDLE mutex = CreateMutexW(nullptr, TRUE, L"Local\\iSmartMessengerUpdaterMutex");
  if (mutex == nullptr) {
    return nullptr;
  }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(mutex);
    return nullptr;
  }
  return mutex;
}

bool IsElevated() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return false;
  }
  TOKEN_ELEVATION elevation{};
  DWORD size = sizeof(elevation);
  bool is_elevated = false;
  if (GetTokenInformation(token, TokenElevation, &elevation, sizeof(elevation), &size)) {
    is_elevated = elevation.TokenIsElevated != 0;
  }
  CloseHandle(token);
  return is_elevated;
}

bool IsDirectoryWritable(const std::filesystem::path& dir_path) {
  try {
    if (!std::filesystem::exists(dir_path)) {
      std::filesystem::create_directories(dir_path);
    }
    const auto temp_file = dir_path / L".write_test";
    std::wofstream test_file(temp_file);
    if (test_file.is_open()) {
      test_file.close();
      std::filesystem::remove(temp_file);
      return true;
    }
  } catch (...) {
  }
  return false;
}

bool RelaunchSelfElevated(const std::vector<std::wstring>& args) {
  wchar_t self_path[MAX_PATH];
  GetModuleFileNameW(nullptr, self_path, MAX_PATH);
  std::wstring parameters = BuildParameterString(args);

  SHELLEXECUTEINFOW info{};
  info.cbSize = sizeof(info);
  info.lpVerb = L"runas";
  info.lpFile = self_path;
  info.lpParameters = parameters.empty() ? nullptr : parameters.c_str();
  info.nShow = SW_SHOWNORMAL;

  return ShellExecuteExW(&info) == TRUE;
}

}  // namespace

int APIENTRY wWinMain(HINSTANCE instance,
                      HINSTANCE prev,
                      wchar_t* command_line,
                      int show_command) {
  int argc = 0;
  wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return EXIT_FAILURE;
  }

  std::vector<std::wstring> args;
  for (int i = 1; i < argc; ++i) {
    args.emplace_back(argv[i]);
  }
  LocalFree(argv);

  const auto parent_pid_value = ReadFlagValue(args, L"--parent-pid");
  const auto installer_path_value = ReadFlagValue(args, L"--installer-path");
  const auto installer_kind_value = ReadFlagValue(args, L"--installer-kind");
  const auto silent_args_value = ReadFlagValue(args, L"--silent-args");
  const auto relaunch_path_value = ReadFlagValue(args, L"--relaunch-path");
  const auto install_dir_value = ReadFlagValue(args, L"--install-dir");
  const auto backup_dir_value = ReadFlagValue(args, L"--backup-dir");
  const auto log_dir_value = ReadFlagValue(args, L"--log-dir");
  const auto target_version_value = ReadFlagValue(args, L"--target-version");
  const auto result_file_value = ReadFlagValue(args, L"--result-file");

  InitializeLogPath(log_dir_value ? *log_dir_value : L"");

  if (!installer_path_value || !installer_kind_value || !relaunch_path_value) {
    AppendLog(L"Missing required updater arguments.");
    return EXIT_FAILURE;
  }

  const std::wstring relaunch_path_check = Trim(*relaunch_path_value);
  const std::wstring install_dir_check = install_dir_value ? Trim(*install_dir_value) : L"";

  if (!IsElevated()) {
    std::filesystem::path app_executable_path(relaunch_path_check);
    std::filesystem::path app_directory =
        install_dir_check.empty() ? app_executable_path.parent_path()
                                  : std::filesystem::path(install_dir_check);
    if (!IsDirectoryWritable(app_directory)) {
      AppendLog(L"Install directory is not writable. Relaunching elevated.");
      if (RelaunchSelfElevated(args)) {
        return EXIT_SUCCESS;
      } else {
        AppendLog(L"Relaunch elevated failed or cancelled by user.");
      }
    }
  }

  HANDLE updater_mutex = AcquireUpdaterMutex();
  if (updater_mutex == nullptr) {
    AppendLog(L"Another updater instance is already running.");
    return EXIT_FAILURE;
  }

  DWORD parent_pid = 0;
  if (parent_pid_value && !parent_pid_value->empty()) {
    parent_pid = static_cast<DWORD>(std::wcstoul(parent_pid_value->c_str(), nullptr, 10));
  }

  const std::wstring installer_path = Trim(*installer_path_value);
  const std::wstring installer_kind = Trim(*installer_kind_value);
  const std::wstring relaunch_path = Trim(*relaunch_path_value);
  const std::wstring raw_silent_args =
      silent_args_value ? *silent_args_value : L"";
  const std::wstring install_dir = install_dir_value ? Trim(*install_dir_value) : L"";
  const std::wstring backup_dir = backup_dir_value ? Trim(*backup_dir_value) : L"";
  const std::wstring target_version =
      target_version_value ? Trim(*target_version_value) : L"";
  const std::wstring result_file =
      result_file_value ? Trim(*result_file_value) : L"";

  AppendLog(L"Updater started.");
  WaitForParentExit(parent_pid);
  TerminateRemainingAppProcesses(relaunch_path, GetCurrentProcessId(), parent_pid);
  AppendLog(L"Background app processes handled. Starting update application.");

  if (installer_kind == L"zip") {
    const bool installed = ApplyZipBundle(
        installer_path,
        relaunch_path,
        install_dir,
        backup_dir,
        target_version,
        result_file);
    Sleep(1200);
    RelaunchApplication(relaunch_path);
    ReleaseMutex(updater_mutex);
    CloseHandle(updater_mutex);
    return installed ? EXIT_SUCCESS : EXIT_FAILURE;
  }

  const auto attempts = BuildAttempts(installer_kind, installer_path, raw_silent_args);
  bool installed = false;
  DWORD last_exit_code = 0;

  for (const auto& attempt : attempts) {
    const std::wstring executable =
        installer_kind == L"msi" ? L"msiexec.exe" : installer_path;
    const std::wstring parameters = BuildParameterString(attempt);
    AppendLog(L"Launching installer: " + executable + L" " + parameters);

    DWORD exit_code = 0;
    const bool launched =
        LaunchAndWaitElevated(executable, parameters, &exit_code);
    last_exit_code = exit_code;
    if (!launched) {
      AppendLog(L"Installer launch failed. Win32 code=" + std::to_wstring(exit_code));
      continue;
    }

    AppendLog(L"Installer finished. ExitCode=" + std::to_wstring(exit_code));
    if (exit_code == 0) {
      installed = true;
      break;
    }
  }

  WriteResultFile(result_file,
                  installed ? L"success" : L"failed",
                  target_version,
                  installed ? L"Installer completed successfully."
                            : L"Installer did not complete successfully.");

  Sleep(2000);
  if (RelaunchApplication(relaunch_path)) {
    AppendLog(installed ? L"App relaunched after successful update."
                        : L"App relaunched after failed update.");
  } else {
    AppendLog(L"Failed to relaunch app.");
  }

  ReleaseMutex(updater_mutex);
  CloseHandle(updater_mutex);
  return installed ? EXIT_SUCCESS : static_cast<int>(last_exit_code == 0 ? 1 : last_exit_code);
}


