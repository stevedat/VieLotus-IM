; ============================================================================
; Sen Việt (VieLotusIM) - Windows Official Native Installer Script (Inno Setup)
; Produces: VieLotus-Setup-x64.exe & VieLotus-Setup-arm64.exe
; Universal x64 + ARM64 Native Windows Text Services Framework (TSF) TIP
; Microsoft Store Win32 / WinGet Silent Installer Compliant
; ============================================================================

#define MyAppName "Sen Việt (VieLotusIM)"
#ifndef MyAppVersion
  #define MyAppVersion "1.1.1"
#endif
#ifndef MyAppArch
  #define MyAppArch "x64"
#endif
#define MyAppPublisher "Trần Phát Đạt (Steve Dat)"
#define MyAppURL "https://github.com/stevedat/VieLotus-IM"

[Setup]
AppId={{C7B08E9D-4762-4C97-8B1F-522197A598DC}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Setup
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}.0
VersionInfoCopyright=Copyright (C) 2026 {#MyAppPublisher}. All rights reserved.
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\VieLotusIM
DefaultGroupName=Sen Việt (VieLotus)
DisableProgramGroupPage=yes
OutputDir=..\..\dist\windows
OutputBaseFilename=VieLotus-Setup-{#MyAppArch}
SetupIconFile=assets\VieLotusIM.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible arm64
ArchitecturesInstallIn64BitMode=x64compatible arm64
PrivilegesRequired=admin
CloseApplications=no
RestartApplications=no
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\VieLotusSettings.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; Native Windows Text Services Framework (TSF) In-process COM TIP DLL (Universal x64 + ARM64)
#if FileExists("bin\x64\VieLotusTIP.dll") && FileExists("bin\arm64\VieLotusTIP.dll")
Source: "bin\x64\VieLotusTIP.dll"; DestDir: "{app}"; DestName: "VieLotusTIP.dll"; Check: not IsArm64; Flags: ignoreversion regserver 64bit restartreplace uninsrestartdelete
Source: "bin\arm64\VieLotusTIP.dll"; DestDir: "{app}"; DestName: "VieLotusTIP.dll"; Check: IsArm64; Flags: ignoreversion regserver 64bit restartreplace uninsrestartdelete
#else
Source: "bin\VieLotusTIP.dll"; DestDir: "{app}"; Flags: ignoreversion regserver 64bit restartreplace uninsrestartdelete
#endif
; Native Win32 Settings & IME Launcher Executable
#if FileExists("bin\x64\VieLotusSettings.exe") && FileExists("bin\arm64\VieLotusSettings.exe")
Source: "bin\x64\VieLotusSettings.exe"; DestDir: "{app}"; DestName: "VieLotusSettings.exe"; Check: not IsArm64; Flags: ignoreversion 64bit
Source: "bin\arm64\VieLotusSettings.exe"; DestDir: "{app}"; DestName: "VieLotusSettings.exe"; Check: IsArm64; Flags: ignoreversion 64bit
#else
Source: "bin\VieLotusSettings.exe"; DestDir: "{app}"; Flags: ignoreversion 64bit skipifsourcedoesntexist
#endif
; Optional Swift C-ABI & Runtime DLLs if staged
Source: "bin\*.dll"; Excludes: "VieLotusTIP.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
; VieLotusCore Resource Bundle (typing-modes.yml)
Source: "bin\VietLotusIM_VieLotusCore.resources\*"; DestDir: "{app}\VietLotusIM_VieLotusCore.resources"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
; Application Branding Icon & System Tray Icons
Source: "assets\VieLotusIM.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "assets\*.png"; DestDir: "{app}\assets"; Flags: ignoreversion

[Icons]
Name: "{group}\Cài đặt Sen Việt (VieLotusIM)"; Filename: "{app}\VieLotusSettings.exe"; IconFilename: "{app}\VieLotusIM.ico"
Name: "{group}\Gỡ cài đặt Sen Việt"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Cài đặt Sen Việt (VieLotusIM)"; Filename: "{app}\VieLotusSettings.exe"; IconFilename: "{app}\VieLotusIM.ico"

[Run]
; Grant Read & Execute ACLs to ALL APPLICATION PACKAGES (S-1-15-2-1) and ALL RESTRICTED APPLICATION PACKAGES (S-1-15-2-2)
; so Windows 10/11 UWP, WinUI 3 (Notepad, Terminal, Search, Start Menu, Edge, Settings) can load VieLotusTIP.dll
Filename: "{sys}\icacls.exe"; Parameters: """{app}"" /grant ""*S-1-15-2-1:(OI)(CI)(RX)"" /grant ""*S-1-15-2-2:(OI)(CI)(RX)"" /T /C /Q"; Flags: runhidden
; Activate Telex & VNI profiles in Windows Language Bar (Win + Space) for both elevated and interactive user contexts
Filename: "{sys}\rundll32.exe"; Parameters: """{app}\VieLotusTIP.dll"",ActivateUserProfilesW"; Flags: runhidden
Filename: "{sys}\rundll32.exe"; Parameters: """{app}\VieLotusTIP.dll"",ActivateUserProfilesW"; Flags: runasoriginaluser runhidden
; Auto-refresh Windows Input Language status and restart ctfmon
Filename: "{sys}\rundll32.exe"; Parameters: "user32.dll,UpdatePerUserSystemParameters"; Flags: runhidden
Filename: "{sys}\ctfmon.exe"; Flags: nowait runhidden
; Post-install checkbox to open Sen Việt Settings Window immediately (skipped automatically during Microsoft Store / WinGet silent install)
Filename: "{app}\VieLotusSettings.exe"; Description: "Mở bảng Cài đặt Sen Việt (VieLotusIM)"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "{sys}\rundll32.exe"; Parameters: """{app}\VieLotusTIP.dll"",DeactivateUserProfilesW"; Flags: runhidden; RunOnceId: "DeactivateVieLotusProfiles"

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
var
  DllPath, OldDllPath: String;
  ResultCode: Integer;
begin
  if CurStep = ssInstall then
  begin
    DllPath := ExpandConstant('{app}\VieLotusTIP.dll');
    OldDllPath := ExpandConstant('{app}\VieLotusTIP.old.dll');
    if FileExists(DllPath) then
    begin
      Exec(ExpandConstant('{sys}\rundll32.exe'), '"' + DllPath + '",DeactivateUserProfilesW', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      DeleteFile(OldDllPath);
      if not DeleteFile(DllPath) then
      begin
        RenameFile(DllPath, OldDllPath);
      end;
      Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM TextInputHost.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;
  end;
end;
