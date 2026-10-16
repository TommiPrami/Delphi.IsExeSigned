unit CIESUnit.Runner;

// Checks the files the command line names, signs the unsigned ones if asked, writes the console output and the NUnit
// log, and sets the exit code.

interface

uses
  Delphi.WildCardMatcher, DNLUnit.NUnitLogger, CIESUnit.Types;

type
  TCIESRunner = class(TObject)
  strict private
    FCommandLine: TCommandLineParameters;
    // FailOnError or LogOnly, Auto resolved
    FFailMode: TFailMode;
    FInvalidSignatures: Integer;
    FLineIndent: string;
    FLogger: TNUnitLogger;
    // Of the file being checked, begun and ended by CheckFile
    FLogTestCase: TNUnitTestCase;
    // Begun and ended by Run
    FLogTestSuite: TNUnitTestSuite;
    FSignedFiles: Integer;
    FSignerFilter: TWildCardFilter;
    FSignFiles: Boolean;
    FSignFilter: TWildCardFilter;
    FSignTimeouts: Integer;
    FUnsignedFiles: Integer;
    FVerifySignatures: Boolean;
    // Checks one file in its own log test case. False when the run must stop.
    function CheckFile(const AFileName: string): Boolean;
    // Checks one file, signs it first if asked. False when the run must stop.
    function CheckFileSignature(const AFileName: string): Boolean;
    // 'ERROR: ' with FailMode LogOnly, for the console line of a file that failed the check
    function FailedCheckPrefix: string;
    // Log result of a file that failed the check: an error with FailMode LogOnly, as then the log is the only place
    // the failure shows
    function FailedCheckResult: TNUnitTestResult;
    function MustVerifySignature(const ASignerName: string; const ASignedNow: Boolean): Boolean;
    // Runs the sign command for AFileName, ASignError tells what went wrong, if anything. False when the run must
    // stop (timeout and ContinueOnSignTimeout is False).
    function SignFile(const AFileName: string; var ASignError: string): Boolean;
    procedure ReportSignedFile(const AFileName, ASignerName: string; const ASignedNow: Boolean);
    procedure ReportUnsignedFile(const AFileName, ASignError: string);
    // Saves the log, if one is asked for
    procedure SaveLog;
    procedure SetExitCode;
    // Sets the exit code of an error, not with FailMode LogOnly
    procedure SetFailExitCode(const AExitCode: Integer);
    // Result and message of the log test case of the file being checked
    procedure SetLogTestResult(const AResult: TNUnitTestResult; const AMessage: string);
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
  FFailMode := FCommandLine.GetEffectiveFailMode;

  // Always collected, saved only if a log file is asked for
  FLogger := TNUnitLogger.Create;

  FVerifySignatures := FCommandLine.GetEffectiveVerify;
  FSignerFilter := TWildCardFilter.Create(SplitPatterns(FCommandLine.VerifySigners), [], []);
  FSignFiles := not FCommandLine.SignCommand.IsEmpty;
  // Matched against the full path
  FSignFilter := TWildCardFilter.Create(SplitPatterns(FCommandLine.SignFilter), [], []);
end;

destructor TCIESRunner.Destroy;
begin
  FLogger.Free;

  inherited Destroy;
end;

function TCIESRunner.CheckFile(const AFileName: string): Boolean;
begin
  // Begun here, so the duration covers the signing too. Result and message are set when they are known.
  FLogTestCase := FLogTestSuite.AddTestCase(AFileName, ntrPassed);
  try
    try
      Result := CheckFileSignature(AFileName);
    except
      on E: Exception do
      begin
        // The run ends with the exception, the log tells which file it came from
        SetLogTestResult(ntrError, E.ClassName + ': ' + E.Message);

        raise;
      end;
    end;
  finally
    FLogTestCase.EndTestCase;
    FLogTestCase := nil;
  end;
end;

function TCIESRunner.CheckFileSignature(const AFileName: string): Boolean;
var
  LSignerName: string;
begin
  Result := True;

  var LIsSigned := IsExeSigned(AFileName, LSignerName);
  var LSignedNow := False;
  // What went wrong with the sign command, for the log
  var LSignError := '';

  if not LIsSigned and FSignFiles and FSignFilter.Accepts(AFileName) then
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

function TCIESRunner.FailedCheckPrefix: string;
begin
  Result := if FFailMode = LogOnly then 'ERROR: ' else '';
end;

function TCIESRunner.FailedCheckResult: TNUnitTestResult;
begin
  Result := if FFailMode = LogOnly then ntrError else ntrFailed;
end;

