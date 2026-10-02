; Kader installer (NSIS 3). Built by packaging/windows/deploy.sh:
;   makensis -DVERSION=x.y.z -DSRCDIR=<staged folder> -DFILES=<files.nsh>
;            -DUNFILES=<unfiles.nsh> -DICON=<kader.ico> -DOUTFILE=<setup.exe> kader.nsi
;
; Per-user install into %LOCALAPPDATA%\Programs\Kader: no administrator
; rights, and the in-app updater can update it silently.
;
; Command line (besides NSIS's own /S and /D=<folder>):
;   /UPDATE    used by Kader's updater: wait for Kader to close, keep the
;              user's shortcut / "Open with" choices, start Kader afterwards
;   /PORTABLE  only replace the program files in a portable folder (no
;              shortcuts, registry entries or uninstaller)

Unicode true
ManifestDPIAware true
SetCompressor /SOLID lzma
RequestExecutionLevel user

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "Sections.nsh"

!ifndef VERSION | SRCDIR | FILES | UNFILES | ICON | OUTFILE
  !error "VERSION, SRCDIR, FILES, UNFILES, ICON and OUTFILE must be defined (see deploy.sh)"
!endif

!define APP       "Kader"
!define EXE       "kader.exe"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Kader"
!define APPPATHS  "Software\Microsoft\Windows\CurrentVersion\App Paths\kader.exe"
!define PROGID    "Kader.Media"
!define SETTINGS  "Software\Kader\Installer"

Name "${APP}"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\Programs\${APP}"
InstallDirRegKey HKCU "${SETTINGS}" "InstallDir"
BrandingText "${APP} ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName"     "${APP}"
VIAddVersionKey "ProductVersion"  "${VERSION}"
VIAddVersionKey "FileVersion"     "${VERSION}"
VIAddVersionKey "FileDescription" "${APP} installer"
VIAddVersionKey "LegalCopyright"  "MIT License"

!define MUI_ICON   "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TEXT "This will install ${APP} ${VERSION}, a fast photo and video gallery.$\r$\n$\r$\nNo administrator rights are needed.$\r$\n$\r$\nClick Next to continue."
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Start ${APP}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Var Portable
Var Update

; Image and video types Kader opens (matches FileScanner's extensions).
!macro ForEachExtension MACRO
  !insertmacro ${MACRO} ".jpg"
  !insertmacro ${MACRO} ".jpeg"
  !insertmacro ${MACRO} ".png"
  !insertmacro ${MACRO} ".webp"
  !insertmacro ${MACRO} ".gif"
  !insertmacro ${MACRO} ".bmp"
  !insertmacro ${MACRO} ".tif"
  !insertmacro ${MACRO} ".tiff"
  !insertmacro ${MACRO} ".heic"
  !insertmacro ${MACRO} ".heif"
  !insertmacro ${MACRO} ".mp4"
  !insertmacro ${MACRO} ".mkv"
  !insertmacro ${MACRO} ".mov"
  !insertmacro ${MACRO} ".avi"
  !insertmacro ${MACRO} ".webm"
  !insertmacro ${MACRO} ".dng"
  !insertmacro ${MACRO} ".nef"
  !insertmacro ${MACRO} ".cr2"
  !insertmacro ${MACRO} ".cr3"
  !insertmacro ${MACRO} ".arw"
  !insertmacro ${MACRO} ".raf"
  !insertmacro ${MACRO} ".orf"
  !insertmacro ${MACRO} ".rw2"
  !insertmacro ${MACRO} ".pef"
  !insertmacro ${MACRO} ".srw"
!macroend

!macro AddOpenWith EXT
  WriteRegStr HKCU "Software\Classes\${EXT}\OpenWithProgids" "${PROGID}" ""
  WriteRegStr HKCU "Software\Classes\Applications\${EXE}\SupportedTypes" "${EXT}" ""
!macroend

!macro RemoveOpenWith EXT
  DeleteRegValue HKCU "Software\Classes\${EXT}\OpenWithProgids" "${PROGID}"
!macroend

; Kader holds kader.exe open until it has exited; the updater starts us
; right before quitting, so wait (up to ~30 s) until the file is free.
Function WaitForKader
  IfFileExists "$INSTDIR\${EXE}" 0 done
  StrCpy $1 0
  loop:
    ClearErrors
    FileOpen $0 "$INSTDIR\${EXE}" a
    IfErrors busy
    FileClose $0
    Goto done
  busy:
    IntOp $1 $1 + 1
    IntCmp $1 120 done
    Sleep 250
    Goto loop
  done:
FunctionEnd

Section "${APP}" SecMain
  SectionIn RO
  !include "${FILES}"

  ${If} $Portable == 1
    Return
  ${EndIf}

  WriteUninstaller "$INSTDIR\uninstall.exe"
  WriteRegStr HKCU "${SETTINGS}" "InstallDir" "$INSTDIR"
  CreateShortcut "$SMPROGRAMS\${APP}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\${EXE}" 0

  ; "kader" from Win+R
  WriteRegStr HKCU "${APPPATHS}" "" "$INSTDIR\${EXE}"
  WriteRegStr HKCU "${APPPATHS}" "Path" "$INSTDIR"

  ; Apps & features
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegStr   HKCU "${UNINSTKEY}" "DisplayName"          "${APP}"
  WriteRegStr   HKCU "${UNINSTKEY}" "DisplayVersion"       "${VERSION}"
  WriteRegStr   HKCU "${UNINSTKEY}" "Publisher"            "${APP}"
  WriteRegStr   HKCU "${UNINSTKEY}" "DisplayIcon"          "$INSTDIR\${EXE}"
  WriteRegStr   HKCU "${UNINSTKEY}" "InstallLocation"      "$INSTDIR"
  WriteRegStr   HKCU "${UNINSTKEY}" "URLInfoAbout"         "https://github.com/vndreiii/kader"
  WriteRegStr   HKCU "${UNINSTKEY}" "UninstallString"      '"$INSTDIR\uninstall.exe"'
  WriteRegStr   HKCU "${UNINSTKEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINSTKEY}" "EstimatedSize"        $0
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoModify"             1
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoRepair"             1
SectionEnd

Section "Desktop shortcut" SecDesktop
  CreateShortcut "$DESKTOP\${APP}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\${EXE}" 0
SectionEnd

Section "Add $\"Open with ${APP}$\" for photos and videos" SecAssoc
  ; Offered in "Open with" without taking over the default app.
  WriteRegStr HKCU "Software\Classes\${PROGID}" "" "${APP} media"
  WriteRegStr HKCU "Software\Classes\${PROGID}\DefaultIcon" "" "$INSTDIR\${EXE},0"
  WriteRegStr HKCU "Software\Classes\${PROGID}\shell\open\command" "" '"$INSTDIR\${EXE}" "%1"'
  WriteRegStr HKCU "Software\Classes\Applications\${EXE}" "FriendlyAppName" "${APP}"
  WriteRegStr HKCU "Software\Classes\Applications\${EXE}\shell\open\command" "" '"$INSTDIR\${EXE}" "%1"'
  !insertmacro ForEachExtension AddOpenWith
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
SectionEnd

; Remember the choices so silent updates keep them.
Section "-Remember choices"
  ${If} $Portable == 1
    Return
  ${EndIf}
  ${If} ${SectionIsSelected} ${SecAssoc}
    WriteRegStr HKCU "${SETTINGS}" "OpenWith" "1"
  ${Else}
    WriteRegStr HKCU "${SETTINGS}" "OpenWith" "0"
  ${EndIf}
SectionEnd

LangString DESC_Main    ${LANG_ENGLISH} "The ${APP} program."
LangString DESC_Desktop ${LANG_ENGLISH} "Put a ${APP} shortcut on the desktop."
LangString DESC_Assoc   ${LANG_ENGLISH} "List ${APP} under $\"Open with$\" for images, RAW photos and videos. Your default apps are not changed."
!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecMain}    $(DESC_Main)
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} $(DESC_Desktop)
  !insertmacro MUI_DESCRIPTION_TEXT ${SecAssoc}   $(DESC_Assoc)
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Function .onInit
  StrCpy $Portable 0
  StrCpy $Update 0
  ${GetParameters} $R0
  ClearErrors
  ${GetOptions} $R0 "/PORTABLE" $R1
  ${IfNot} ${Errors}
    StrCpy $Portable 1
  ${EndIf}
  ClearErrors
  ${GetOptions} $R0 "/UPDATE" $R1
  ${IfNot} ${Errors}
    StrCpy $Update 1
  ${EndIf}

  ${If} $Portable == 1
    !insertmacro UnselectSection ${SecDesktop}
    !insertmacro UnselectSection ${SecAssoc}
  ${ElseIf} $Update == 1
    ; keep what the user has: a deleted desktop shortcut stays deleted
    ${IfNot} ${FileExists} "$DESKTOP\${APP}.lnk"
      !insertmacro UnselectSection ${SecDesktop}
    ${EndIf}
    ReadRegStr $R2 HKCU "${SETTINGS}" "OpenWith"
    ${If} $R2 == "0"
      !insertmacro UnselectSection ${SecAssoc}
    ${EndIf}
  ${EndIf}

  ${If} $Update == 1
    Call WaitForKader
  ${EndIf}
