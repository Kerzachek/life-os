; Inno Setup script for Life OS (home_organizer) - password protected installer.
; Paths are relative to the folder containing this file (project root).
; Compile with: ISCC.exe installer.iss  (or run build_installer.ps1)

#define MyAppName "Life OS"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#define MyAppPublisher "Artem Chugaev"
#define MyAppExeName "home_organizer.exe"
#define MyAppSourceDir "build\windows\x64\runner\Release"

; Installer password. Override from the command line: ISCC.exe /DInstallPassword=secret installer.iss
#ifndef InstallPassword
  #define InstallPassword "2486"
#endif

[Setup]
AppId={{8F2B5A3C-1122-4D3E-9456-ABCDEF123456}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
OutputDir=build\installer
OutputBaseFilename=LifeOS_Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; --- Password protection (files are encrypted with the password) ---
Password={#InstallPassword}
Encryption=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Whole Flutter Release output (exe, dlls, data\ with flutter_assets). Stray installer.iss copies are excluded.
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Excludes: "installer.iss"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
