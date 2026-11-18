; Inno Setup script for the X-Plm Windows client.
; Build: $env:APP_BRAND='xplm'; flutter build windows --release --dart-define=BRAND=xplm
; Then: ISCC.exe windows\installer\x-plm.iss

#define MyAppName "X-Plm"
#ifndef MyAppVersion
#define MyAppVersion "1.0.73"
#endif
#define MyAppPublisher "X-Plm"
#define MyAppURL "https://x-plm.online"
#define MyAppExeName "XPlm.exe"
#define ReleaseDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{B7E2D4A1-9C38-4F6B-8A1E-2D5C7F90B4E6}
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
OutputBaseFilename=X-Plm-Setup-{#MyAppVersion}
SetupIconFile=..\runner\resources\xplm_app_icon.ico
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
VersionInfoDescription=X-Plm setup
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}.0
InfoBeforeFile=info-ru-xplm.txt
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
; Open app after email confirm (xplm://confirmed), same idea as Android.
Root: HKCR; Subkey: "xplm"; ValueType: string; ValueName: ""; ValueData: "URL:X-Plm"; Flags: uninsdeletekey
Root: HKCR; Subkey: "xplm"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCR; Subkey: "xplm\DefaultIcon"; ValueType: string; ValueData: "{app}\{#MyAppExeName},0"
Root: HKCR; Subkey: "xplm\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent shellexec
Filename: "{app}\{#MyAppExeName}"; Flags: nowait skipifnotsilent shellexec

[Code]
function VersionPart(const S: String; Index: Integer): Integer;
var
  Work, Piece: String;
  Dot, I: Integer;
begin
  Work := S + '.';
  Piece := '0';
  for I := 0 to Index do
  begin
    Dot := Pos('.', Work);
    if Dot = 0 then
    begin
      Result := 0;
      Exit;
    end;
    Piece := Copy(Work, 1, Dot - 1);
    Delete(Work, 1, Dot);
  end;
  Result := StrToIntDef(Piece, 0);
end;

function CompareAppVersions(const Left, Right: String): Integer;
var
  I, A, B: Integer;
  L, R: String;
begin
  L := Left;
  R := Right;
  if Pos('+', L) > 0 then L := Copy(L, 1, Pos('+', L) - 1);
  if Pos('+', R) > 0 then R := Copy(R, 1, Pos('+', R) - 1);
  Result := 0;
  for I := 0 to 3 do
  begin
    A := VersionPart(L, I);
    B := VersionPart(R, I);
    if A > B then begin Result := 1; Exit; end;
    if A < B then begin Result := -1; Exit; end;
  end;
end;

function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
  Location, InstalledVersion: String;
begin
  Result := True;
  // Silent re-exec for upgrades — never silent-downgrade a newer install.
  if WizardSilent then
    Exit;
  if not RegQueryStringValue(HKLM64,
       'Software\Microsoft\Windows\CurrentVersion\Uninstall\{B7E2D4A1-9C38-4F6B-8A1E-2D5C7F90B4E6}_is1',
       'InstallLocation', Location) then
    Exit;
  if RegQueryStringValue(HKLM64,
       'Software\Microsoft\Windows\CurrentVersion\Uninstall\{B7E2D4A1-9C38-4F6B-8A1E-2D5C7F90B4E6}_is1',
       'DisplayVersion', InstalledVersion) then
  begin
    if CompareAppVersions(ExpandConstant('{#MyAppVersion}'), InstalledVersion) < 0 then
      Exit;
  end;
  if Exec(ExpandConstant('{srcexe}'),
       '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /FORCECLOSEAPPLICATIONS',
       '', SW_HIDE, ewNoWait, ResultCode) then
    Result := False;
end;
