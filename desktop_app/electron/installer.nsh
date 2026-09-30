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
!macroend
