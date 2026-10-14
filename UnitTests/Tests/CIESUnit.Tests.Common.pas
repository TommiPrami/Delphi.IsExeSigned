unit CIESUnit.Tests.Common;

// Shared by the test fixtures: test files in a temp folder, fake sign tools, and running IsExeSigned.exe.

interface

type
  TTestFileKind = (tfkSigned, tfkTampered, tfkUnsigned);

  // Fake sign tools (batch files). Each one appends the parameter it got to SignToolLog.
  //   stkSign        - copies a validly signed file over the file to sign
  //   stkSignInvalid - copies a signed file with a broken signature over it
  //   stkFail        - does not sign, exits with code 7
  //   stkHang        - starts a child process that runs a few seconds, then writes HangMarker (unless it is stopped)
  TSignToolKind = (stkSign, stkSignInvalid, stkFail, stkHang);

  // Result of one IsExeSigned.exe run
  TRunResult = record
    ExitCode: Integer;
    Output: string;
  end;

  // A fresh temp folder per instance, deleted on Free.
  //   <Root>\Test Files - the files to check, a space in the path on purpose, quoting must work everywhere
  //   <Root>\Tools      - fake sign tools and their source files, outside of the checked files. Without spaces (8.3
  //                       path, if the temp path has them), as quotes in the -SignFileCommandLine value do not get
  //                       through the command line parsing
  TTestFiles = class(TObject)
  strict private
    FFilesDir: string;
    FRoot: string;
    FToolsDir: string;
    procedure WriteBatchFile(const AFileName: string; const ALines: array of string);
  public
    constructor Create;
    destructor Destroy; override;
    // Adds a file under FilesDir, ARelativeName can have sub directories. Returns its full path.
    function Add(const ARelativeName: string; const AKind: TTestFileKind): string;
    function CreateSignTool(const AKind: TSignToolKind): string;
    function HangMarker: string;
    function PathOf(const ARelativeName: string): string;
    // What the sign tools were called with, one line per call, '' if never called
    function SignToolLog: string;
    function SignToolLogFileName: string;
    property FilesDir: string read FFilesDir;
    property Root: string read FRoot;
  end;

// IsExeSigned.exe under test: the ISEXESIGNED_EXE environment variable, or the most recently built
// <repository>\<Win32|Win64>\<Release|Debug>\IsExeSigned.exe
function IsExeSignedExe: string;
function RunIsExeSigned(const AArguments: array of string): TRunResult;
// A Windows file with a valid embedded signature, used as the source of all signed test files
function SignedSystemFile: string;

implementation

uses
  Winapi.Windows, System.IOUtils, System.SysUtils, CIESUnit.Utils;

const
  BUILD_CONFIGS: array[0..1] of string = ('Release', 'Debug');
  BUILD_PLATFORMS: array[0..1] of string = ('Win32', 'Win64');
  // Generous, the slowest test (sign timeouts) takes a few seconds
  RUN_TIMEOUT_MS = 120000;
  SIGNED_FILE_CANDIDATES: array[0..3] of string = ('System32\tar.exe', 'System32\curl.exe', 'System32\kernel32.dll',
    'explorer.exe');

var
  GIsExeSignedExe: string;
  GSignedSystemFile: string;

function QuoteArgument(const AArgument: string): string;
begin
  if AArgument.Contains(' ') then
    Result := '"' + AArgument + '"'
  else
    Result := AArgument;
end;

// 8.3 path of an existing file or directory, or the path as is if there is none
function ShortPathOf(const APath: string): string;
begin
  var LLength := GetShortPathName(PChar(APath), nil, 0);

  if LLength = 0 then
    Exit(APath);

  SetLength(Result, LLength);
  LLength := GetShortPathName(PChar(APath), PChar(Result), LLength);
  SetLength(Result, LLength);
end;

function RepositoryRoot: string;
begin
  var LDirectory := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));

  while LDirectory <> '' do
  begin
    if TFile.Exists(TPath.Combine(LDirectory, 'IsExeSigned.dpr')) then
      Exit(LDirectory);

    if ExtractFileDir(LDirectory) = LDirectory then
      Break;

    LDirectory := ExtractFileDir(LDirectory);
  end;

  raise Exception.Create('Repository root (IsExeSigned.dpr) not found above ' + ParamStr(0));
end;

function IsExeSignedExe: string;
var
  LNewest: TDateTime;
