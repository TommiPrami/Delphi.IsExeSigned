unit DNLUnit.NUnitLogger;

// Very simple NUnit 3 XML result file writer. No XML library is used, the file is written as plain text.
//
//   LLogger := TNUnitLogger.Create;
//   try
//     // AddTestSuite and AddTestCase also begin the test suite and the test case
//     LTestSuite := LLogger.AddTestSuite('DisallowedList');
//
//     LTestCase := LTestSuite.AddTestCase('Unit1.pas', ntrPassed);
//     if not CheckUnit('Unit1.pas', LMessage) then
//     begin
//       LTestCase.TestResult := ntrFailed;
//       LTestCase.Message := LMessage;
//     end;
//     LTestCase.EndTestCase;
//
//     // Not begun, so it is not timed
//     LTestSuite.AddTestCase('Unit2.pas', ntrSkipped, 'Generated unit', '', 0, False);
//
//     LTestSuite.EndTestSuite;
//
//     LLogger.SaveToFile('TestResults.xml', True);
//   finally
//     LLogger.Free;
//   end;
//
// Written structure: test-run > test-suite (Assembly, added automatically, with environment) > test-suite (TestFixture)
// > test-case
//
// Times: Begin* writes the start time and End* the end time, the duration between them is measured with TStopwatch and
// written in seconds with six decimals, like NUnit does. Everything that is begun must also be ended, SaveToFile raises
// ENUnitLogger otherwise. A test case that is never begun is written as a zero length test case at the time it was added.
// A test suite that is never begun runs from the start of its first test case to the end of its last one. The test run
// lasts from the logger creation to SaveToFile.

interface

uses
  System.Diagnostics, System.Generics.Collections, System.SysUtils;

type
  ENUnitLogger = class(Exception);

  // ntrError is written as a failure with label="Error" (unexpected exception instead of a failed check)
  TNUnitTestResult = (ntrPassed, ntrFailed, ntrError, ntrSkipped, ntrInconclusive, ntrWarning);

  // The time attributes and the environment element are optional in NUnit 3 result files, leaving them out makes large
  // files smaller. Consumers show missing durations as zero.
  TNUnitLogOption = (
    nuloLogTimes,    // start-time and end-time attributes
    nuloDurations,   // duration attributes
    nuloEnvironment, // environment element of the Assembly test suite
    nuloIndent       // indentation of nested elements, without it each element is still written on its own line
  );
  TNUnitLogOptions = set of TNUnitLogOption;

const
  NUNIT_LOG_DEFAULT_OPTIONS = [nuloLogTimes, nuloDurations, nuloEnvironment, nuloIndent];

