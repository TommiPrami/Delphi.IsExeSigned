unit IESUnit.Runner;

// Checks the files the command line names, signs the unsigned ones if asked, writes the console output and the NUnit
// log, and sets the exit code.

interface

uses
  Delphi.WildCardMatcher, DNLUnit.NUnitLogger, IESUnit.Types, IESUnit.Utils;

type
  TIESRunner = class(TObject)
  strict private
    FCertificateExpirationErrors: Integer;
    FCertificateExpirationWarnings: Integer;
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
    // Files signed now, and files of the VerifySigners signers, are our own files, their certificate must not expire
    // soon. Others, e.g. redistributables, are timestamped usually, and stay valid after their certificate expires.
    function MustCheckCertificateExpiration(const ASignerName: string; const ASignedNow: Boolean): Boolean;
    function MustVerifySignature(const ASignerName: string; const ASignedNow: Boolean): Boolean;
    // Runs the sign command for AFileName, ASignError tells what went wrong, if anything. False when the run must
    // stop (timeout and ContinueOnSignTimeout is False).
    function SignFile(const AFileName: string; var ASignError: string): Boolean;
    // Report of a file with a valid signature, whose certificate expiration is checked
    procedure ReportCertificateExpiration(const ASignedLine, ASignedText: string; const AExpiration: TDateTime);
    procedure ReportSignedFile(const AFileName: string; const ASignatureInfo: TSignatureInfo; const ASignedNow: Boolean);
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
  System.DateUtils, System.SysUtils, IESUnit.Commandline, IESUnit.Consts;

// AThresholdDays 0 is off
function ExpirationThresholdReached(const AThresholdDays, ADaysLeft: Integer): Boolean;
begin
  Result := (AThresholdDays > 0) and (ADaysLeft <= AThresholdDays);
end;

