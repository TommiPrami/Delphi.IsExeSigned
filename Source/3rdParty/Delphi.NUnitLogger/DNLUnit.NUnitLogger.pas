unit DNLUnit.NUnitLogger;

// Very simple NUnit 3 XML result file writer. No XML library is used, the file is written as plain text.
//
//   LLogger := TNUnitLogger.Create;
//   try
//     LTestSuite := LLogger.AddTestSuite('DisallowedList');
//     LTestSuite.AddTestCase('Unit1.pas', ntrPassed);
//     LTestSuite.AddTestCase('Unit2.pas', ntrPassed, LStopwatch.Elapsed.TotalSeconds);
//     LTestSuite.AddTestCase('Unit3.pas', ntrFailed, 0.0, 'Disallowed identifier found');
//
//     LLogger.SaveToFile('TestResults.xml', True);
//   finally
//     LLogger.Free;
//   end;
//
// Written structure: test-run > test-suite (Assembly, added automatically, with environment) > test-suite (TestFixture)
// > test-case
//
// Times: a test case ends when it is added and starts ADuration seconds (default 0.0) before that. A test suite runs
// from its creation to the end of its last test case, the test run from the logger creation to SaveToFile.

interface

uses
  System.Generics.Collections, System.SysUtils;

type
  ENUnitLogger = class(Exception);

  // ntrError is written as a failure with label="Error" (unexpected exception instead of a failed check)
  TNUnitTestResult = (ntrPassed, ntrFailed, ntrError, ntrSkipped, ntrInconclusive, ntrWarning);

  TNUnitTestCase = class(TObject)
  strict private
    FAsserts: Integer;
    FEndTime: TDateTime;
    FMessage: string;
    FName: string;
    FStackTrace: string;
    FStartTime: TDateTime;
    FTestResult: TNUnitTestResult;
  public
    constructor Create(const AName: string; const ATestResult: TNUnitTestResult; const ADuration: Double; const AMessage,
      AStackTrace: string; const AAsserts: Integer);

    property Asserts: Integer read FAsserts write FAsserts;
    property EndTime: TDateTime read FEndTime write FEndTime;
    // Failed and errored test cases: failure message, others: reason message (written only if not empty)
    property Message: string read FMessage write FMessage;
    property Name: string read FName;
    // Written only for failed and errored test cases
    property StackTrace: string read FStackTrace write FStackTrace;
    property StartTime: TDateTime read FStartTime write FStartTime;
    property TestResult: TNUnitTestResult read FTestResult write FTestResult;
  end;

  TNUnitTestSuite = class(TObject)
  strict private
    FName: string;
    FStartTime: TDateTime;
    FTestCases: TObjectList<TNUnitTestCase>;
  public
    constructor Create(const AName: string);
    destructor Destroy; override;

    // ADuration is in seconds
    function AddTestCase(const AName: string; const ATestResult: TNUnitTestResult; const ADuration: Double = 0.0;
      const AMessage: string = ''; const AStackTrace: string = ''; const AAsserts: Integer = 0): TNUnitTestCase;

    property Name: string read FName;
    property StartTime: TDateTime read FStartTime;
    property TestCases: TObjectList<TNUnitTestCase> read FTestCases;
  end;

  TNUnitLogger = class(TObject)
  strict private
    FCommandLine: string;
    FFullName: string;
    FName: string;
    FStartTime: TDateTime;
    FTestSuites: TObjectList<TNUnitTestSuite>;
  public
    constructor Create;
    destructor Destroy; override;

    function AddTestSuite(const AName: string): TNUnitTestSuite;
    procedure SaveToFile(const AFileName: string; const AAllowOverWrite: Boolean = False);

    // CommandLine, FullName and Name default to the running executable
    property CommandLine: string read FCommandLine write FCommandLine;
    property FullName: string read FFullName write FFullName;
    property Name: string read FName write FName;
    property StartTime: TDateTime read FStartTime;
    property TestSuites: TObjectList<TNUnitTestSuite> read FTestSuites;
  end;

implementation

uses
  System.Classes;

const
  ENGINE_VERSION = '3.0';
  INDENT = '  ';
  TEST_RESULT_TEXTS: array[TNUnitTestResult] of string = ('Passed', 'Failed', 'Failed', 'Skipped', 'Inconclusive', 'Warning');
  TEST_RUN_ID = '2';