begin
  if not GIsExeSignedExe.IsEmpty then
    Exit(GIsExeSignedExe);

  GIsExeSignedExe := GetEnvironmentVariable('ISEXESIGNED_EXE');

  if GIsExeSignedExe.IsEmpty then
  begin
    var LRoot := RepositoryRoot;
    LNewest := 0;

    for var LPlatform in BUILD_PLATFORMS do
      for var LConfig in BUILD_CONFIGS do
      begin
        var LFileName := TPath.Combine(LRoot, LPlatform + '\' + LConfig + '\IsExeSigned.exe');

        if TFile.Exists(LFileName) and (TFile.GetLastWriteTime(LFileName) > LNewest) then
        begin
          GIsExeSignedExe := LFileName;
          LNewest := TFile.GetLastWriteTime(LFileName);
        end;
      end;
  end;

  if GIsExeSignedExe.IsEmpty or not TFile.Exists(GIsExeSignedExe) then
    raise Exception.Create('IsExeSigned.exe not found, build IsExeSigned.dproj first (or set ISEXESIGNED_EXE)');

  Result := GIsExeSignedExe;
end;

function RunIsExeSigned(const AArguments: array of string): TRunResult;
var
  LExitCode: Cardinal;
  LProcessInfo: TProcessInformation;
  LSecurityAttributes: TSecurityAttributes;
  LStartupInfo: TStartupInfo;
begin
  // Output to a file, not a pipe: no reader thread needed, and a full pipe can not block the process
  var LOutputFileName := TPath.GetTempFileName;
  try
    LSecurityAttributes.nLength := SizeOf(LSecurityAttributes);
    LSecurityAttributes.lpSecurityDescriptor := nil;
    LSecurityAttributes.bInheritHandle := True;

    var LOutput := CreateFile(PChar(LOutputFileName), GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, @LSecurityAttributes,
      CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);

    if LOutput = INVALID_HANDLE_VALUE then
      RaiseLastOSError;

    try
      // Empty input, so the Debug build's "Press [Enter]" does not wait
      var LInput := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, @LSecurityAttributes, OPEN_EXISTING, 0, 0);

      if LInput = INVALID_HANDLE_VALUE then
        RaiseLastOSError;

      try
        FillChar(LStartupInfo, SizeOf(LStartupInfo), 0);
        LStartupInfo.cb := SizeOf(LStartupInfo);
        LStartupInfo.dwFlags := STARTF_USESTDHANDLES;
        LStartupInfo.hStdInput := LInput;
        LStartupInfo.hStdOutput := LOutput;
        LStartupInfo.hStdError := LOutput;

        var LCommandLine := QuoteArgument(IsExeSignedExe);

        for var LArgument in AArguments do
          LCommandLine := LCommandLine + ' ' + QuoteArgument(LArgument);

        // CreateProcessW can modify the command line buffer
        UniqueString(LCommandLine);

        if not CreateProcess(nil, PChar(LCommandLine), nil, nil, True, CREATE_NO_WINDOW, nil, nil, LStartupInfo, LProcessInfo) then
          RaiseLastOSError;

        try
          if WaitForSingleObject(LProcessInfo.hProcess, RUN_TIMEOUT_MS) <> WAIT_OBJECT_0 then
          begin
            TerminateProcess(LProcessInfo.hProcess, 1);

            raise Exception.Create('IsExeSigned.exe did not finish in ' + (RUN_TIMEOUT_MS div 1000).ToString + ' seconds');
          end;

          if not GetExitCodeProcess(LProcessInfo.hProcess, LExitCode) then
            RaiseLastOSError;

          Result.ExitCode := Integer(LExitCode);
        finally
          CloseHandle(LProcessInfo.hThread);
          CloseHandle(LProcessInfo.hProcess);
        end;
      finally
        CloseHandle(LInput);
      end;
    finally
      CloseHandle(LOutput);
    end;

    Result.Output := TFile.ReadAllText(LOutputFileName, TEncoding.ANSI);
  finally
    // Not checked, a leftover temp file must not fail a test
    DeleteFile(PChar(LOutputFileName));
  end;
end;

function SignedSystemFile: string;
var
  LErrorMessage: string;
  LSignerName: string;
begin
  if not GSignedSystemFile.IsEmpty then
    Exit(GSignedSystemFile);

  var LWindowsDir := GetEnvironmentVariable('SystemRoot');

  for var LCandidate in SIGNED_FILE_CANDIDATES do
  begin
    var LFileName := TPath.Combine(LWindowsDir, LCandidate);

    if TFile.Exists(LFileName) and IsExeSigned(LFileName, LSignerName) and IsSignatureValid(LFileName, LErrorMessage) then
    begin
      GSignedSystemFile := LFileName;

      Exit(GSignedSystemFile);
    end;
  end;

  raise Exception.Create('No Windows file with a valid embedded signature found (tried: '
    + string.Join(', ', SIGNED_FILE_CANDIDATES) + ')');
