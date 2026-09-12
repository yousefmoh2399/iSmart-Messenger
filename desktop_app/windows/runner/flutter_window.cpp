#include "flutter_window.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <optional>
#include <string>
#include <vector>

#include <dwmapi.h>
#include <shellapi.h>
#include <strsafe.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

#ifndef PW_RENDERFULLCONTENT
#define PW_RENDERFULLCONTENT 0x00000002
#endif
#ifndef DWMWA_CLOAKED
#define DWMWA_CLOAKED 14
#endif

namespace {
constexpr UINT kTrayIconMessage = WM_APP + 101;
constexpr UINT kTrayIconId = 1;

constexpr UINT kMenuStartup = 1001;
constexpr UINT kMenuSettings = 1002;
constexpr UINT kMenuProfile = 1003;
constexpr UINT kMenuOpen = 1004;
constexpr UINT kMenuSignOut = 1005;
constexpr UINT kMenuStatusOnline = 1010;
constexpr UINT kMenuStatusIdle = 1011;
constexpr UINT kMenuStatusMeeting = 1012;
constexpr UINT kMenuStatusLunch = 1013;
constexpr UINT kMenuStatusOffline = 1014;
constexpr UINT kMenuExit = 1099;

constexpr wchar_t kStartupRegistryPath[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kStartupRegistryValue[] = L"iSmartMessengerDesktop";

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int required = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.c_str(),
      static_cast<int>(value.size()), nullptr, 0);
  if (required <= 0) {
    return std::wstring();
  }
  std::wstring output(required, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.c_str(),
                      static_cast<int>(value.size()), output.data(), required);
  return output;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  const int required = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.c_str(),
      static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (required <= 0) {
    return std::string();
  }
  std::string output(required, '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.c_str(),
                      static_cast<int>(value.size()), output.data(), required,
                      nullptr, nullptr);
  return output;
}

std::wstring GetWindowTitle(HWND hwnd) {
  const int title_length = GetWindowTextLengthW(hwnd);
  if (title_length <= 0) {
    return std::wstring();
  }
  std::wstring title(static_cast<size_t>(title_length) + 1, L'\0');
  const int copied = GetWindowTextW(hwnd, title.data(), title_length + 1);
  if (copied <= 0) {
    return std::wstring();
  }
  title.resize(static_cast<size_t>(copied));
  return title;
}

std::wstring GetWindowClassName(HWND hwnd) {
  std::array<wchar_t, 256> class_name = {};
  const int copied = GetClassNameW(hwnd, class_name.data(),
                                   static_cast<int>(class_name.size()));
  if (copied <= 0) {
    return std::wstring();
  }
  return std::wstring(class_name.data(), static_cast<size_t>(copied));
}

bool IsCapturableWindow(HWND hwnd, HWND app_handle) {
  if (hwnd == nullptr || hwnd == app_handle) {
    return false;
  }
  if (!IsWindow(hwnd) || !IsWindowVisible(hwnd)) {
    return false;
  }
  if (GetAncestor(hwnd, GA_ROOT) != hwnd) {
    return false;
  }

  if (hwnd == GetShellWindow() || hwnd == GetDesktopWindow()) {
    return false;
  }

  const std::wstring class_name = GetWindowClassName(hwnd);
  if (class_name == L"Progman" || class_name == L"WorkerW" ||
      class_name == L"Shell_TrayWnd" ||
      class_name == L"Shell_SecondaryTrayWnd") {
    return false;
  }

  const LONG ex_style = GetWindowLongW(hwnd, GWL_EXSTYLE);
  if ((ex_style & WS_EX_TOOLWINDOW) != 0) {
    return false;
  }

  if (GetWindow(hwnd, GW_OWNER) != nullptr && (ex_style & WS_EX_APPWINDOW) == 0) {
    return false;
  }

  DWORD cloaked = 0;
  if (SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked,
                                      sizeof(cloaked))) &&
      cloaked != 0) {
    return false;
  }

  if (GetWindowTitle(hwnd).empty()) {
    return false;
  }

  RECT rect = {};
  if (!GetWindowRect(hwnd, &rect)) {
    return false;
  }
  const int width = rect.right - rect.left;
  const int height = rect.bottom - rect.top;
  if (width < 80 || height < 60) {
    return false;
  }

  return true;
}