FunctionEnd

Function .onInstSuccess
  ${If} $Update == 1
    Exec '"$INSTDIR\${EXE}"'
  ${EndIf}
FunctionEnd

; ── Uninstaller ─────────────────────────────────────────────────────────────

Section "Uninstall"
  !include "${UNFILES}"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"

  Delete "$SMPROGRAMS\${APP}.lnk"
  Delete "$DESKTOP\${APP}.lnk"
  DeleteRegKey HKCU "${UNINSTKEY}"
  DeleteRegKey HKCU "${APPPATHS}"
  DeleteRegKey HKCU "Software\Classes\${PROGID}"
  DeleteRegKey HKCU "Software\Classes\Applications\${EXE}"
  !insertmacro ForEachExtension RemoveOpenWith
  DeleteRegKey HKCU "${SETTINGS}"
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'

  ; Library database, thumbnails, AI models and settings — never the photos.
  IfSilent keep
  MessageBox MB_YESNO|MB_ICONQUESTION|MB_DEFBUTTON2 \
    "Also delete Kader's library index, thumbnails, downloaded AI models and settings?$\r$\n$\r$\nYour photos and videos are not touched." \
    IDNO keep
  RMDir /r "$LOCALAPPDATA\${APP}"
  DeleteRegKey HKCU "Software\${APP}"
  keep:
SectionEnd
