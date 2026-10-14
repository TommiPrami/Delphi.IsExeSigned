unit CIESUnit.Runner;

// Checks the files the command line names, signs the unsigned ones if asked, writes the console output and the NUnit
// log, and sets the exit code.

interface

uses
  System.Diagnostics, Delphi.WildCardMatcher, DNLUnit.NUnitLogger, CIESUnit.Types;

type
  TCIESRunner = class(TObject)
  strict private
    FCheckSignatures: Boolean;
    FCommandLine: TCommandLineParameters;
    FFileStopwatch: TStopwatch;
    FInvalidSignatures: Integer;
    FLineIndent: string;
    FLogger: TNUnitLogger;
    FLogTestSuite: TNUnitTestSuite;
    FSignedFiles: Integer;
    FSignerFilter: TWildCardFilter;
    FSignFileFilter: TWildCardFilter;
    FSignFiles: Boolean;
    FSignTimeouts: Integer;
    FUnsignedFiles: Integer;
    // Checks one file, signs it first if asked. False when the run must stop.
    function CheckFile(const AFileName: string): Boolean;
    function MustCheckSignature(const ASignerName: string; const ASignedNow: Boolean): Boolean;
    // Runs the sign command for AFileName, ASignError tells what went wrong, if anything. False when the run must
    // stop (timeout and ContinueOnSignTimeout is False).
    function SignFile(const AFileName: string; var ASignError: string): Boolean;
    // Log test case of the current file, its duration from FFileStopwatch
    procedure AddLogTestCase(const AFileName: string; const AResult: TNUnitTestResult; const AMessage: string);
    procedure ReportSignedFile(const AFileName, ASignerName: string; const ASignedNow: Boolean);
    procedure ReportUnsignedFile(const AFileName, ASignError: string);
    // Saves the log, if one is asked for
    procedure SaveLog;
    procedure SetExitCode;
    procedure WriteSummary(const AFilesCount: Integer);
  public
    // ACommandLine is parsed and validated (ParseCommandLine), and not owned
    constructor Create(const ACommandLine: TCommandLineParameters);
    destructor Destroy; override;

    procedure Run;
  end;

implementation

uses
  System.SysUtils, CIESUnit.Commandline, CIESUnit.Consts, CIESUnit.Utils;

// No patterns, the filter accepts everything
function SplitPatterns(const APatterns: string): TArray<string>;
begin
  Result := APatterns.Split([';'], TStringSplitOptions.ExcludeEmpty);
end;

{ TCIESRunner }

constructor TCIESRunner.Create(const ACommandLine: TCommandLineParameters);
begin
  inherited Create;

  FCommandLine := ACommandLine;

  // Always collected, saved only if a log file is asked for
  FLogger := TNUnitLogger.Create;
  FLogTestSuite := FLogger.AddTestSuite(LOG_TEST_SUITE_NAME);

  FCheckSignatures := FCommandLine.CheckIsSignatureValid or not FCommandLine.CheckSignatureSignerFilter.IsEmpty;
  FSignerFilter := TWildCardFilter.Create(SplitPatterns(FCommandLine.CheckSignatureSignerFilter), [], []);
  FSignFiles := not FCommandLine.SignFileCommandLine.IsEmpty;
  // Matched against the full path
  FSignFileFilter := TWildCardFilter.Create(SplitPatterns(FCommandLine.SignFileWildCard), [], []);
end;

destructor TCIESRunner.Destroy;
begin
  FLogger.Free;

  inherited Destroy;
end;

function TCIESRunner.CheckFile(const AFileName: string): Boolean;
var
  LSignerName: string;
begin
  Result := True;
  FFileStopwatch := TStopwatch.StartNew;

  var LIsSigned := IsExeSigned(AFileName, LSignerName);
  var LSignedNow := False;
  // What went wrong with the sign command, for the log
  var LSignError := '';

  if not LIsSigned and FSignFiles and FSignFileFilter.Accepts(AFileName) then
  begin
    if not SignFile(AFileName, LSignError) then
      Exit(False);

    LIsSigned := IsExeSigned(AFileName, LSignerName);
    LSignedNow := LIsSigned;

    if LSignedNow then
      Inc(FSignedFiles);
  end;

  if LIsSigned then
    ReportSignedFile(AFileName, LSignerName, LSignedNow)
  else
    ReportUnsignedFile(AFileName, LSignError);
end;

function TCIESRunner.MustCheckSignature(const ASignerName: string; const ASignedNow: Boolean): Boolean;
begin
  // Just signed files are always checked, to make sure the signing really worked
  Result := ASignedNow or (FCheckSignatures and FSignerFilter.Accepts(ASignerName));
end;

function TCIESRunner.SignFile(const AFileName: string; var ASignError: string): Boolean;
var
  LSignExitCode: Cardinal;
