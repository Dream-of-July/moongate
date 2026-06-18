; 月之门 Windows 安装器（NSIS，在 macOS 上用 brew 的 makensis 交叉构建）
; 设计目标：双击即装、无需管理员权限（装到当前用户目录）、开始菜单/桌面快捷方式、可卸载。
; 构建参数（由 build-windows.sh 传入）：
;   /DPUBLISH_DIR=<dotnet publish 输出目录>  /DOUTFILE=<安装器输出路径>  /DAPPVERSION=<版本>

Unicode true
!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"

!ifndef APPVERSION
  !define APPVERSION "0.7.2"
!endif
!ifndef ICON_PATH
  !define ICON_PATH "windows/assets/app-nsis.ico"
!endif

!define APPNAME "月之门"
!define EXENAME "Moongate.exe"
!define INSTALL_MARKER ".moongate-install-root"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Moongate"

Name "${APPNAME}"
OutFile "${OUTFILE}"
; 每用户安装，免 UAC 弹窗（与“允许用户直接安装”的诉求一致）
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\Programs\${APPNAME}"
SetCompressor /SOLID lzma

!define MUI_ICON "${ICON_PATH}"
!define MUI_UNICON "${ICON_PATH}"
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXENAME}"
!define MUI_FINISHPAGE_RUN_TEXT "立即运行 ${APPNAME}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"

Section "安装"
  ; 更新安装：App 以 /UPDATEPID=<pid> 启动本安装器，这里先等旧进程完全退出再覆盖文件，
  ; 避免「安装器已启动但旧 App 仍占用 $INSTDIR 文件」的竞态导致部分覆盖 / 更新后无法启动。
  ${GetParameters} $R0
  ${GetOptions} $R0 "/UPDATEPID=" $R1
  ${If} $R1 != ""
    ; OpenProcess(SYNCHRONIZE=0x00100000, FALSE, pid)
    System::Call 'kernel32::OpenProcess(i 0x00100000, i 0, i $R1) i .R2'
    ${If} $R2 <> 0
      ; 最多等 15s；旧进程已退出会立即返回。
      System::Call 'kernel32::WaitForSingleObject(i $R2, i 15000)'
      System::Call 'kernel32::CloseHandle(i $R2)'
    ${EndIf}
  ${EndIf}

  SetOutPath "$INSTDIR"
  File /r "${PUBLISH_DIR}\*"
  FileOpen $0 "$INSTDIR\${INSTALL_MARKER}" w
  FileWrite $0 "Moongate ${APPVERSION}$\r$\n"
  FileClose $0

  ; 快捷方式
  CreateShortCut "$SMPROGRAMS\${APPNAME}.lnk" "$INSTDIR\${EXENAME}"
  CreateShortCut "$DESKTOP\${APPNAME}.lnk" "$INSTDIR\${EXENAME}"

  ; 卸载信息（当前用户注册表，控制面板可见）
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayVersion" "${APPVERSION}"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayIcon" "$INSTDIR\${EXENAME}"
  WriteRegStr HKCU "${UNINSTKEY}" "Publisher" "月之门 · Moongate"
  WriteRegStr HKCU "${UNINSTKEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoRepair" 1
  ; EstimatedSize 单位 KB
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${UNINSTKEY}" "EstimatedSize" "$0"
SectionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\${APPNAME}.lnk"
  Delete "$DESKTOP\${APPNAME}.lnk"
  IfFileExists "$INSTDIR\${INSTALL_MARKER}" 0 skipRecursiveRemove
  StrCmp "$INSTDIR" "$LOCALAPPDATA\Programs\${APPNAME}" 0 skipRecursiveRemove
  Delete "$INSTDIR\${INSTALL_MARKER}"
  RMDir /r "$INSTDIR"
  Goto uninstallRegistry
skipRecursiveRemove:
  Delete "$INSTDIR\Uninstall.exe"
  Delete "$INSTDIR\${EXENAME}"
  RMDir "$INSTDIR"
uninstallRegistry:
  DeleteRegKey HKCU "${UNINSTKEY}"
  ; 注意：刻意保留 %LOCALAPPDATA%\Moongate（下载的 yt-dlp/ffmpeg 与设置），
  ; 重装无需重新下载依赖；用户想彻底清理可手动删除该目录。
SectionEnd