std::string GetProcessNameFromWindow(HWND hwnd) {
  DWORD process_id = 0;
  GetWindowThreadProcessId(hwnd, &process_id);
  if (process_id == 0) {
    return std::string();
  }

  HANDLE process =
      OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (process == nullptr) {
    return std::string();
  }

  std::array<wchar_t, MAX_PATH> path_buffer = {};
  DWORD path_length = static_cast<DWORD>(path_buffer.size());
  std::string process_name;
  if (QueryFullProcessImageNameW(process, 0, path_buffer.data(), &path_length) !=
      FALSE) {
    std::wstring path(path_buffer.data(), path_length);
    const std::size_t slash_pos = path.find_last_of(L"\\/");
    const std::wstring file_name =
        slash_pos == std::wstring::npos ? path : path.substr(slash_pos + 1);
    process_name = WideToUtf8(file_name);
  }
  CloseHandle(process);
  return process_name;
}

std::optional<int64_t> ReadInt64(const flutter::EncodableValue& value) {
  if (const auto* value64 = std::get_if<int64_t>(&value)) {
    return *value64;
  }
  if (const auto* value32 = std::get_if<int32_t>(&value)) {
    return static_cast<int64_t>(*value32);
  }
  return std::nullopt;
}

bool SaveBitmapToBmpFile(HBITMAP bitmap, HDC dc, int width, int height,
                         const std::wstring& output_path) {
  if (bitmap == nullptr || dc == nullptr || width <= 0 || height <= 0) {
    return false;
  }

  BITMAPINFOHEADER info_header = {};
  info_header.biSize = sizeof(BITMAPINFOHEADER);
  info_header.biWidth = width;
  info_header.biHeight = -height;
  info_header.biPlanes = 1;
  info_header.biBitCount = 32;
  info_header.biCompression = BI_RGB;

  std::vector<uint8_t> pixels(static_cast<size_t>(width) *
                              static_cast<size_t>(height) * 4u);
  if (GetDIBits(dc, bitmap, 0, static_cast<UINT>(height), pixels.data(),
                reinterpret_cast<BITMAPINFO*>(&info_header),
                DIB_RGB_COLORS) == 0) {
    return false;
  }

  // Ensure fully-opaque alpha. Some viewers/renderers treat 0 alpha as black.
  for (size_t i = 3; i < pixels.size(); i += 4) {
    pixels[i] = 0xFF;
  }

  BITMAPFILEHEADER file_header = {};
  file_header.bfType = 0x4D42;
  file_header.bfOffBits =
      sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
  file_header.bfSize =
      file_header.bfOffBits + static_cast<DWORD>(pixels.size());

  FILE* file = nullptr;
  if (_wfopen_s(&file, output_path.c_str(), L"wb") != 0 || file == nullptr) {
    return false;
  }

  const bool success =
      fwrite(&file_header, sizeof(file_header), 1, file) == 1 &&
      fwrite(&info_header, sizeof(info_header), 1, file) == 1 &&
      fwrite(pixels.data(), sizeof(uint8_t), pixels.size(), file) ==
          pixels.size();
  fclose(file);
  return success;
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::SetLaunchToTray(bool value) { launch_to_tray_ = value; }

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  RegisterWindowChannel();
  startup_enabled_ = IsStartupEnabled();
  InitializeTray();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (launch_to_tray_) {
      this->HideMainWindow();
      return;
    }
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::RegisterWindowChannel() {
  window_method_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "dbacd_hub/window",
          &flutter::StandardMethodCodec::GetInstance());

  window_method_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "requestAttention") {
          bool play_sound = true;
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments != nullptr) {
            const auto it =
                arguments->find(flutter::EncodableValue("playSound"));
            if (it != arguments->end()) {
              if (const auto* value = std::get_if<bool>(&it->second)) {
                play_sound = *value;
              }
            }
          }

          RequestAttention(play_sound);
          result->Success();
          return;
        }

        if (call.method_name() == "getWindowState") {
          result->Success(flutter::EncodableValue(GetWindowState()));
          return;
        }

        if (call.method_name() == "showMainWindow") {
          ShowMainWindow();
          result->Success();
          return;
        }

        if (call.method_name() == "hideToTray") {
          HideMainWindow();
          result->Success();
          return;
        }

        if (call.method_name() == "setTrayStatus") {
          std::string status = "online";
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments != nullptr) {
            const auto status_it =
                arguments->find(flutter::EncodableValue("status"));
            if (status_it != arguments->end()) {
              if (const auto* status_value =
                      std::get_if<std::string>(&status_it->second)) {
                status = *status_value;
              }
            }
          }
          SetTrayStatus(status);
          result->Success();
          return;
        }

        if (call.method_name() == "isStartupEnabled") {
          startup_enabled_ = IsStartupEnabled();
          UpdateTrayChecks();
          result->Success(flutter::EncodableValue(startup_enabled_));
          return;
        }

        if (call.method_name() == "setStartupEnabled") {
          bool enabled = false;
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments != nullptr) {
            const auto enabled_it =
                arguments->find(flutter::EncodableValue("enabled"));
            if (enabled_it != arguments->end()) {
              if (const auto* enabled_value =
                      std::get_if<bool>(&enabled_it->second)) {
                enabled = *enabled_value;
              }
            }
          }
          const bool success = SetStartupEnabled(enabled);
          startup_enabled_ = success ? enabled : IsStartupEnabled();
          UpdateTrayChecks();
          result->Success(flutter::EncodableValue(success));
          return;
        }

        if (call.method_name() == "listOpenWindows") {
          result->Success(flutter::EncodableValue(ListOpenWindows()));
          return;
        }

        if (call.method_name() == "captureWindowImage") {
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments == nullptr) {
            result->Success(flutter::EncodableValue(false));
            return;
          }

          const auto id_it =
              arguments->find(flutter::EncodableValue("windowId"));
          const auto path_it =
              arguments->find(flutter::EncodableValue("imagePath"));
          if (id_it == arguments->end() || path_it == arguments->end()) {
            result->Success(flutter::EncodableValue(false));
            return;
          }

          const auto window_id = ReadInt64(id_it->second);
          const auto* image_path = std::get_if<std::string>(&path_it->second);
          if (!window_id.has_value() || image_path == nullptr ||
              image_path->empty()) {
            result->Success(flutter::EncodableValue(false));
            return;
          }

          const bool captured =
              CaptureWindowImage(*window_id, Utf8ToWide(*image_path));
          result->Success(flutter::EncodableValue(captured));
          return;
        }

        if (call.method_name() == "capturePrimaryScreenImage") {
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments == nullptr) {
            result->Success(flutter::EncodableValue(false));
            return;
          }

          const auto path_it =
              arguments->find(flutter::EncodableValue("imagePath"));
          if (path_it == arguments->end()) {
            result->Success(flutter::EncodableValue(false));
            return;
          }

          const auto* image_path = std::get_if<std::string>(&path_it->second);
          if (image_path == nullptr || image_path->empty()) {
            result->Success(flutter::EncodableValue(false));
            return;
          }

          const bool captured = CapturePrimaryScreenImage(Utf8ToWide(*image_path));
          result->Success(flutter::EncodableValue(captured));
          return;
        }

        result->NotImplemented();
      });
}