function TCIESRunner.MustVerifySignature(const ASignerName: string; const ASignedNow: Boolean): Boolean;
begin
  // Just signed files are always checked, to make sure the signing really worked
  Result := ASignedNow or (FVerifySignatures and FSignerFilter.Accepts(ASignerName));
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

  if not RunSignFileCommand(FCommandLine.SignCommand, AFileName, FCommandLine.SignTimeout, LSignExitCode) then
  begin
    ASignError := 'Sign command did not finish in ' + FCommandLine.SignTimeout.ToString + ' seconds, it was stopped';

    Writeln(FLineIndent + '  ERROR: ' + ASignError);

    Inc(FSignTimeouts);

    if not FCommandLine.ContinueOnSignTimeout then
    begin
      SetLogTestResult(ntrError, ASignError);

      Writeln('Stopped, ContinueOnSignTimeout is False');

      SetFailExitCode(EXIT_CODE_SIGN_TIMEOUT);
      Result := False;
    end;
  end
  else if LSignExitCode <> 0 then
  begin
    ASignError := 'Sign command returned exit code ' + LSignExitCode.ToString;

    Writeln(FLineIndent + '  ' + ASignError);
  end;
end;

procedure TCIESRunner.ReportSignedFile(const AFileName, ASignerName: string; const ASignedNow: Boolean);
var
  LErrorMessage: string;
begin
  var LSignedText := (if ASignedNow then 'Signed now by ' else 'Signed by ') + ASignerName.QuotedString('"');
  var LSignedLine := AFileName.QuotedString('"') + ' - is ' + LSignedText;

  if not MustVerifySignature(ASignerName, ASignedNow) then
  begin
    Writeln(FLineIndent + '- ' + LSignedLine);

    SetLogTestResult(ntrPassed, LSignedText);
  end
  else if IsSignatureValid(AFileName, LErrorMessage) then
  begin
    Writeln(FLineIndent + '- ' + LSignedLine + ' - signature is valid');

    SetLogTestResult(ntrPassed, LSignedText + ', signature is valid');
  end
  else
  begin
    Writeln(FLineIndent + '! ' + FailedCheckPrefix + LSignedLine + ' - signature is NOT valid: ' + LErrorMessage);

    SetLogTestResult(FailedCheckResult, LSignedText + ', signature is NOT valid: ' + LErrorMessage);

    Inc(FInvalidSignatures);
  end;
end;

procedure TCIESRunner.ReportUnsignedFile(const AFileName, ASignError: string);
begin
  Writeln(FLineIndent + '* ' + FailedCheckPrefix + AFileName.QuotedString('"') +  ' - is NOT Signed');

  SetLogTestResult(FailedCheckResult, 'Not signed' + (if ASignError.IsEmpty then '' else '. ' + ASignError));

  Inc(FUnsignedFiles);
end;

procedure TCIESRunner.Run;
begin
  FLogTestSuite := FLogger.AddTestSuite(LOG_TEST_SUITE_NAME);
  try
    var LFiles := GetFiles(FCommandLine.Files, FCommandLine.Recursive);
    var LFilesCount := Length(LFiles);

    if LFilesCount = 0 then
    begin
      var LError := 'no files match the pattern ' + FCommandLine.Files.QuotedString('"');

      // Found out only now, so it is a result of the run, like a file that is not signed
      Writeln(ParamValueErrorText(PARAM_FILES, LError));
      SetFailExitCode(EXIT_CODE_PARAM_VALUE_ERROR);
      // Not begun, nothing was timed
      FLogTestSuite.AddTestCase(FCommandLine.Files, ntrError, LError, '', 0, False);
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
    // Ended before saving, SaveToFile does not accept anything still running
    FLogTestSuite.EndTestSuite;

    // Also when the run stops early, the log tells how far it got
    SaveLog;
  end;
end;

procedure TCIESRunner.SaveLog;
begin
  var LLogFileName := FCommandLine.GetLogFileName;

  if LLogFileName.IsEmpty then
    Exit;

  FLogger.SaveToFile(LLogFileName, FCommandLine.LogOverwrite);

  Writeln('Log written to ' + LLogFileName.QuotedString('"'));
end;

procedure TCIESRunner.SetExitCode;
begin
  if FUnsignedFiles > 0 then
    SetFailExitCode(EXIT_CODE_NOT_SIGNED)
  else if FInvalidSignatures > 0 then
    SetFailExitCode(EXIT_CODE_SIGNATURE_NOT_VALID);
end;

procedure TCIESRunner.SetFailExitCode(const AExitCode: Integer);
begin
  if FFailMode = FailOnError then
    ExitCode := AExitCode;
end;

procedure TCIESRunner.SetLogTestResult(const AResult: TNUnitTestResult; const AMessage: string);
begin
  FLogTestCase.TestResult := AResult;
  FLogTestCase.Message := AMessage;
end;

procedure TCIESRunner.WriteSummary(const AFilesCount: Integer);
begin
  var LSummary := AFilesCount.ToString + ' file(s) checked, ' + FUnsignedFiles.ToString + ' of them unsigned';

  if FSignFiles then
    LSummary := LSummary + ', ' + FSignedFiles.ToString + ' signed now';

  if FSignTimeouts > 0 then
    LSummary := LSummary + ', ' + FSignTimeouts.ToString + ' sign command timeout(s)';

  if FVerifySignatures or FSignFiles then
    LSummary := LSummary + ', ' + FInvalidSignatures.ToString + ' with invalid signature';

  Writeln(LSummary + '.');
end;

end.