type
  // Common part of test cases and test suites
  TNUnitTimedItem = class(TObject)
  strict private
    FAddTime: TDateTime;
    FDuration: Double;
    FEndTime: TDateTime;
    FName: string;
    FStartTime: TDateTime;
    FStopwatch: TStopwatch;
  strict protected
    function KindText: string; virtual; abstract;
    procedure BeginTiming;
    procedure EndTiming;
  public
    constructor Create(const AName: string);

    // Begun but not ended
    function IsRunning: Boolean;

    // Time when the item was created
    property AddTime: TDateTime read FAddTime;
    // Seconds between begin and end, measured with TStopwatch. 0.0 until ended.
    property Duration: Double read FDuration;
    // 0.0 until ended
    property EndTime: TDateTime read FEndTime;
    property Name: string read FName;
    // 0.0 until begun
    property StartTime: TDateTime read FStartTime;
  end;

  TNUnitTestCase = class(TNUnitTimedItem)
  strict private
    FAsserts: Integer;
    FMessage: string;
    FStackTrace: string;
    FTestResult: TNUnitTestResult;
  strict protected
    function KindText: string; override;
  public
    constructor Create(const AName: string; const ATestResult: TNUnitTestResult; const AMessage, AStackTrace: string;
      const AAsserts: Integer);

    // Both raise ENUnitLogger if called in the wrong order or more than once
    procedure BeginTestCase;
    procedure EndTestCase;

    property Asserts: Integer read FAsserts write FAsserts;
    // Written only if not empty. Failed and errored test cases: failure message, passed and warning ones: output,
    // skipped and inconclusive ones: reason message
    property Message: string read FMessage write FMessage;
    // Written only for failed and errored test cases
    property StackTrace: string read FStackTrace write FStackTrace;
    property TestResult: TNUnitTestResult read FTestResult write FTestResult;
  end;

  TNUnitTestSuite = class(TNUnitTimedItem)
  strict private
    FTestCases: TObjectList<TNUnitTestCase>;
  strict protected
    function KindText: string; override;
  public
    constructor Create(const AName: string);
    destructor Destroy; override;

    // AStartTestCase calls BeginTestCase of the added test case
    function AddTestCase(const AName: string; const ATestResult: TNUnitTestResult; const AMessage: string = '';
      const AStackTrace: string = ''; const AAsserts: Integer = 0; const AStartTestCase: Boolean = True): TNUnitTestCase;
    // Both raise ENUnitLogger if called in the wrong order or more than once
    procedure BeginTestSuite;
    procedure EndTestSuite;

    property TestCases: TObjectList<TNUnitTestCase> read FTestCases;
  end;

  TNUnitLogger = class(TObject)
  strict private
    FCommandLine: string;
    FFullName: string;
    FName: string;
    FOptions: TNUnitLogOptions;
    FStartTime: TDateTime;
    FStopwatch: TStopwatch;
    FTestSuites: TObjectList<TNUnitTestSuite>;
    function GetDuration: Double;
    procedure CheckEverythingEnded;
  public
    constructor Create(const AOptions: TNUnitLogOptions = NUNIT_LOG_DEFAULT_OPTIONS);
    destructor Destroy; override;

    // AStartTestSuite calls BeginTestSuite of the added test suite
    function AddTestSuite(const AName: string; const AStartTestSuite: Boolean = True): TNUnitTestSuite;
    // Raises ENUnitLogger if a test suite or a test case has begun but not ended
    procedure SaveToFile(const AFileName: string; const AAllowOverWrite: Boolean = False);

    // CommandLine, FullName and Name default to the running executable
    property CommandLine: string read FCommandLine write FCommandLine;
    // Seconds since the logger was created, measured with TStopwatch
    property Duration: Double read GetDuration;
    property FullName: string read FFullName write FFullName;
    property Name: string read FName write FName;
    property Options: TNUnitLogOptions read FOptions write FOptions;
    property StartTime: TDateTime read FStartTime;
    property TestSuites: TObjectList<TNUnitTestSuite> read FTestSuites;
  end;

implementation

uses
  System.Classes;

const
  DURATION_FORMAT = '0.000000';
  ENGINE_VERSION = '3.0';
  INDENT = '  ';
  TEST_RESULT_TEXTS: array[TNUnitTestResult] of string = ('Passed', 'Failed', 'Failed', 'Skipped', 'Inconclusive', 'Warning');
  TEST_RUN_ID = '2';

type
  TNUnitSummary = record
    Asserts: Integer;
    Failed: Integer;
    Inconclusive: Integer;
    Passed: Integer;
    Skipped: Integer;
    Total: Integer;
    Warnings: Integer;
    function CountAttributes(const AIsTestSuite: Boolean = True): string;
    function ResultText: string;
    procedure Add(const ASummary: TNUnitSummary); overload;
    procedure Add(const ATestCase: TNUnitTestCase); overload;
  end;

  TNUnitTimes = record
    Duration: Double;
    EndTime: TDateTime;
    StartTime: TDateTime;
    procedure Include(const ATimes: TNUnitTimes);
    procedure Init(const AStartTime, AEndTime: TDateTime; const ADuration: Double);
  end;

  TNUnitXmlWriter = class(TObject)
  strict private
    FBuilder: TStringBuilder;
    FLastId: Integer;
    FOptions: TNUnitLogOptions;
    function NextId: string;
    function TimeAttributes(const ATimes: TNUnitTimes): string;
    procedure WriteChildFailure(const AIndentLevel: Integer; const ASummary: TNUnitSummary);
    procedure WriteEnvironment(const AIndentLevel: Integer);
    procedure WriteLine(const AIndentLevel: Integer; const AText: string);
    procedure WriteTestCase(const ATestCase: TNUnitTestCase; const AClassName: string);
    procedure WriteTestSuite(const ATestSuite: TNUnitTestSuite; const ASummary: TNUnitSummary; const ATimes: TNUnitTimes;
      const AFullName: string);
  public
    constructor Create;
    destructor Destroy; override;

    function Build(const ALogger: TNUnitLogger): string;
  end;