type
  TNUnitSummary = record
    Asserts: Integer;
    EndTime: TDateTime;
    Failed: Integer;
    Inconclusive: Integer;
    Passed: Integer;
    Skipped: Integer;
    StartTime: TDateTime;
    Total: Integer;
    Warnings: Integer;
    function CountAttributes(const AIsTestSuite: Boolean = True): string;
    function ResultText: string;
    procedure Add(const ASummary: TNUnitSummary); overload;
    procedure Add(const ATestCase: TNUnitTestCase); overload;
    procedure IncludeTimes(const AStartTime, AEndTime: TDateTime);
    procedure Init(const AStartTime, AEndTime: TDateTime);
  end;

  TNUnitXmlWriter = class(TObject)
  strict private
    FBuilder: TStringBuilder;
    FLastId: Integer;
    function NextId: string;
    procedure WriteChildFailure(const AIndentLevel: Integer; const ASummary: TNUnitSummary);
    procedure WriteEnvironment(const AIndentLevel: Integer);
    procedure WriteLine(const AIndentLevel: Integer; const AText: string);
    procedure WriteTestCase(const ATestCase: TNUnitTestCase; const AClassName: string);
    procedure WriteTestSuite(const ATestSuite: TNUnitTestSuite; const ASummary: TNUnitSummary; const AFullName: string);
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

function TimeAttributes(const AStartTime, AEndTime: TDateTime): string;
begin
  Result := Format(' start-time="%s" end-time="%s" duration="%s"', [DateTimeText(AStartTime), DateTimeText(AEndTime),
    FormatFloat('0.000', (AEndTime - AStartTime) * SecsPerDay, TFormatSettings.Invariant)]);
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

  IncludeTimes(ASummary.StartTime, ASummary.EndTime);
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

  IncludeTimes(ATestCase.StartTime, ATestCase.EndTime);
end;

procedure TNUnitSummary.IncludeTimes(const AStartTime, AEndTime: TDateTime);
begin
  if AStartTime < StartTime then
    StartTime := AStartTime;

  if AEndTime > EndTime then
    EndTime := AEndTime;
end;

procedure TNUnitSummary.Init(const AStartTime, AEndTime: TDateTime);
begin
  Self := Default(TNUnitSummary);

  StartTime := AStartTime;
  EndTime := AEndTime;
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
  LSuiteSummaries: TArray<TNUnitSummary>;
  LTestCase: TNUnitTestCase;
  LTestSuite: TNUnitTestSuite;
begin
  FBuilder.Clear;
  FLastId := 0;

  // Counts and times go into the start tags, so they are calculated before writing anything
  LRunSummary.Init(ALogger.StartTime, Now);
  SetLength(LSuiteSummaries, ALogger.TestSuites.Count);

  for LIndex := 0 to ALogger.TestSuites.Count - 1 do
  begin
    LTestSuite := ALogger.TestSuites[LIndex];
    LSuiteSummaries[LIndex].Init(LTestSuite.StartTime, LTestSuite.StartTime);

    for LTestCase in LTestSuite.TestCases do
      LSuiteSummaries[LIndex].Add(LTestCase);

    LRunSummary.Add(LSuiteSummaries[LIndex]);
  end;

  LName := XmlEscape(ALogger.Name);

  WriteLine(0, '<?xml version="1.0" encoding="utf-8"?>');
  WriteLine(0, Format('<test-run id="%s" name="%s" fullname="%s"%s engine-version="%s"%s>', [TEST_RUN_ID, LName, LName,
    LRunSummary.CountAttributes(False), ENGINE_VERSION, TimeAttributes(LRunSummary.StartTime, LRunSummary.EndTime)]));
  WriteLine(1, '<command-line>' + XmlEscape(ALogger.CommandLine) + '</command-line>');
  WriteLine(1, Format('<test-suite type="Assembly" id="%s" name="%s" fullname="%s" runstate="Runnable"%s%s>', [NextId, LName,
    XmlEscape(ALogger.FullName), LRunSummary.CountAttributes, TimeAttributes(LRunSummary.StartTime, LRunSummary.EndTime)]));
  WriteEnvironment(2);
  WriteChildFailure(2, LRunSummary);

  for LIndex := 0 to ALogger.TestSuites.Count - 1 do
  begin
    LTestSuite := ALogger.TestSuites[LIndex];

    WriteTestSuite(LTestSuite, LSuiteSummaries[LIndex], ALogger.Name + '.' + LTestSuite.Name);
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
  WriteLine(AIndentLevel, Format('<environment os-version="%s" cwd="%s" machine-name="%s" user="%s" user-domain="%s" />', [
    XmlEscape(TOSVersion.ToString), XmlEscape(GetCurrentDir), XmlEscape(GetEnvironmentVariable('COMPUTERNAME')),
    XmlEscape(GetEnvironmentVariable('USERNAME')), XmlEscape(GetEnvironmentVariable('USERDOMAIN'))]));
