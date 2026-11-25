; ============================================================================
; Sen Việt (VieLotusIM) - Clean Native Windows Installer Script (Inno Setup 6)
; Produces: VieLotus-Setup-x64.exe & VieLotus-Setup-arm64.exe
; Bundles:
;   - x64 / ARM64X (ARM64 + ARM64EC) VieLotusTIP.dll (64-bit COM InprocServer32)
;   - x86 (Win32 WOW64) VieLotusTIP32.dll (32-bit WOW6432Node COM InprocServer32)
;   - VieLotusSettings.exe (Native Win32 Security ACL + TSF registration, zero LOLBins)
; ============================================================================

#define MyAppName "Sen Việt (VieLotusIM)"
#ifndef MyAppVersion
  #define MyAppVersion "2.0.10"
#endif
#ifndef MyAppArch
  #define MyAppArch "x64"
#endif
#define MyAppPublisher "Trần Phát Đạt (Steve Dat)"
#define MyAppURL "https://github.com/stevedat/VieLotus-IM"

[Setup]
AppId={{C7B08E9D-4762-4C97-8B1F-522197A598DE}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Setup ({#MyAppArch})
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}.0
VersionInfoCopyright=Copyright (C) 2026 {#MyAppPublisher}. All rights reserved.
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\VieLotusIM
DefaultGroupName=Sen Việt (VieLotusIM)
DisableProgramGroupPage=yes
OutputDir=..\..\dist\windows
OutputBaseFilename=VieLotus-Setup-{#MyAppArch}
SetupIconFile=assets\VieLotusIM.ico
Compression=lzma2/fast
SolidCompression=no
WizardStyle=modern
#if MyAppArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
PrivilegesRequired=admin
CloseApplications=no
RestartApplications=no
Uninstallable=yes
UninstallDisplayIcon={app}\VieLotusIM.ico
UninstallDisplayName=Sen Việt (VieLotusIM) — Bộ gõ Tiếng Việt

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Icons]
Name: "{group}\Cài đặt Sen Việt (VieLotusIM)"; Filename: "{app}\VieLotusSettings.exe"; Parameters: "--settings"; WorkingDir: "{app}"; IconFilename: "{app}\VieLotusIM.ico"
Name: "{group}\Gỡ cài đặt Sen Việt (VieLotusIM)"; Filename: "{uninstallexe}"; IconFilename: "{app}\VieLotusIM.ico"

[Files]
; 64-bit Native TSF COM TIP DLL (x64 on x64, ARM64X [ARM64 + ARM64EC] on ARM64)
#if MyAppArch == "arm64"
Source: "bin\arm64\VieLotusTIP.dll"; DestDir: "{app}"; DestName: "VieLotusTIP.dll"; Flags: ignoreversion 64bit restartreplace
Source: "bin\arm64\VieLotusSettings.exe"; DestDir: "{app}"; DestName: "VieLotusSettings.exe"; Flags: ignoreversion 64bit restartreplace
#else
Source: "bin\x64\VieLotusTIP.dll"; DestDir: "{app}"; DestName: "VieLotusTIP.dll"; Flags: ignoreversion 64bit restartreplace
Source: "bin\x64\VieLotusSettings.exe"; DestDir: "{app}"; DestName: "VieLotusSettings.exe"; Flags: ignoreversion 64bit restartreplace
#endif
; 32-bit WOW64 TSF COM TIP DLL (supports 32-bit x86 apps such as Zalo PC, Steam, legacy Win32 on both x64 & ARM64)
Source: "bin\x86\VieLotusTIP32.dll"; DestDir: "{app}"; DestName: "VieLotusTIP32.dll"; Flags: ignoreversion restartreplace
; VieLotusCore Resource Bundle (typing-modes.yml)
Source: "bin\VietLotusIM_VieLotusCore.resources\*"; DestDir: "{app}\VietLotusIM_VieLotusCore.resources"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
; Application Branding Icon & System Tray Icons
Source: "assets\VieLotusIM.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "assets\*.png"; DestDir: "{app}\assets"; Flags: ignoreversion

[Run]
; Native Win32 provisioning: grants AppContainer RX ACLs via SetNamedSecurityInfoW and registers
; 64-bit (KEY_WOW64_64KEY) + 32-bit WOW6432Node (KEY_WOW64_32KEY) COM/TSF entries cleanly.
Filename: "{app}\VieLotusSettings.exe"; Parameters: "--register-tsf"; Flags: waituntilterminated
; Activate Sen Việt Telex/VNI profiles in the logged-in user's Windows Language Bar (Win + Space)
Filename: "{app}\VieLotusSettings.exe"; Parameters: "--activate"; Flags: runasoriginaluser waituntilterminated
; Open Settings UI after interactive install (skipped during silent /VERYSILENT install)
Filename: "{app}\VieLotusSettings.exe"; Parameters: "--settings"; Description: "Mở bảng Cài đặt Sen Việt (VieLotusIM)"; Flags: postinstall nowait skipifsilent runasoriginaluser

[UninstallRun]
Filename: "{app}\VieLotusSettings.exe"; Parameters: "--unregister-tsf"; RunOnceId: "VieLotusUnregisterTsf"; Flags: waituntilterminated

[Code]
procedure PrepareDllForHotUpgrade(BaseName: String);
var
  DllPath, OldDllPath: String;
  I: Integer;
begin
  DllPath := ExpandConstant('{app}\') + BaseName + '.dll';
  DeleteFile(ExpandConstant('{app}\') + BaseName + '.old.dll');
  for I := 1 to 99 do
  begin
    DeleteFile(ExpandConstant('{app}\') + BaseName + '.old.' + IntToStr(I) + '.dll');
  end;
  if FileExists(DllPath) then
  begin
    if not DeleteFile(DllPath) then
    begin
      for I := 1 to 99 do
      begin
        OldDllPath := ExpandConstant('{app}\') + BaseName + '.old.' + IntToStr(I) + '.dll';
        DeleteFile(OldDllPath);
        if RenameFile(DllPath, OldDllPath) then
        begin
          Break;
        end;
      end;
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    DeleteFile(ExpandConstant('{app}\VieLotusCAPI.dll'));
    PrepareDllForHotUpgrade('VieLotusTIP');
    PrepareDllForHotUpgrade('VieLotusTIP32');
  end;
end;