void FlutterWindow::RequestAttention(bool play_sound) {
  FLASHWINFO flash_info = {};
  flash_info.cbSize = sizeof(FLASHWINFO);
  flash_info.hwnd = GetHandle();
  flash_info.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG;
  flash_info.uCount = 5;
  flash_info.dwTimeout = 0;
  FlashWindowEx(&flash_info);

  if (play_sound) {
    MessageBeep(MB_ICONEXCLAMATION);
  }
}

flutter::EncodableMap FlutterWindow::GetWindowState() const {
  const HWND handle = GetHandle();
  const bool is_visible = IsWindowVisible(handle);
  const bool is_minimized = IsIconic(handle);
  const bool is_foreground = GetForegroundWindow() == handle;

  flutter::EncodableMap state;
  state[flutter::EncodableValue("isVisible")] = flutter::EncodableValue(is_visible);
  state[flutter::EncodableValue("isMinimized")] = flutter::EncodableValue(is_minimized);
  state[flutter::EncodableValue("isForeground")] = flutter::EncodableValue(is_foreground);
  return state;
}

void FlutterWindow::NotifyWindowStateChanged() {
  if (!window_method_channel_) {
    return;
  }
  window_method_channel_->InvokeMethod(
      "windowStateChanged",
      std::make_unique<flutter::EncodableValue>(GetWindowState()));
}

