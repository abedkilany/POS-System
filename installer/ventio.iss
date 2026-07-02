#ifndef AppVersion
  #define AppVersion "1.0.28"
#endif

#ifndef AppBuild
  #define AppBuild "28"
#endif

#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

#ifndef OutputDir
  #define OutputDir "..\build\installer"
#endif

#define AppFullVersion AppVersion + "+" + AppBuild
#define AppPublisher "Ventio"
#define AppExeName "Ventio.exe"
#define AppId "{{B9B6E650-12E8-4E9D-A2F2-04F6B4CB2DC1}"

[Setup]
AppId={#AppId}
AppName=Ventio
AppVersion={#AppFullVersion}
AppVerName=Ventio
UninstallDisplayName=Ventio
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\Ventio
DefaultGroupName=Ventio
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=VentioSetup-{#AppVersion}-build{#AppBuild}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
RestartApplications=yes
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile=..\windows\runner\resources\app_icon.ico
CloseApplications=yes
VersionInfoVersion={#AppVersion}.{#AppBuild}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription=Ventio installer
VersionInfoProductName=Ventio
VersionInfoProductVersion={#AppVersion}.{#AppBuild}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Ventio"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\Ventio"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch Ventio"; Flags: nowait postinstall skipifsilent