end;

{ TTestFiles }

constructor TTestFiles.Create;
begin
  inherited Create;

  FRoot := TPath.Combine(TPath.GetTempPath, 'IsExeSignedTests\' + TPath.GetGUIDFileName);
  FFilesDir := TPath.Combine(FRoot, 'Test Files');
  FToolsDir := TPath.Combine(FRoot, 'Tools');

  ForceDirectories(FFilesDir);
  ForceDirectories(FToolsDir);

  FToolsDir := ShortPathOf(FToolsDir);
end;

destructor TTestFiles.Destroy;
begin
  try
    TDirectory.Delete(FRoot, True);
  except
    // A leftover in the temp folder (e.g. a file still locked) must not fail a test
  end;

  inherited Destroy;
end;

function TTestFiles.Add(const ARelativeName: string; const AKind: TTestFileKind): string;
begin
  Result := PathOf(ARelativeName);

  ForceDirectories(ExtractFilePath(Result));

  case AKind of
    tfkSigned:
      TFile.Copy(SignedSystemFile, Result, True);
    tfkTampered:
      begin
        TFile.Copy(SignedSystemFile, Result, True);

        // One flipped byte inside the sections breaks the signature (the signature itself is at the end of the file)
        var LBytes := TFile.ReadAllBytes(Result);
        var LIndex := Length(LBytes) div 4;
        LBytes[LIndex] := LBytes[LIndex] xor $FF;
        TFile.WriteAllBytes(Result, LBytes);
      end;
    tfkUnsigned:
      TFile.WriteAllText(Result, 'Not signed', TEncoding.ASCII);
  end;
end;

function TTestFiles.CreateSignTool(const AKind: TSignToolKind): string;
const
  TOOL_NAMES: array[TSignToolKind] of string = ('Sign.bat', 'SignInvalid.bat', 'Fail.bat', 'Hang.bat');
begin
  Result := TPath.Combine(FToolsDir, TOOL_NAMES[AKind]);

  var LLog := 'echo %1>>"' + SignToolLogFileName + '"';

  case AKind of
    stkSign:
      begin
        Add('..\Tools\Signed.exe', tfkSigned);
        WriteBatchFile(Result, [LLog, 'copy /y "' + TPath.Combine(FToolsDir, 'Signed.exe') + '" %1 >nul']);
      end;
    stkSignInvalid:
      begin
        Add('..\Tools\Tampered.exe', tfkTampered);
        WriteBatchFile(Result, [LLog, 'copy /y "' + TPath.Combine(FToolsDir, 'Tampered.exe') + '" %1 >nul']);
      end;
    stkFail:
      WriteBatchFile(Result, [LLog, 'exit /b 7']);
    stkHang:
      begin
        // The marker is written by a grandchild of IsExeSigned (a second cmd.exe), so it shows whether a timeout
        // stops the whole process tree and not only the first cmd.exe
        var LChild := TPath.Combine(FToolsDir, 'HangChild.bat');

        WriteBatchFile(LChild, ['ping -n 4 127.0.0.1 >nul', 'echo done>"' + HangMarker + '"']);
        WriteBatchFile(Result, [LLog, 'cmd /c "' + LChild + '"']);
      end;
  end;
end;

function TTestFiles.HangMarker: string;
begin
  Result := TPath.Combine(FToolsDir, 'Hang.marker');
end;

function TTestFiles.PathOf(const ARelativeName: string): string;
begin
  // Not TPath.Combine/GetFullPath, those reject the '<' of a pattern
  Result := ExpandFileName(IncludeTrailingPathDelimiter(FFilesDir) + ARelativeName);
end;

function TTestFiles.SignToolLog: string;
begin
  if TFile.Exists(SignToolLogFileName) then
    Result := TFile.ReadAllText(SignToolLogFileName, TEncoding.ANSI)
  else
    Result := '';
end;

function TTestFiles.SignToolLogFileName: string;
begin
  Result := TPath.Combine(FToolsDir, 'SignTool.log');
end;

procedure TTestFiles.WriteBatchFile(const AFileName: string; const ALines: array of string);
begin
  TFile.WriteAllText(AFileName, '@echo off' + sLineBreak + string.Join(sLineBreak, ALines) + sLineBreak, TEncoding.ASCII);
end;

end.
