#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/method_channel.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();
  void SetLaunchToTray(bool value);

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_method_channel_;
  bool launch_to_tray_ = false;
  bool is_exiting_ = false;
  bool tray_initialized_ = false;
  bool startup_enabled_ = false;
  std::string tray_status_ = "online";
  HMENU tray_menu_ = nullptr;
  NOTIFYICONDATAW tray_icon_data_ = {};

  void RegisterWindowChannel();
  void RequestAttention(bool play_sound);
  flutter::EncodableMap GetWindowState() const;
  void NotifyWindowStateChanged();
  void InitializeTray();
  void DisposeTray();
  void ShowTrayMenu();
  void NotifyTrayAction(const std::string& action);
  void ShowMainWindow();
  void HideMainWindow();
  void ExitToDesktop();
  void UpdateTrayChecks();
  bool IsStartupEnabled() const;
  bool SetStartupEnabled(bool enabled);
  std::wstring GetStartupCommand() const;
  void SetTrayStatus(const std::string& status);
  flutter::EncodableList ListOpenWindows() const;
  bool CaptureWindowImage(int64_t window_id, const std::wstring& image_path) const;
  bool CapturePrimaryScreenImage(const std::wstring& image_path) const;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