end;

procedure TNUnitXmlWriter.WriteLine(const AIndentLevel: Integer; const AText: string);
var
  LIndex: Integer;
begin
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
    TimeAttributes(ATestCase.StartTime, ATestCase.EndTime), ATestCase.Asserts]);

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
  else if not ATestCase.Message.IsEmpty then
  begin
    WriteLine(3, LStartTag + '>');
    WriteLine(4, '<reason>');
    WriteLine(5, '<message>' + XmlCData(ATestCase.Message) + '</message>');
    WriteLine(4, '</reason>');
    WriteLine(3, '</test-case>');
  end
  else
    WriteLine(3, LStartTag + ' />');
end;

procedure TNUnitXmlWriter.WriteTestSuite(const ATestSuite: TNUnitTestSuite; const ASummary: TNUnitSummary;
  const AFullName: string);
var
  LFullName: string;
  LTestCase: TNUnitTestCase;
begin
  LFullName := XmlEscape(AFullName);

  WriteLine(2, Format('<test-suite type="TestFixture" id="%s" name="%s" fullname="%s" classname="%s" runstate="Runnable"%s%s>',
    [NextId, XmlEscape(ATestSuite.Name), LFullName, LFullName, ASummary.CountAttributes,
    TimeAttributes(ASummary.StartTime, ASummary.EndTime)]));
  WriteChildFailure(3, ASummary);

  for LTestCase in ATestSuite.TestCases do
    WriteTestCase(LTestCase, LFullName);

  WriteLine(2, '</test-suite>');
end;

{ TNUnitTestCase }

constructor TNUnitTestCase.Create(const AName: string; const ATestResult: TNUnitTestResult; const ADuration: Double;
  const AMessage, AStackTrace: string; const AAsserts: Integer);
begin
  inherited Create;

  FName := AName;
  FTestResult := ATestResult;
  FMessage := AMessage;
  FStackTrace := AStackTrace;
  FAsserts := AAsserts;
  FEndTime := Now;
  FStartTime := FEndTime - ADuration / SecsPerDay;
end;

{ TNUnitTestSuite }

constructor TNUnitTestSuite.Create(const AName: string);
begin
  inherited Create;

  FName := AName;
  FTestCases := TObjectList<TNUnitTestCase>.Create;
  FStartTime := Now;
end;

destructor TNUnitTestSuite.Destroy;
begin
  FTestCases.Free;

  inherited Destroy;
end;

function TNUnitTestSuite.AddTestCase(const AName: string; const ATestResult: TNUnitTestResult; const ADuration: Double = 0.0;
  const AMessage: string = ''; const AStackTrace: string = ''; const AAsserts: Integer = 0): TNUnitTestCase;
begin
  Result := TNUnitTestCase.Create(AName, ATestResult, ADuration, AMessage, AStackTrace, AAsserts);

  FTestCases.Add(Result);
end;

{ TNUnitLogger }

constructor TNUnitLogger.Create;
begin
  inherited Create;

  FTestSuites := TObjectList<TNUnitTestSuite>.Create;
  FStartTime := Now;
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

function TNUnitLogger.AddTestSuite(const AName: string): TNUnitTestSuite;
begin
  Result := TNUnitTestSuite.Create(AName);

  FTestSuites.Add(Result);
end;

procedure TNUnitLogger.SaveToFile(const AFileName: string; const AAllowOverWrite: Boolean = False);
var
  LBytes: TBytes;
  LFileStream: TFileStream;
  LXmlWriter: TNUnitXmlWriter;
begin
  if FileExists(AFileName) and not AAllowOverWrite then
    raise ENUnitLogger.CreateFmt('File "%s" already exists and overwriting is not allowed', [AFileName]);

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
