; Talkable installer/uninstaller hooks.
;
; The models are downloaded outside the install folder (%APPDATA%\talkable),
; so the uninstaller asks whether to remove them too. The /SD default keeps
; silent updates (which run the uninstaller silently) keeping all data.

!macro NSIS_HOOK_POSTUNINSTALL
  MessageBox MB_YESNO|MB_ICONQUESTION "Also remove the downloaded models and settings from this computer?" /SD IDNO IDNO talkable_keep_data
  RmDir /r "$APPDATA\talkable"
  RmDir /r "$APPDATA\app.talkable.desktop"
  RmDir /r "$LOCALAPPDATA\app.talkable.desktop"
  talkable_keep_data:
!macroend
