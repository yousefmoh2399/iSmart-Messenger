!include "LogicLib.nsh"

!macro customUnInit
  nsExec::ExecToLog 'taskkill /IM "iSmart Messenger.exe" /F'
!macroend

!macro customUnInstall
  DetailPrint "Closing iSmart Messenger..."
  nsExec::ExecToLog 'taskkill /IM "iSmart Messenger.exe" /F'

  DetailPrint "Removing startup entry..."
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "iSmart Messenger"

  DetailPrint "Removing session and cache data..."
  Delete "$APPDATA\iSmart Messenger\secure-store.json"
  Delete "$APPDATA\iSmart Messenger\auth-debug.log"
  Delete "$APPDATA\iSmart Messenger\lan-transfer-store.json"
  RMDir /r "$APPDATA\iSmart Messenger\Cache"
  RMDir /r "$APPDATA\iSmart Messenger\Code Cache"
  RMDir /r "$APPDATA\iSmart Messenger\GPUCache"
  RMDir /r "$APPDATA\iSmart Messenger\IndexedDB"
  RMDir /r "$APPDATA\iSmart Messenger\Local Storage"
  RMDir /r "$APPDATA\iSmart Messenger\Session Storage"
  RMDir /r "$APPDATA\iSmart Messenger\Service Worker"
  RMDir /r "$APPDATA\iSmart Messenger\blob_storage"
  RMDir /r "$APPDATA\iSmart Messenger\DawnGraphiteCache"
  RMDir /r "$APPDATA\iSmart Messenger\DawnWebGPUCache"
  RMDir /r "$APPDATA\iSmart Messenger\logs"
  RMDir "$APPDATA\iSmart Messenger"

  DetailPrint "Keeping local chat and document storage..."
  RMDir "$LOCALAPPDATA\iSmart Messenger"
!macroend

!macro customInstall
  ReadRegStr $R0 SHELL_CONTEXT "${UNINSTALL_REGISTRY_KEY}" QuietUninstallString
  WriteRegStr SHELL_CONTEXT "${UNINSTALL_REGISTRY_KEY}" UninstallString "$R0"

  ; Install Segoe UI Emoji font if missing on Windows (e.g. Windows 7 / POSReady / stripped Windows)
  ${IfNot} ${FileExists} "$FONTS\seguiemj.ttf"
    DetailPrint "Installing Segoe UI Emoji font..."
    SetOutPath "$FONTS"
    File /oname=seguiemj.ttf "${BUILD_RESOURCES_DIR}\seguiemj.ttf"
    WriteRegStr HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" "Segoe UI Emoji (TrueType)" "seguiemj.ttf"
    System::Call "gdi32::AddFontResource(t '$FONTS\seguiemj.ttf') i .r0"
    SendMessage 0xFFFF 0x001D 0 0
  ${EndIf}

  ; Install Noto Sans Arabic fonts for Windows 7 / POSReady to guarantee Arabic text rendering
  ${IfNot} ${FileExists} "$FONTS\NotoSansArabic-Regular.ttf"
    DetailPrint "Installing Arabic fonts..."
    SetOutPath "$FONTS"
    File /oname=NotoSansArabic-Regular.ttf "${BUILD_RESOURCES_DIR}\NotoSansArabic-Regular.ttf"
    File /oname=NotoSansArabic-Bold.ttf "${BUILD_RESOURCES_DIR}\NotoSansArabic-Bold.ttf"
    WriteRegStr HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" "Noto Sans Arabic (TrueType)" "NotoSansArabic-Regular.ttf"
    WriteRegStr HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" "Noto Sans Arabic Bold (TrueType)" "NotoSansArabic-Bold.ttf"
    System::Call "gdi32::AddFontResource(t '$FONTS\NotoSansArabic-Regular.ttf') i .r0"
    System::Call "gdi32::AddFontResource(t '$FONTS\NotoSansArabic-Bold.ttf') i .r0"
    SendMessage 0xFFFF 0x001D 0 0
  ${EndIf}
!macroend
