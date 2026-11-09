; Kich ban dong goi Inno Setup cho Du an Game Pixel 2D Phuc Hoi Chuc Nang
; Tac gia: Nong Thi Hong Lan

#define MyAppName "Game Pixel 2D - Phuc Hoi Chuc Nang Khop Vai"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "De tai NCKH"
#define MyAppExeName "GamePixel2D_PHCN.exe"
#define MyOutputDir "..\..\release_installer"

[Setup]
; Thong tin co ban cua ung dung
AppId={{9B78D82A-5D12-4C61-9E5F-7C91D4E03B81}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\GamePixel2D_PHCN
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir={#MyOutputDir}
OutputBaseFilename=Cai_Dat_Game_PHCN_Setup_v1.0
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; File thuc thi Godot Frontend chinh
Source: "..\..\build\GamePixel2D_PHCN.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\build\GamePixel2D_PHCN.pck"; DestDir: "{app}"; Flags: ignoreversion

; Thu muc AI Backend da duoc dong goi bang PyInstaller
Source: "..\..\build\dist\ai_backend\*"; DestDir: "{app}\ai_backend"; Flags: ignoreversion recursesubdirs createallsubdirs

; File huong dan su dung
Source: "..\..\README.md"; DestDir: "{app}"; DestName: "Huong_Dan_Su_Dung.txt"; Flags: ignoreversion isreadme

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
