!macro customUnInit
  MessageBox MB_ICONQUESTION|MB_YESNOCANCEL "Why are you uninstalling iSmart Messenger?$\r$\n$\r$\nYes: It is not working as expected.$\r$\nNo: I no longer need it.$\r$\nCancel: Keep the app installed." IDYES reason_issue IDNO reason_unused
  Abort

  reason_issue:
    StrCpy $0 "not_working_as_expected"
    Goto write_reason

  reason_unused:
    StrCpy $0 "no_longer_needed"
    Goto write_reason

  write_reason:
    FileOpen $1 "$TEMP\iSmartMessenger-uninstall-feedback.log" a
    FileWrite $1 "reason=$0$\r$\n"
    FileClose $1

  nsExec::ExecToLog 'taskkill /IM "iSmart Messenger.exe" /F'

  MessageBox MB_ICONINFORMATION|MB_OK "iSmart Messenger will be closed if it is running.$\r$\n$\r$\nThe uninstaller will remove the installed app, cached session data, logs, and startup entries.$\r$\n$\r$\nYour chat, document, scan, and incoming file storage will be kept."
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