function DateTimeText(const ADateTime: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss', ADateTime);
end;

// XML 1.0 does not allow most control characters at all, not even as character references
function IsInvalidXmlChar(const AChar: Char): Boolean;
begin
  Result := ((AChar < #32) and not CharInSet(AChar, [#9, #10, #13])) or (AChar = #$FFFE) or (AChar = #$FFFF);
end;

function ReplaceInvalidXmlChars(const AText: string): string;
var
  LIndex: Integer;
begin
  Result := AText;

  for LIndex := 1 to Length(Result) do
    if IsInvalidXmlChar(Result[LIndex]) then
      Result[LIndex] := '?';
end;

function TestCaseTimes(const ATestCase: TNUnitTestCase): TNUnitTimes;
begin
  if ATestCase.StartTime = 0.0 then
    Result.Init(ATestCase.AddTime, ATestCase.AddTime, 0.0)
  else
    Result.Init(ATestCase.StartTime, ATestCase.EndTime, ATestCase.Duration);
end;

function TestSuiteTimes(const ATestSuite: TNUnitTestSuite): TNUnitTimes;
var
  LIndex: Integer;
begin
  if ATestSuite.StartTime <> 0.0 then
    Result.Init(ATestSuite.StartTime, ATestSuite.EndTime, ATestSuite.Duration)
  else if ATestSuite.TestCases.Count = 0 then
    Result.Init(ATestSuite.AddTime, ATestSuite.AddTime, 0.0)
  else
  begin
    Result := TestCaseTimes(ATestSuite.TestCases[0]);

    for LIndex := 1 to ATestSuite.TestCases.Count - 1 do
      Result.Include(TestCaseTimes(ATestSuite.TestCases[LIndex]));
  end;
end;

function XmlCData(const AText: string): string;
begin
  // "]]>" would end the CDATA section, so it is split into two sections
  Result := '<![CDATA[' + ReplaceInvalidXmlChars(AText).Replace(']]>', ']]]]><![CDATA[>', [rfReplaceAll]) + ']]>';
end;

function XmlEscape(const AText: string): string;
var
  LBuilder: TStringBuilder;
  LChar: Char;
begin
  LBuilder := TStringBuilder.Create(Length(AText));
  try
    for LChar in AText do
      case LChar of
        '"': LBuilder.Append('&quot;');
        '&': LBuilder.Append('&amp;');
        '<': LBuilder.Append('&lt;');
        '>': LBuilder.Append('&gt;');
        #9: LBuilder.Append('&#x9;');
        #10: LBuilder.Append('&#xA;');
        #13: LBuilder.Append('&#xD;');
      else
        if IsInvalidXmlChar(LChar) then
          LBuilder.Append('?')
        else
          LBuilder.Append(LChar);
      end;

    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

{ TNUnitSummary }

function TNUnitSummary.CountAttributes(const AIsTestSuite: Boolean = True): string;
var
  LSite: string;
begin
  // Like NUnit, a failed test suite tells that the failure came from its children
  if AIsTestSuite and (Failed > 0) then
    LSite := ' site="Child"'
  else
    LSite := '';

  Result := Format(' testcasecount="%d" result="%s"%s total="%d" passed="%d" failed="%d" warnings="%d" inconclusive="%d" skipped="%d" asserts="%d"',
    [Total, ResultText, LSite, Total, Passed, Failed, Warnings, Inconclusive, Skipped, Asserts]);
end;

// Same order as NUnit: any failure fails the suite, skipped or inconclusive only when nothing else ran
function TNUnitSummary.ResultText: string;
begin
  if Failed > 0 then
    Result := 'Failed'
  else if Warnings > 0 then
    Result := 'Warning'
  else if (Passed > 0) or (Total = 0) then
    Result := 'Passed'
  else if Inconclusive > 0 then
    Result := 'Inconclusive'
  else
    Result := 'Skipped';
end;

procedure TNUnitSummary.Add(const ASummary: TNUnitSummary);
begin
  Inc(Asserts, ASummary.Asserts);
  Inc(Failed, ASummary.Failed);
  Inc(Inconclusive, ASummary.Inconclusive);
  Inc(Passed, ASummary.Passed);
  Inc(Skipped, ASummary.Skipped);
  Inc(Total, ASummary.Total);
  Inc(Warnings, ASummary.Warnings);
end;

procedure TNUnitSummary.Add(const ATestCase: TNUnitTestCase);
begin
  Inc(Asserts, ATestCase.Asserts);
  Inc(Total);

  case ATestCase.TestResult of
    ntrPassed: Inc(Passed);
    ntrFailed, ntrError: Inc(Failed);
    ntrSkipped: Inc(Skipped);
    ntrInconclusive: Inc(Inconclusive);
    ntrWarning: Inc(Warnings);
  end;
end;

{ TNUnitTimes }

// The duration becomes the time between the start and the end, so it is only as accurate as Now
procedure TNUnitTimes.Include(const ATimes: TNUnitTimes);
begin
  if ATimes.StartTime < StartTime then
    StartTime := ATimes.StartTime;

  if ATimes.EndTime > EndTime then
    EndTime := ATimes.EndTime;

  Duration := (EndTime - StartTime) * SecsPerDay;
end;

procedure TNUnitTimes.Init(const AStartTime, AEndTime: TDateTime; const ADuration: Double);
begin
  StartTime := AStartTime;
  EndTime := AEndTime;
  Duration := ADuration;
end;

{ TNUnitXmlWriter }

constructor TNUnitXmlWriter.Create;
begin
  inherited Create;

  FBuilder := TStringBuilder.Create;
end;

destructor TNUnitXmlWriter.Destroy;
begin
  FBuilder.Free;

  inherited Destroy;
end;

function TNUnitXmlWriter.Build(const ALogger: TNUnitLogger): string;
var
  LIndex: Integer;
  LName: string;
  LRunSummary: TNUnitSummary;
  LRunTimes: TNUnitTimes;
  LSuiteSummaries: TArray<TNUnitSummary>;
  LTestCase: TNUnitTestCase;
  LTestSuite: TNUnitTestSuite;
begin
  FBuilder.Clear;
  FLastId := 0;
  FOptions := ALogger.Options;

  // Counts go into the start tags, so they are calculated before writing anything
  LRunTimes.Init(ALogger.StartTime, Now, ALogger.Duration);
  LRunSummary := Default(TNUnitSummary);
  SetLength(LSuiteSummaries, ALogger.TestSuites.Count);

  for LIndex := 0 to ALogger.TestSuites.Count - 1 do
  begin
    LSuiteSummaries[LIndex] := Default(TNUnitSummary);

    for LTestCase in ALogger.TestSuites[LIndex].TestCases do
      LSuiteSummaries[LIndex].Add(LTestCase);

    LRunSummary.Add(LSuiteSummaries[LIndex]);
  end;

  LName := XmlEscape(ALogger.Name);

  WriteLine(0, '<?xml version="1.0" encoding="utf-8"?>');
  WriteLine(0, Format('<test-run id="%s" name="%s" fullname="%s"%s engine-version="%s"%s>', [TEST_RUN_ID, LName, LName,
    LRunSummary.CountAttributes(False), ENGINE_VERSION, TimeAttributes(LRunTimes)]));
  WriteLine(1, '<command-line>' + XmlEscape(ALogger.CommandLine) + '</command-line>');
  WriteLine(1, Format('<test-suite type="Assembly" id="%s" name="%s" fullname="%s" runstate="Runnable"%s%s>', [NextId, LName,
    XmlEscape(ALogger.FullName), LRunSummary.CountAttributes, TimeAttributes(LRunTimes)]));
  WriteEnvironment(2);
  WriteChildFailure(2, LRunSummary);

  for LIndex := 0 to ALogger.TestSuites.Count - 1 do
  begin
    LTestSuite := ALogger.TestSuites[LIndex];

    WriteTestSuite(LTestSuite, LSuiteSummaries[LIndex], TestSuiteTimes(LTestSuite), ALogger.Name + '.' + LTestSuite.Name);
  end;

  WriteLine(1, '</test-suite>');
  WriteLine(0, '</test-run>');

  Result := FBuilder.ToString;
end;

function TNUnitXmlWriter.NextId: string;
begin
  Inc(FLastId);

  Result := '0-' + FLastId.ToString;
end;

function TNUnitXmlWriter.TimeAttributes(const ATimes: TNUnitTimes): string;
begin
  Result := '';

  if nuloLogTimes in FOptions then
    Result := Format(' start-time="%s" end-time="%s"', [DateTimeText(ATimes.StartTime), DateTimeText(ATimes.EndTime)]);

  if nuloDurations in FOptions then
    Result := Result + ' duration="' + FormatFloat(DURATION_FORMAT, ATimes.Duration, TFormatSettings.Invariant) + '"';
end;

procedure TNUnitXmlWriter.WriteChildFailure(const AIndentLevel: Integer; const ASummary: TNUnitSummary);
begin
  if ASummary.Failed = 0 then
    Exit;

  WriteLine(AIndentLevel, '<failure>');
  WriteLine(AIndentLevel + 1, '<message>' + XmlCData('One or more child tests had errors') + '</message>');
  WriteLine(AIndentLevel, '</failure>');
end;

procedure TNUnitXmlWriter.WriteEnvironment(const AIndentLevel: Integer);
begin
  if not (nuloEnvironment in FOptions) then
    Exit;

  WriteLine(AIndentLevel, Format('<environment os-version="%s" cwd="%s" machine-name="%s" user="%s" user-domain="%s" />', [
    XmlEscape(TOSVersion.ToString), XmlEscape(GetCurrentDir), XmlEscape(GetEnvironmentVariable('COMPUTERNAME')),
    XmlEscape(GetEnvironmentVariable('USERNAME')), XmlEscape(GetEnvironmentVariable('USERDOMAIN'))]));
end;

procedure TNUnitXmlWriter.WriteLine(const AIndentLevel: Integer; const AText: string);
var
  LIndex: Integer;
begin
  if nuloIndent in FOptions then
    for LIndex := 1 to AIndentLevel do
      FBuilder.Append(INDENT);

  FBuilder.AppendLine(AText);
end;

procedure TNUnitXmlWriter.WriteTestCase(const ATestCase: TNUnitTestCase; const AClassName: string);
var
  LLabel: string;
  LName: string;
  LStartTag: string;
begin
  LName := XmlEscape(ATestCase.Name);

  if ATestCase.TestResult = ntrError then
    LLabel := ' label="Error"'
  else
    LLabel := '';

  LStartTag := Format('<test-case id="%s" name="%s" fullname="%s.%s" methodname="%s" classname="%s" runstate="Runnable" result="%s"%s%s asserts="%d"',
    [NextId, LName, AClassName, LName, LName, AClassName, TEST_RESULT_TEXTS[ATestCase.TestResult], LLabel,
    TimeAttributes(TestCaseTimes(ATestCase)), ATestCase.Asserts]);

  if ATestCase.TestResult in [ntrFailed, ntrError] then
  begin
    WriteLine(3, LStartTag + '>');
    WriteLine(4, '<failure>');
    WriteLine(5, '<message>' + XmlCData(ATestCase.Message) + '</message>');

    if not ATestCase.StackTrace.IsEmpty then
      WriteLine(5, '<stack-trace>' + XmlCData(ATestCase.StackTrace) + '</stack-trace>');

    WriteLine(4, '</failure>');
    WriteLine(3, '</test-case>');
  end
  else if ATestCase.Message.IsEmpty then
    WriteLine(3, LStartTag + ' />')
  else if ATestCase.TestResult in [ntrPassed, ntrWarning] then
  begin
    // The test case ran, so its message is output, not a reason: reason is for test cases that did not run, and some
    // consumers show every test case with a reason as skipped, whatever its result
    WriteLine(3, LStartTag + '>');
    WriteLine(4, '<output>' + XmlCData(ATestCase.Message) + '</output>');
    WriteLine(3, '</test-case>');
  end
  else
  begin
    WriteLine(3, LStartTag + '>');
    WriteLine(4, '<reason>');
    WriteLine(5, '<message>' + XmlCData(ATestCase.Message) + '</message>');
    WriteLine(4, '</reason>');
    WriteLine(3, '</test-case>');
  end;
end;

procedure TNUnitXmlWriter.WriteTestSuite(const ATestSuite: TNUnitTestSuite; const ASummary: TNUnitSummary;
  const ATimes: TNUnitTimes; const AFullName: string);
var
  LFullName: string;
  LTestCase: TNUnitTestCase;
begin
  LFullName := XmlEscape(AFullName);

  WriteLine(2, Format('<test-suite type="TestFixture" id="%s" name="%s" fullname="%s" classname="%s" runstate="Runnable"%s%s>',
    [NextId, XmlEscape(ATestSuite.Name), LFullName, LFullName, ASummary.CountAttributes, TimeAttributes(ATimes)]));
  WriteChildFailure(3, ASummary);

  for LTestCase in ATestSuite.TestCases do
    WriteTestCase(LTestCase, LFullName);

  WriteLine(2, '</test-suite>');
end;

{ TNUnitTimedItem }

constructor TNUnitTimedItem.Create(const AName: string);
begin
  inherited Create;

  FName := AName;
  FAddTime := Now;
end;

procedure TNUnitTimedItem.BeginTiming;
begin
  if FStartTime <> 0.0 then
    raise ENUnitLogger.CreateFmt('%s "%s" has already begun', [KindText, FName]);

  FStartTime := Now;
  FStopwatch := TStopwatch.StartNew;
end;

procedure TNUnitTimedItem.EndTiming;
begin
  if FStartTime = 0.0 then
    raise ENUnitLogger.CreateFmt('%s "%s" has not begun', [KindText, FName]);

  if FEndTime <> 0.0 then
    raise ENUnitLogger.CreateFmt('%s "%s" has already ended', [KindText, FName]);

  FStopwatch.Stop;
  FDuration := FStopwatch.Elapsed.TotalSeconds;
  FEndTime := Now;
end;

function TNUnitTimedItem.IsRunning: Boolean;
begin
  Result := (FStartTime <> 0.0) and (FEndTime = 0.0);
end;

{ TNUnitTestCase }

constructor TNUnitTestCase.Create(const AName: string; const ATestResult: TNUnitTestResult; const AMessage,
  AStackTrace: string; const AAsserts: Integer);
begin
  inherited Create(AName);

  FTestResult := ATestResult;
  FMessage := AMessage;
  FStackTrace := AStackTrace;
  FAsserts := AAsserts;
end;

function TNUnitTestCase.KindText: string;
begin
  Result := 'Test case';
end;

procedure TNUnitTestCase.BeginTestCase;
begin
  BeginTiming;
end;

procedure TNUnitTestCase.EndTestCase;
begin
  EndTiming;
end;

{ TNUnitTestSuite }

constructor TNUnitTestSuite.Create(const AName: string);
begin
  inherited Create(AName);

  FTestCases := TObjectList<TNUnitTestCase>.Create;
end;

destructor TNUnitTestSuite.Destroy;
begin
  FTestCases.Free;

  inherited Destroy;
end;

function TNUnitTestSuite.KindText: string;
begin
  Result := 'Test suite';
end;

function TNUnitTestSuite.AddTestCase(const AName: string; const ATestResult: TNUnitTestResult; const AMessage: string = '';
  const AStackTrace: string = ''; const AAsserts: Integer = 0; const AStartTestCase: Boolean = True): TNUnitTestCase;
begin
  Result := TNUnitTestCase.Create(AName, ATestResult, AMessage, AStackTrace, AAsserts);

  FTestCases.Add(Result);

  if AStartTestCase then
    Result.BeginTestCase;
end;

procedure TNUnitTestSuite.BeginTestSuite;
begin
  BeginTiming;
end;

procedure TNUnitTestSuite.EndTestSuite;
begin
  EndTiming;
end;

{ TNUnitLogger }

constructor TNUnitLogger.Create(const AOptions: TNUnitLogOptions = NUNIT_LOG_DEFAULT_OPTIONS);
begin
  inherited Create;

  FOptions := AOptions;
  FTestSuites := TObjectList<TNUnitTestSuite>.Create;
  FStartTime := Now;
  FStopwatch := TStopwatch.StartNew;
  FFullName := ParamStr(0);
  FName := ChangeFileExt(ExtractFileName(FFullName), '');
  {$WARN SYMBOL_PLATFORM OFF}
  FCommandLine := string(CmdLine);
  {$WARN SYMBOL_PLATFORM ON}
end;

destructor TNUnitLogger.Destroy;
begin
  FTestSuites.Free;

  inherited Destroy;
end;

function TNUnitLogger.AddTestSuite(const AName: string; const AStartTestSuite: Boolean = True): TNUnitTestSuite;
begin
  Result := TNUnitTestSuite.Create(AName);

  FTestSuites.Add(Result);

  if AStartTestSuite then
    Result.BeginTestSuite;
end;

// Forgetting an End* call is a programming error, so it is not written as if it had ended at SaveToFile
procedure TNUnitLogger.CheckEverythingEnded;
var
  LTestCase: TNUnitTestCase;
  LTestSuite: TNUnitTestSuite;
begin
  for LTestSuite in FTestSuites do
  begin
    if LTestSuite.IsRunning then
      raise ENUnitLogger.CreateFmt('Test suite "%s" has begun but not ended, call EndTestSuite before SaveToFile',
        [LTestSuite.Name]);

    for LTestCase in LTestSuite.TestCases do
      if LTestCase.IsRunning then
        raise ENUnitLogger.CreateFmt('Test case "%s" of test suite "%s" has begun but not ended, call EndTestCase before SaveToFile',
          [LTestCase.Name, LTestSuite.Name]);
  end;
end;

function TNUnitLogger.GetDuration: Double;
begin
  Result := FStopwatch.Elapsed.TotalSeconds;
end;

procedure TNUnitLogger.SaveToFile(const AFileName: string; const AAllowOverWrite: Boolean = False);
var
  LBytes: TBytes;
  LFileStream: TFileStream;
  LXmlWriter: TNUnitXmlWriter;
begin
  if FileExists(AFileName) and not AAllowOverWrite then
    raise ENUnitLogger.CreateFmt('File "%s" already exists and overwriting is not allowed', [AFileName]);

  CheckEverythingEnded;

  LXmlWriter := TNUnitXmlWriter.Create;
  try
    // UTF8.GetBytes does not add the BOM
    LBytes := TEncoding.UTF8.GetBytes(LXmlWriter.Build(Self));
  finally
    LXmlWriter.Free;
  end;

  if FileExists(AFileName) and not DeleteFile(AFileName) then
    raise ENUnitLogger.CreateFmt('Could not delete existing file "%s": %s', [AFileName, SysErrorMessage(GetLastError)]);

  ForceDirectories(ExtractFileDir(ExpandFileName(AFileName)));

  LFileStream := TFileStream.Create(AFileName, fmCreate);
  try
    LFileStream.WriteBuffer(LBytes, Length(LBytes));
  finally
    LFileStream.Free;
  end;
end;

end.