begin
  Result := True;
  ASignError := '';

  // Written and flushed before running the command, so sign tool output comes after this line, also when the output
  // is redirected (buffered)
  Writeln(FLineIndent + '> ' + AFileName.QuotedString('"') +  ' - is NOT Signed, signing it');
  Flush(Output);

  if not RunSignFileCommand(FCommandLine.SignFileCommandLine, AFileName, FCommandLine.SignTimeout, LSignExitCode) then
  begin
    ASignError := 'Sign command did not finish in ' + FCommandLine.SignTimeout.ToString + ' seconds, it was stopped';

    Writeln(FLineIndent + '  ERROR: ' + ASignError);

    Inc(FSignTimeouts);

    if not FCommandLine.ContinueOnSignTimeout then
    begin
      AddLogTestCase(AFileName, ntrError, ASignError);

      Writeln('Stopped, ContinueOnSignTimeout is False');

      ExitCode := EXIT_CODE_SIGN_TIMEOUT;
      Result := False;
    end;
  end
  else if LSignExitCode <> 0 then
  begin
    ASignError := 'Sign command returned exit code ' + LSignExitCode.ToString;

    Writeln(FLineIndent + '  ' + ASignError);
  end;
end;

procedure TCIESRunner.AddLogTestCase(const AFileName: string; const AResult: TNUnitTestResult; const AMessage: string);
begin
  FLogTestSuite.AddTestCase(AFileName, AResult, FFileStopwatch.Elapsed.TotalSeconds, AMessage);
end;

procedure TCIESRunner.ReportSignedFile(const AFileName, ASignerName: string; const ASignedNow: Boolean);
var
  LErrorMessage: string;
begin
  var LSignedText := (if ASignedNow then 'Signed now by ' else 'Signed by ') + ASignerName.QuotedString('"');
  var LSignedLine := AFileName.QuotedString('"') + ' - is ' + LSignedText;

  if not MustCheckSignature(ASignerName, ASignedNow) then
  begin
    Writeln(FLineIndent + '- ' + LSignedLine);

    AddLogTestCase(AFileName, ntrPassed, LSignedText);
  end
  else if IsSignatureValid(AFileName, LErrorMessage) then
  begin
    Writeln(FLineIndent + '- ' + LSignedLine + ' - signature is valid');

    AddLogTestCase(AFileName, ntrPassed, LSignedText + ', signature is valid');
  end
  else
  begin
    Writeln(FLineIndent + '! ' + LSignedLine + ' - signature is NOT valid: ' + LErrorMessage);

    AddLogTestCase(AFileName, ntrFailed, LSignedText + ', signature is NOT valid: ' + LErrorMessage);

    Inc(FInvalidSignatures);
  end;
end;

procedure TCIESRunner.ReportUnsignedFile(const AFileName, ASignError: string);
begin
  Writeln(FLineIndent + '* ' + AFileName.QuotedString('"') +  ' - is NOT Signed');

  // Like the exit code: not signed fails only with ErrorIfNotSigned, otherwise it is a warning
  AddLogTestCase(AFileName, if FCommandLine.ErrorIfNotSigned then ntrFailed else ntrWarning,
    'Not signed' + (if ASignError.IsEmpty then '' else '. ' + ASignError));

  Inc(FUnsignedFiles);
end;

procedure TCIESRunner.Run;
begin
  try
    var LFiles := GetFiles(FCommandLine.FileName, FCommandLine.RecurseSubDirs);
    var LFilesCount := Length(LFiles);

    if LFilesCount = 0 then
    begin
      var LError := 'no files match the pattern ' + FCommandLine.FileName.QuotedString('"');

      SetParamValueError(PARAM_FILE_NAME, LError);
      FLogTestSuite.AddTestCase(FCommandLine.FileName, ntrError, 0.0, LError);
      Exit;
    end;

    var LMultipleFiles := LFilesCount > 1;
    FLineIndent := if LMultipleFiles then '  ' else '';

    if LMultipleFiles then
      Writeln(LFilesCount.ToString + ' files found.');

    for var LFileName in LFiles do
      if not CheckFile(LFileName) then
        Exit;

    if LMultipleFiles then
      WriteSummary(LFilesCount);

    SetExitCode;
  finally
    // Also when the run stops early, the log tells how far it got
    SaveLog;
  end;
end;

procedure TCIESRunner.SaveLog;
begin
  var LLogFileName := FCommandLine.GetLogFileName;

  if LLogFileName.IsEmpty then
    Exit;

  FLogger.SaveToFile(LLogFileName, FCommandLine.AllowLogOverwrite);

  Writeln('Log written to ' + LLogFileName.QuotedString('"'));
end;

procedure TCIESRunner.SetExitCode;
begin
  if (FUnsignedFiles > 0) and FCommandLine.ErrorIfNotSigned then
    ExitCode := EXIT_CODE_NOT_SIGNED
  else if FInvalidSignatures > 0 then
    ExitCode := EXIT_CODE_SIGNATURE_NOT_VALID;
end;

procedure TCIESRunner.WriteSummary(const AFilesCount: Integer);
begin
  var LSummary := AFilesCount.ToString + ' file(s) checked, ' + FUnsignedFiles.ToString + ' of them unsigned';

  if FSignFiles then
    LSummary := LSummary + ', ' + FSignedFiles.ToString + ' signed now';

  if FSignTimeouts > 0 then
    LSummary := LSummary + ', ' + FSignTimeouts.ToString + ' sign command timeout(s)';

  if FCheckSignatures or FSignFiles then
    LSummary := LSummary + ', ' + FInvalidSignatures.ToString + ' with invalid signature';

  Writeln(LSummary + '.');
end;

end.
