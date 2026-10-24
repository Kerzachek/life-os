; Скрипт сборки инсталлятора Life OS через Inno Setup
#define MyAppName "Life OS"
#define MyAppVersion "1.8.9"
#define MyAppPublisher "Personal"
#define MyAppExeName "home_organizer.exe"
#define MyAppSourceDir "build\windows\x64\runner\Release"

[Setup]
AppId={{D37E84B1-4A59-42E1-9B3C-9B67C9267A10}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=build\installer
OutputBaseFilename=LifeOS-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
; Сбросить кэш иконок Explorer, чтобы панель задач подхватила новую иконку
ChangesAssociations=yes

; Закрывать запущенный экземпляр перед обновлением
CloseApplications=yes
RestartApplications=no
; [Registry] только удаляет значение автозапуска текущего пользователя при деинсталляции
UsedUserAreasWarning=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Основной exe-файл
Source: "{#MyAppSourceDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

; Все зависимые DLL и ресурсы Flutter (data, flutter_windows.dll и т.д.)
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; Убрать запись автозапуска (если включали в настройках) при удалении
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "LifeOS"; Flags: uninsdeletevalue dontcreatekey
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"; ValueType: none; ValueName: "LifeOS"; Flags: uninsdeletevalue dontcreatekey

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
; Перезапуск после тихого обновления из приложения (/VERYSILENT)
Filename: "{app}\{#MyAppExeName}"; Flags: nowait; Check: WizardSilent