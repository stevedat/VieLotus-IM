; ============================================================================
; Sen Việt (VieLotusIM) - Windows Official Native Installer Script (Inno Setup)
; Produces: VieLotus-Setup-x64.exe (Native Windows Text Services Framework TIP)
; ============================================================================

#define MyAppName "Sen Việt (VieLotusIM)"
#ifndef MyAppVersion
  #define MyAppVersion "1.1.1"
#endif
#ifndef MyAppArch
  #define MyAppArch "x64"
#endif
#define MyAppPublisher "VieLotus Project"
#define MyAppURL "https://github.com/vielotus/VietLotusIM"

[Setup]
AppId={{C7B08E9D-4762-4C97-8B1F-522197A598DC}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\VieLotusIM
DefaultGroupName=Sen Việt (VieLotus)
DisableProgramGroupPage=yes
OutputDir=..\..\dist\windows
OutputBaseFilename=VieLotus-Setup-{#MyAppArch}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
#if MyAppArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
PrivilegesRequired=admin
UninstallDisplayIcon={app}\VieLotusIM.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; Core Swift 6 C-ABI DLL and bundled Swift Windows Runtime DLLs
Source: "bin\*.dll"; Excludes: "VieLotusTIP.dll"; DestDir: "{app}"; Flags: ignoreversion
; Native Windows Text Services Framework (TSF) In-process COM TIP DLL
Source: "bin\VieLotusTIP.dll"; DestDir: "{app}"; Flags: ignoreversion regserver 64bit
; VieLotusCore Resource Bundle (lexicon & typing-modes.yml)
Source: "bin\VietLotusIM_VieLotusCore.resources\*"; DestDir: "{app}\VietLotusIM_VieLotusCore.resources"; Flags: ignoreversion recursesubdirs createallsubdirs
; Application Branding Icon & System Tray Icons
Source: "assets\VieLotusIM.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "assets\*.png"; DestDir: "{app}\assets"; Flags: ignoreversion

[Icons]
Name: "{group}\Gỡ cài đặt Sen Việt"; Filename: "{uninstallexe}"

[Run]
; Auto-refresh Windows Input Language status
Filename: "rundll32.exe"; Parameters: "user32.dll,UpdatePerUserSystemParameters"; Flags: runhidden
