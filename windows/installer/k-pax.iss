; Inno Setup script for the K-Pax Windows client.
; Build the app first: flutter build windows --release
; Then: ISCC.exe windows\installer\k-pax.iss

#define MyAppName "K-Pax"
#define MyAppVersion "1.0.56"
#define MyAppPublisher "K-Pax"
#define MyAppURL "https://k-pax.space"
#define MyAppExeName "KPax.exe"
#define ReleaseDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{8F4C2A91-6B17-4E5D-9C3A-1D7E6B0A4F28}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
AllowNoIcons=no
OutputDir=..\..\build\windows\installer
OutputBaseFilename=K-Pax-Setup-{#MyAppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=K-Pax setup
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}.0
InfoBeforeFile=info-ru.txt
CloseApplications=force
RestartApplications=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; Open app after email confirm (kpax://confirmed), same idea as Android.
Root: HKCR; Subkey: "kpax"; ValueType: string; ValueName: ""; ValueData: "URL:K-Pax"; Flags: uninsdeletekey
Root: HKCR; Subkey: "kpax"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCR; Subkey: "kpax\DefaultIcon"; ValueType: string; ValueData: "{app}\{#MyAppExeName},0"
Root: HKCR; Subkey: "kpax\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent shellexec
Filename: "{app}\{#MyAppExeName}"; Flags: nowait skipifnotsilent shellexec

[Code]
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
  Location: String;
begin
  Result := True;
  // An upgrade started without silent flags restarts itself silently.
  if WizardSilent then
    Exit;
  if not RegQueryStringValue(HKLM64,
       'Software\Microsoft\Windows\CurrentVersion\Uninstall\{8F4C2A91-6B17-4E5D-9C3A-1D7E6B0A4F28}_is1',
       'InstallLocation', Location) then
    Exit;
  if Exec(ExpandConstant('{srcexe}'),
       '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /FORCECLOSEAPPLICATIONS',
       '', SW_HIDE, ewNoWait, ResultCode) then
    Result := False;
end;
