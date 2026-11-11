!include "LogicLib.nsh"

!macro customInit
  ; Ensure all instances of old or new process (and clipboard helper) are terminated
  nsExec::Exec 'taskkill /IM "iSmart Messenger.exe" /F'
  nsExec::Exec 'taskkill /IM "ismart-messenger.exe" /F'
  nsExec::Exec 'taskkill /IM "clip_helper.exe" /F'
  Sleep 800
!macroend

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
!macroend

!macro customInstall
  ReadRegStr $R0 SHELL_CONTEXT "${UNINSTALL_REGISTRY_KEY}" QuietUninstallString
  WriteRegStr SHELL_CONTEXT "${UNINSTALL_REGISTRY_KEY}" UninstallString "$R0"

  ; Clean up legacy shortcuts and previous per-machine (Program Files) installation
  DetailPrint "Cleaning up legacy shortcuts and older installations..."

  ; Remove old shortcuts from Public/Common Desktop and Common Start Menu
  SetShellVarContext all
  Delete "$DESKTOP\iSmart Messenger.lnk"
  Delete "$DESKTOP\ismart-messenger.lnk"
  Delete "$SMPROGRAMS\iSmart Messenger.lnk"
  Delete "$SMPROGRAMS\iSmart Messenger\iSmart Messenger.lnk"
  RMDir "$SMPROGRAMS\iSmart Messenger"
  SetShellVarContext current

  ; Clean legacy startup entry in HKLM
  DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "iSmart Messenger"

  ; Directly delete legacy uninstaller in Program Files (x86) if present, WITHOUT executing it
  ${If} ${FileExists} "$PROGRAMFILES32\iSmart Messenger\Uninstall iSmart Messenger.exe"
    Delete "$PROGRAMFILES32\iSmart Messenger\Uninstall iSmart Messenger.exe"
    RMDir /r "$PROGRAMFILES32\iSmart Messenger"
  ${EndIf}

  ; Clean legacy HKLM uninstall registry keys
  SetRegView 64
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\com.ismart.messenger.webwrapper"
  SetRegView 32
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\com.ismart.messenger.webwrapper"
  SetRegView lastused

  ; Install system fonts only if running as Admin (standard users skip safely as fonts are bundled in web assets)
  ClearErrors
  UserInfo::GetAccountType
  Pop $0
  ${If} $0 == "Admin"
    ; Install Segoe UI Emoji font if missing on Windows (e.g. Windows 7 / POSReady / stripped Windows)
    ; Guard with IfFileExists so NSIS build does not fail if font is absent from build resources.
    ${IfNot} ${FileExists} "$FONTS\seguiemj.ttf"
      IfFileExists "${BUILD_RESOURCES_DIR}\seguiemj.ttf" 0 SkipSegoeEmoji
      DetailPrint "Installing Segoe UI Emoji font..."
      SetOutPath "$FONTS"
      File /oname=seguiemj.ttf "${BUILD_RESOURCES_DIR}\seguiemj.ttf"
      WriteRegStr HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" "Segoe UI Emoji (TrueType)" "seguiemj.ttf"
      System::Call "gdi32::AddFontResource(t '$FONTS\seguiemj.ttf') i .r0"
      SendMessage 0xFFFF 0x001D 0 0
      SkipSegoeEmoji:
    ${EndIf}

    ; Install Noto Sans Arabic fonts for Windows 7 / POSReady to guarantee Arabic text rendering
    ; Guard with IfFileExists so NSIS build does not fail if font is absent from build resources.
    ${IfNot} ${FileExists} "$FONTS\NotoSansArabic-Regular.ttf"
      IfFileExists "${BUILD_RESOURCES_DIR}\NotoSansArabic-Regular.ttf" 0 SkipNotoArabic
      DetailPrint "Installing Arabic fonts..."
      SetOutPath "$FONTS"
      File /oname=NotoSansArabic-Regular.ttf "${BUILD_RESOURCES_DIR}\NotoSansArabic-Regular.ttf"
      File /oname=NotoSansArabic-Bold.ttf "${BUILD_RESOURCES_DIR}\NotoSansArabic-Bold.ttf"
      WriteRegStr HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" "Noto Sans Arabic (TrueType)" "NotoSansArabic-Regular.ttf"
      WriteRegStr HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" "Noto Sans Arabic Bold (TrueType)" "NotoSansArabic-Bold.ttf"
      System::Call "gdi32::AddFontResource(t '$FONTS\NotoSansArabic-Regular.ttf') i .r0"
      System::Call "gdi32::AddFontResource(t '$FONTS\NotoSansArabic-Bold.ttf') i .r0"
      SendMessage 0xFFFF 0x001D 0 0
      SkipNotoArabic:
    ${EndIf}
  ${EndIf}
!macroend