void FlutterWindow::OnDestroy() {
  DisposeTray();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_CLOSE && !is_exiting_) {
    HideMainWindow();
    return 0;
  }

  if (message == kTrayIconMessage) {
    if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
      ShowTrayMenu();
      return 0;
    }
    if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
      ShowMainWindow();
      return 0;
    }
  }

  if (message == WM_COMMAND) {
    const auto command = LOWORD(wparam);
    switch (command) {
      case kMenuStartup: {
        const bool next_enabled = !startup_enabled_;
        const bool success = SetStartupEnabled(next_enabled);
        startup_enabled_ = success ? next_enabled : IsStartupEnabled();
        UpdateTrayChecks();
        NotifyTrayAction(startup_enabled_ ? "startup_enabled:true"
                                          : "startup_enabled:false");
        return 0;
      }
      case kMenuSettings:
        NotifyTrayAction("settings");
        return 0;
      case kMenuProfile:
        NotifyTrayAction("profile");
        return 0;
      case kMenuOpen:
        ShowMainWindow();
        NotifyTrayAction("open");
        return 0;
      case kMenuSignOut:
        NotifyTrayAction("signout");
        return 0;
      case kMenuStatusOnline:
        SetTrayStatus("online");
        NotifyTrayAction("status:online");
        return 0;
      case kMenuStatusIdle:
        SetTrayStatus("idle");
        NotifyTrayAction("status:idle");
        return 0;
      case kMenuStatusMeeting:
        SetTrayStatus("meeting");
        NotifyTrayAction("status:meeting");
        return 0;
      case kMenuStatusLunch:
        SetTrayStatus("lunch");
        NotifyTrayAction("status:lunch");
        return 0;
      case kMenuStatusOffline:
        SetTrayStatus("offline");
        NotifyTrayAction("status:offline");
        return 0;
      case kMenuExit:
        ExitToDesktop();
        return 0;
    }
  }

  if (message == WM_SIZE || message == WM_SHOWWINDOW || message == WM_ACTIVATE) {
    NotifyWindowStateChanged();
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::InitializeTray() {
  if (tray_initialized_) {
    return;
  }

  ZeroMemory(&tray_icon_data_, sizeof(tray_icon_data_));
  tray_icon_data_.cbSize = sizeof(NOTIFYICONDATAW);
  tray_icon_data_.hWnd = GetHandle();
  tray_icon_data_.uID = kTrayIconId;
  tray_icon_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_data_.uCallbackMessage = kTrayIconMessage;
  tray_icon_data_.hIcon =
      reinterpret_cast<HICON>(LoadImage(GetModuleHandle(nullptr),
                                        MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON,
                                        0, 0, LR_DEFAULTSIZE));
  if (tray_icon_data_.hIcon == nullptr) {
    tray_icon_data_.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
  }
  StringCchCopyW(tray_icon_data_.szTip, ARRAYSIZE(tray_icon_data_.szTip),
                 L"iSmart Messenger");
  Shell_NotifyIconW(NIM_ADD, &tray_icon_data_);
  tray_initialized_ = true;

  tray_menu_ = CreatePopupMenu();
  HMENU status_menu = CreatePopupMenu();
  AppendMenuW(tray_menu_, MF_STRING, kMenuStartup, L"Load at Windows startup");
  AppendMenuW(tray_menu_, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(tray_menu_, MF_STRING, kMenuSettings, L"Settings");
  AppendMenuW(tray_menu_, MF_STRING, kMenuProfile, L"My profile");
  AppendMenuW(tray_menu_, MF_STRING, kMenuOpen, L"Open");
  AppendMenuW(tray_menu_, MF_STRING, kMenuSignOut, L"Sign out");

  AppendMenuW(status_menu, MF_STRING, kMenuStatusOnline, L"Online");
  AppendMenuW(status_menu, MF_STRING, kMenuStatusIdle, L"Idle");
  AppendMenuW(status_menu, MF_STRING, kMenuStatusMeeting, L"Meeting");
  AppendMenuW(status_menu, MF_STRING, kMenuStatusLunch, L"Lunch");
  AppendMenuW(status_menu, MF_STRING, kMenuStatusOffline, L"Offline");
  AppendMenuW(tray_menu_, MF_POPUP, reinterpret_cast<UINT_PTR>(status_menu),
              L"My status");

  AppendMenuW(tray_menu_, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(tray_menu_, MF_STRING, kMenuExit, L"Exit");
  UpdateTrayChecks();
}

void FlutterWindow::DisposeTray() {
  if (tray_initialized_) {
    Shell_NotifyIconW(NIM_DELETE, &tray_icon_data_);
    tray_initialized_ = false;
  }
  if (tray_icon_data_.hIcon != nullptr) {
    DestroyIcon(tray_icon_data_.hIcon);
    tray_icon_data_.hIcon = nullptr;
  }
  if (tray_menu_ != nullptr) {
    DestroyMenu(tray_menu_);
    tray_menu_ = nullptr;
  }
}

void FlutterWindow::ShowTrayMenu() {
  if (!tray_menu_) {
    return;
  }
  UpdateTrayChecks();
  POINT point;
  GetCursorPos(&point);
  SetForegroundWindow(GetHandle());
  TrackPopupMenu(tray_menu_, TPM_BOTTOMALIGN | TPM_LEFTALIGN | TPM_RIGHTBUTTON,
                 point.x, point.y, 0, GetHandle(), nullptr);
  PostMessage(GetHandle(), WM_NULL, 0, 0);
}

void FlutterWindow::NotifyTrayAction(const std::string& action) {
  if (!window_method_channel_) {
    return;
  }
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("action")] = flutter::EncodableValue(action);
  payload[flutter::EncodableValue("status")] =
      flutter::EncodableValue(tray_status_);
  payload[flutter::EncodableValue("startupEnabled")] =
      flutter::EncodableValue(startup_enabled_);
  window_method_channel_->InvokeMethod(
      "trayAction", std::make_unique<flutter::EncodableValue>(payload));
}

void FlutterWindow::ShowMainWindow() {
  const auto handle = GetHandle();
  ShowWindow(handle, SW_RESTORE);
  ShowWindow(handle, SW_SHOWNORMAL);
  SetForegroundWindow(handle);
  NotifyWindowStateChanged();
}

void FlutterWindow::HideMainWindow() {
  ShowWindow(GetHandle(), SW_HIDE);
  NotifyWindowStateChanged();
}

void FlutterWindow::ExitToDesktop() {
  is_exiting_ = true;
  DisposeTray();
  Destroy();
}

void FlutterWindow::UpdateTrayChecks() {
  if (!tray_menu_) {
    return;
  }

  startup_enabled_ = IsStartupEnabled();
  CheckMenuItem(tray_menu_, kMenuStartup,
                MF_BYCOMMAND | (startup_enabled_ ? MF_CHECKED : MF_UNCHECKED));

  HMENU status_menu = GetSubMenu(tray_menu_, 6);
  if (!status_menu) {
    return;
  }

  UINT selected_id = kMenuStatusOnline;
  if (tray_status_ == "idle") {
    selected_id = kMenuStatusIdle;
  } else if (tray_status_ == "meeting") {
    selected_id = kMenuStatusMeeting;
  } else if (tray_status_ == "lunch") {
    selected_id = kMenuStatusLunch;
  } else if (tray_status_ == "offline") {
    selected_id = kMenuStatusOffline;
  }
  CheckMenuRadioItem(status_menu, kMenuStatusOnline, kMenuStatusOffline,
                     selected_id, MF_BYCOMMAND);
}

flutter::EncodableList FlutterWindow::ListOpenWindows() const {
  flutter::EncodableList windows;
  const HWND app_handle = GetHandle();
  struct EnumContext {
    flutter::EncodableList* windows = nullptr;
    HWND app_handle = nullptr;
  } context{&windows, app_handle};

  EnumWindows(
      [](HWND hwnd, LPARAM lparam) -> BOOL {
        auto* payload = reinterpret_cast<EnumContext*>(lparam);
        if (payload == nullptr) {
          return FALSE;
        }
        if (!IsCapturableWindow(hwnd, payload->app_handle)) {
          return TRUE;
        }

        const std::wstring window_title = GetWindowTitle(hwnd);
        const std::string app_name = GetProcessNameFromWindow(hwnd);
        const std::string title_utf8 = WideToUtf8(window_title);
        const std::string display_title =
            !title_utf8.empty() ? title_utf8 : app_name;
        if (display_title.empty()) {
          return TRUE;
        }

        flutter::EncodableMap window_entry;
        window_entry[flutter::EncodableValue("windowId")] =
            flutter::EncodableValue(static_cast<int64_t>(
                reinterpret_cast<uintptr_t>(hwnd)));
        window_entry[flutter::EncodableValue("title")] =
            flutter::EncodableValue(display_title);
        window_entry[flutter::EncodableValue("appName")] =
            flutter::EncodableValue(app_name);
        payload->windows->push_back(flutter::EncodableValue(window_entry));
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&context));
  return windows;
}

bool FlutterWindow::CaptureWindowImage(int64_t window_id,
                                       const std::wstring& image_path) const {
  if (window_id <= 0 || image_path.empty()) {
    return false;
  }

  const HWND hwnd =
      reinterpret_cast<HWND>(static_cast<uintptr_t>(window_id));
  if (!IsWindow(hwnd)) {
    return false;
  }

  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  }
  SetForegroundWindow(hwnd);
  BringWindowToTop(hwnd);
  Sleep(180);

  RECT rect = {};
  if (!GetWindowRect(hwnd, &rect)) {
    return false;
  }
  const int width = rect.right - rect.left;
  const int height = rect.bottom - rect.top;
  if (width <= 0 || height <= 0) {
    return false;
  }

  HDC screen_dc = GetDC(nullptr);
  if (screen_dc == nullptr) {
    return false;
  }
  HDC mem_dc = CreateCompatibleDC(screen_dc);
  if (mem_dc == nullptr) {
    ReleaseDC(nullptr, screen_dc);
    return false;
  }

  HBITMAP bitmap = CreateCompatibleBitmap(screen_dc, width, height);
  if (bitmap == nullptr) {
    DeleteDC(mem_dc);
    ReleaseDC(nullptr, screen_dc);
    return false;
  }

  HGDIOBJ old_bitmap = SelectObject(mem_dc, bitmap);
  bool copied =
      BitBlt(mem_dc, 0, 0, width, height, screen_dc, rect.left, rect.top,
             SRCCOPY | CAPTUREBLT) == TRUE;
  if (!copied) {
    copied =
        PrintWindow(hwnd, mem_dc, PW_RENDERFULLCONTENT) == TRUE;
  }
  if (!copied) {
    copied = BitBlt(mem_dc, 0, 0, width, height, screen_dc, rect.left,
                    rect.top, SRCCOPY) == TRUE;
  }

  bool saved = false;
  if (copied) {
    saved = SaveBitmapToBmpFile(bitmap, mem_dc, width, height, image_path);
  }

  SelectObject(mem_dc, old_bitmap);
  DeleteObject(bitmap);
  DeleteDC(mem_dc);
  ReleaseDC(nullptr, screen_dc);
  return saved;
}

bool FlutterWindow::CapturePrimaryScreenImage(
    const std::wstring& image_path) const {
  if (image_path.empty()) {
    return false;
  }

  const int left = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int top = GetSystemMetrics(SM_YVIRTUALSCREEN);
  const int width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const int height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  if (width <= 0 || height <= 0) {
    return false;
  }

  HDC screen_dc = GetDC(nullptr);
  if (screen_dc == nullptr) {
    return false;
  }
  HDC mem_dc = CreateCompatibleDC(screen_dc);
  if (mem_dc == nullptr) {
    ReleaseDC(nullptr, screen_dc);
    return false;
  }

  HBITMAP bitmap = CreateCompatibleBitmap(screen_dc, width, height);
  if (bitmap == nullptr) {
    DeleteDC(mem_dc);
    ReleaseDC(nullptr, screen_dc);
    return false;
  }

  HGDIOBJ old_bitmap = SelectObject(mem_dc, bitmap);
  const bool copied =
      BitBlt(mem_dc, 0, 0, width, height, screen_dc, left, top,
             SRCCOPY | CAPTUREBLT) == TRUE;

  bool saved = false;
  if (copied) {
    saved = SaveBitmapToBmpFile(bitmap, mem_dc, width, height, image_path);
  }

  SelectObject(mem_dc, old_bitmap);
  DeleteObject(bitmap);
  DeleteDC(mem_dc);
  ReleaseDC(nullptr, screen_dc);
  return saved;
}

bool FlutterWindow::IsStartupEnabled() const {
  HKEY key = nullptr;
  const auto open_result = RegOpenKeyExW(HKEY_CURRENT_USER, kStartupRegistryPath,
                                         0, KEY_QUERY_VALUE, &key);
  if (open_result != ERROR_SUCCESS || key == nullptr) {
    return false;
  }

  DWORD type = 0;
  DWORD data_size = 0;
  const auto query_result =
      RegQueryValueExW(key, kStartupRegistryValue, nullptr, &type, nullptr,
                       &data_size);
  RegCloseKey(key);
  return query_result == ERROR_SUCCESS && type == REG_SZ && data_size > 2;
}

bool FlutterWindow::SetStartupEnabled(bool enabled) {
  HKEY key = nullptr;
  const auto create_result =
      RegCreateKeyExW(HKEY_CURRENT_USER, kStartupRegistryPath, 0, nullptr, 0,
                      KEY_SET_VALUE | KEY_QUERY_VALUE, nullptr, &key, nullptr);
  if (create_result != ERROR_SUCCESS || key == nullptr) {
    return false;
  }

  LONG result = ERROR_SUCCESS;
  if (enabled) {
    const auto command = GetStartupCommand();
    result = RegSetValueExW(
        key, kStartupRegistryValue, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(command.c_str()),
        static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    result = RegDeleteValueW(key, kStartupRegistryValue);
    if (result == ERROR_FILE_NOT_FOUND) {
      result = ERROR_SUCCESS;
    }
  }

  RegCloseKey(key);
  return result == ERROR_SUCCESS;
}

std::wstring FlutterWindow::GetStartupCommand() const {
  std::array<wchar_t, MAX_PATH> path = {};
  const DWORD copied = GetModuleFileNameW(nullptr, path.data(),
                                          static_cast<DWORD>(path.size()));
  if (copied == 0) {
    return L"";
  }
  std::wstring executable(path.data(), copied);
  return L"\"" + executable + L"\" --launch-to-tray";
}

void FlutterWindow::SetTrayStatus(const std::string& status) {
  const std::string normalized = [&]() {
    std::string lowered = status;
    std::transform(
        lowered.begin(), lowered.end(), lowered.begin(),
        [](unsigned char value) { return static_cast<char>(std::tolower(value)); });
    if (lowered == "idle" || lowered == "meeting" || lowered == "lunch" ||
        lowered == "offline" || lowered == "online") {
      return lowered;
    }
    return std::string("online");
  }();

  tray_status_ = normalized;
  UpdateTrayChecks();

  if (!tray_initialized_) {
    return;
  }

  std::wstring tip = L"iSmart Messenger - ";
  tip += Utf8ToWide(normalized);
  StringCchCopyW(tray_icon_data_.szTip, ARRAYSIZE(tray_icon_data_.szTip),
                 tip.c_str());
  tray_icon_data_.uFlags = NIF_TIP;
  Shell_NotifyIconW(NIM_MODIFY, &tray_icon_data_);
}