// AExpiration is UTC, the text is the local date
function LocalDateText(const AExpiration: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd', TTimeZone.Local.ToLocalTime(AExpiration));
end;

// No patterns, the filter accepts everything
function SplitPatterns(const APatterns: string): TArray<string>;
begin
  Result := APatterns.Split([';'], TStringSplitOptions.ExcludeEmpty);
end;

{ TIESRunner }

constructor TIESRunner.Create(const ACommandLine: TCommandLineParameters);
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

destructor TIESRunner.Destroy;
begin
  FLogger.Free;

  inherited Destroy;
end;

function TIESRunner.CheckFile(const AFileName: string): Boolean;
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

function TIESRunner.CheckFileSignature(const AFileName: string): Boolean;
var
  LSignatureInfo: TSignatureInfo;
begin
  Result := True;

  var LIsSigned := GetSignatureInfo(AFileName, LSignatureInfo);
  var LSignedNow := False;
  // What went wrong with the sign command, for the log
  var LSignError := '';

  if not LIsSigned and FSignFiles and FSignFilter.Accepts(AFileName) then
  begin
    if not SignFile(AFileName, LSignError) then
      Exit(False);

    LIsSigned := GetSignatureInfo(AFileName, LSignatureInfo);
    LSignedNow := LIsSigned;

    if LSignedNow then
      Inc(FSignedFiles);
  end;

  if LIsSigned then
    ReportSignedFile(AFileName, LSignatureInfo, LSignedNow)
  else
    ReportUnsignedFile(AFileName, LSignError);
end;

function TIESRunner.FailedCheckPrefix: string;
begin
  Result := if FFailMode = LogOnly then 'ERROR: ' else '';
end;

function TIESRunner.FailedCheckResult: TNUnitTestResult;
begin
  Result := if FFailMode = LogOnly then ntrError else ntrFailed;
end;

function TIESRunner.MustCheckCertificateExpiration(const ASignerName: string; const ASignedNow: Boolean): Boolean;
begin
  Result := ((FCommandLine.CertificateExpirationWarning > 0) or (FCommandLine.CertificateExpirationError > 0))
    and (ASignedNow or (not FCommandLine.VerifySigners.IsEmpty and FSignerFilter.Accepts(ASignerName)));
end;

function TIESRunner.MustVerifySignature(const ASignerName: string; const ASignedNow: Boolean): Boolean;
begin
  // Just signed files are always checked, to make sure the signing really worked
  Result := ASignedNow or (FVerifySignatures and FSignerFilter.Accepts(ASignerName));
end;

function TIESRunner.SignFile(const AFileName: string; var ASignError: string): Boolean;
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

procedure TIESRunner.ReportCertificateExpiration(const ASignedLine, ASignedText: string; const AExpiration: TDateTime);
begin
  var LDaysLeft := CertificateDaysLeft(AExpiration);
  var LDate := LocalDateText(AExpiration);
  var LExpiration: string;

  if AExpiration = 0.0 then
    LExpiration := 'certificate is not found in the signature'
  else if LDaysLeft < 0 then
    LExpiration := 'certificate expired ' + LDate + ', ' + (-LDaysLeft).ToString + ' days ago'
  else
    LExpiration := 'certificate expires ' + LDate + ', in ' + LDaysLeft.ToString + ' days';

  if (AExpiration = 0.0) or ExpirationThresholdReached(FCommandLine.CertificateExpirationError, LDaysLeft) then
  begin
    Writeln(FLineIndent + '! ' + FailedCheckPrefix + ASignedLine + ' - signature is valid, but the ' + LExpiration);

    SetLogTestResult(FailedCheckResult, ASignedText + ', signature is valid, but the ' + LExpiration);

    Inc(FCertificateExpirationErrors);
  end
  else if ExpirationThresholdReached(FCommandLine.CertificateExpirationWarning, LDaysLeft) then
  begin
    Writeln(FLineIndent + '- ' + ASignedLine + ' - signature is valid - WARNING: ' + LExpiration);

    SetLogTestResult(ntrWarning, ASignedText + ', signature is valid, but the ' + LExpiration);

    Inc(FCertificateExpirationWarnings);
  end
  else
  begin
    Writeln(FLineIndent + '- ' + ASignedLine + ' - signature is valid, certificate valid until ' + LDate);

    SetLogTestResult(ntrPassed, ASignedText + ', signature is valid, certificate valid until ' + LDate);
  end;
end;

procedure TIESRunner.ReportSignedFile(const AFileName: string; const ASignatureInfo: TSignatureInfo; const ASignedNow: Boolean);
var
  LErrorMessage: string;
begin
  var LSignerName := ASignatureInfo.SignerName;
  var LSignedText := (if ASignedNow then 'Signed now by ' else 'Signed by ') + LSignerName.QuotedString('"');
  var LSignedLine := AFileName.QuotedString('"') + ' - is ' + LSignedText;

  if not MustVerifySignature(LSignerName, ASignedNow) then
  begin
    Writeln(FLineIndent + '- ' + LSignedLine);

    SetLogTestResult(ntrPassed, LSignedText);
  end
  else if not IsSignatureValid(AFileName, LErrorMessage) then
  begin
    Writeln(FLineIndent + '! ' + FailedCheckPrefix + LSignedLine + ' - signature is NOT valid: ' + LErrorMessage);

    SetLogTestResult(FailedCheckResult, LSignedText + ', signature is NOT valid: ' + LErrorMessage);

    Inc(FInvalidSignatures);
  end
  else if MustCheckCertificateExpiration(LSignerName, ASignedNow) then
    ReportCertificateExpiration(LSignedLine, LSignedText, ASignatureInfo.CertificateExpiration)
  else
  begin
    Writeln(FLineIndent + '- ' + LSignedLine + ' - signature is valid');

    SetLogTestResult(ntrPassed, LSignedText + ', signature is valid');
  end;
end;

procedure TIESRunner.ReportUnsignedFile(const AFileName, ASignError: string);
begin
  Writeln(FLineIndent + '* ' + FailedCheckPrefix + AFileName.QuotedString('"') +  ' - is NOT Signed');

  SetLogTestResult(FailedCheckResult, 'Not signed' + (if ASignError.IsEmpty then '' else '. ' + ASignError));

  Inc(FUnsignedFiles);
end;

procedure TIESRunner.Run;
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

procedure TIESRunner.SaveLog;
begin
  var LLogFileName := FCommandLine.GetLogFileName;

  if LLogFileName.IsEmpty then
    Exit;

  FLogger.SaveToFile(LLogFileName, FCommandLine.LogOverwrite);

  Writeln('Log written to ' + LLogFileName.QuotedString('"'));
end;

procedure TIESRunner.SetExitCode;
begin
  if FUnsignedFiles > 0 then
    SetFailExitCode(EXIT_CODE_NOT_SIGNED)
  else if FInvalidSignatures > 0 then
    SetFailExitCode(EXIT_CODE_SIGNATURE_NOT_VALID)
  else if FCertificateExpirationErrors > 0 then
    SetFailExitCode(EXIT_CODE_CERTIFICATE_EXPIRING);
end;

procedure TIESRunner.SetFailExitCode(const AExitCode: Integer);
begin
  if FFailMode = FailOnError then
    ExitCode := AExitCode;
end;

procedure TIESRunner.SetLogTestResult(const AResult: TNUnitTestResult; const AMessage: string);
begin
  FLogTestCase.TestResult := AResult;
  FLogTestCase.Message := AMessage;
end;

procedure TIESRunner.WriteSummary(const AFilesCount: Integer);
begin
  var LSummary := AFilesCount.ToString + ' file(s) checked, ' + FUnsignedFiles.ToString + ' of them unsigned';

  if FSignFiles then
    LSummary := LSummary + ', ' + FSignedFiles.ToString + ' signed now';

  if FSignTimeouts > 0 then
    LSummary := LSummary + ', ' + FSignTimeouts.ToString + ' sign command timeout(s)';

  if FVerifySignatures or FSignFiles then
    LSummary := LSummary + ', ' + FInvalidSignatures.ToString + ' with invalid signature';

  if FCertificateExpirationErrors > 0 then
    LSummary := LSummary + ', ' + FCertificateExpirationErrors.ToString + ' with certificate expiring (error)';

  if FCertificateExpirationWarnings > 0 then
    LSummary := LSummary + ', ' + FCertificateExpirationWarnings.ToString + ' with certificate expiring soon (warning)';

  Writeln(LSummary + '.');
end;

end.
