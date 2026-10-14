unit DNLUnit.NUnitLogger.Tests;

// The written file is loaded with MSXML, so every test also checks that the file is well-formed XML.

interface

uses
  DUnitX.TestFramework, Winapi.msxml, DNLUnit.NUnitLogger;

type
  [TestFixture]
  TNUnitLoggerTests = class(TObject)
  strict private
    FDirectory: string;
    FDocument: IXMLDOMDocument2;
    FFileName: string;
    function NodeCount(const AXPath: string): Integer;
    function Value(const AXPath: string): string;
    procedure CheckCounts(const AXPath: string; const ATotal, APassed, AFailed, AWarnings, AInconclusive, ASkipped,
      AAsserts: Integer);
    procedure LoadResultFile;
    procedure SaveAndLoad(const ALogger: TNUnitLogger);
    procedure WriteOldFile;
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure EmptyLoggerWritesRunAndAssemblySuite;
    [Test] procedure DefaultNamesComeFromExecutable;
    [Test] procedure CustomNamesAreWritten;
    [Test] procedure CountsAreSummedToSuitesAndRun;
    [Test] procedure TestCaseResultsAreWritten;
    [Test] procedure SuiteResultFollowsNUnitRules;
    [Test] procedure FailedSuitesGetChildFailure;
    [Test] procedure FailureHasMessageAndStackTrace;
    [Test] procedure ReasonIsWrittenOnlyWithMessage;
    [Test] procedure SpecialCharactersRoundTrip;
    [Test] procedure InvalidXmlCharactersAreReplaced;
    [Test] procedure FileIsUtf8WithoutBomAndIndented;
    [Test] procedure DurationAndAssertsAreWritten;
    [Test] procedure TimesIgnoreFormatSettings;
    [Test] procedure IdsAreUniqueInDocumentOrder;
    [Test] procedure SaveToFileRaisesWhenFileExists;
    [Test] procedure SaveToFileOverwritesWhenAllowed;
    [Test] procedure SaveToFileRaisesWhenFileCannotBeDeleted;
    [Test] procedure SaveToFileCreatesMissingDirectory;
  end;

implementation

uses
  System.IOUtils, System.RegularExpressions, System.SysUtils, Winapi.ActiveX;

const
  ASSEMBLY_PATH = '/test-run/test-suite';
  FIXTURE_PATH = ASSEMBLY_PATH + '/test-suite';
  OLD_CONTENT = 'old content';
  TIME_PATTERN = '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$';

{ TNUnitLoggerTests }

function TNUnitLoggerTests.NodeCount(const AXPath: string): Integer;
begin
  Result := FDocument.selectNodes(AXPath).length;
end;

function TNUnitLoggerTests.Value(const AXPath: string): string;
var
  LNode: IXMLDOMNode;
begin
  LNode := FDocument.selectSingleNode(AXPath);

  if not Assigned(LNode) then
    Assert.Fail('Node not found: ' + AXPath);

  Result := LNode.text;
end;

procedure TNUnitLoggerTests.CheckCounts(const AXPath: string; const ATotal, APassed, AFailed, AWarnings, AInconclusive,
  ASkipped, AAsserts: Integer);
begin
  Assert.AreEqual(ATotal.ToString, Value(AXPath + '/@testcasecount'), AXPath + ' testcasecount');
  Assert.AreEqual(ATotal.ToString, Value(AXPath + '/@total'), AXPath + ' total');
  Assert.AreEqual(APassed.ToString, Value(AXPath + '/@passed'), AXPath + ' passed');
  Assert.AreEqual(AFailed.ToString, Value(AXPath + '/@failed'), AXPath + ' failed');
  Assert.AreEqual(AWarnings.ToString, Value(AXPath + '/@warnings'), AXPath + ' warnings');
  Assert.AreEqual(AInconclusive.ToString, Value(AXPath + '/@inconclusive'), AXPath + ' inconclusive');
  Assert.AreEqual(ASkipped.ToString, Value(AXPath + '/@skipped'), AXPath + ' skipped');
  Assert.AreEqual(AAsserts.ToString, Value(AXPath + '/@asserts'), AXPath + ' asserts');
end;

procedure TNUnitLoggerTests.LoadResultFile;
begin
  FDocument := CoDOMDocument60.Create;
  FDocument.async := False;
  FDocument.preserveWhiteSpace := True;

  if not FDocument.load(FFileName) then
    Assert.Fail('Not valid XML: ' + FDocument.parseError.reason);
end;

procedure TNUnitLoggerTests.SaveAndLoad(const ALogger: TNUnitLogger);
begin
  ALogger.SaveToFile(FFileName);

  LoadResultFile;
end;

procedure TNUnitLoggerTests.WriteOldFile;
begin
  ForceDirectories(FDirectory);

  TFile.WriteAllText(FFileName, OLD_CONTENT);
end;

procedure TNUnitLoggerTests.SetupFixture;
begin
  CoInitialize(nil);
end;

procedure TNUnitLoggerTests.TearDownFixture;
begin
  CoUninitialize;
end;

procedure TNUnitLoggerTests.Setup;
begin
  FDirectory := TPath.Combine(TPath.GetTempPath, 'DNLUnitTests.' + TGUID.NewGuid.ToString);
  FFileName := TPath.Combine(FDirectory, 'Result.xml');
end;

procedure TNUnitLoggerTests.TearDown;
begin
  FDocument := nil;

  if FileExists(FFileName) then
    FileSetReadOnly(FFileName, False);

  if TDirectory.Exists(FDirectory) then
    TDirectory.Delete(FDirectory, True);
end;

procedure TNUnitLoggerTests.EmptyLoggerWritesRunAndAssemblySuite;
var
  LLogger: TNUnitLogger;
begin
  LLogger := TNUnitLogger.Create;
  try
    SaveAndLoad(LLogger);
  finally
    LLogger.Free;
  end;

  Assert.AreEqual(1, NodeCount('/test-run'), 'test-run');
  Assert.AreEqual('Passed', Value('/test-run/@result'), 'test-run result');
  Assert.AreEqual(1, NodeCount('/test-run/command-line'), 'command-line');
  Assert.AreEqual(1, NodeCount(ASSEMBLY_PATH), 'Assembly suite');
  Assert.AreEqual('Assembly', Value(ASSEMBLY_PATH + '/@type'), 'Assembly type');
  Assert.AreEqual(1, NodeCount(ASSEMBLY_PATH + '/environment'), 'environment');
  Assert.AreEqual(0, NodeCount(FIXTURE_PATH), 'fixtures');
  Assert.AreEqual(0, NodeCount('//test-case'), 'test cases');

  CheckCounts('/test-run', 0, 0, 0, 0, 0, 0, 0);
  CheckCounts(ASSEMBLY_PATH, 0, 0, 0, 0, 0, 0, 0);
end;

procedure TNUnitLoggerTests.DefaultNamesComeFromExecutable;
var
  LCommandLine: string;
  LLogger: TNUnitLogger;
  LName: string;
begin
  LName := ChangeFileExt(ExtractFileName(ParamStr(0)), '');

  LLogger := TNUnitLogger.Create;
  try
    Assert.AreEqual(LName, LLogger.Name, 'Name');
    Assert.AreEqual(ParamStr(0), LLogger.FullName, 'FullName');
    Assert.IsNotEmpty(LLogger.CommandLine, 'CommandLine');

    LCommandLine := LLogger.CommandLine;

    SaveAndLoad(LLogger);
  finally
    LLogger.Free;
  end;

  Assert.AreEqual(LName, Value('/test-run/@name'), 'test-run name');
  Assert.AreEqual(LName, Value('/test-run/@fullname'), 'test-run fullname');
  Assert.AreEqual(LCommandLine, Value('/test-run/command-line'), 'command-line');
  Assert.AreEqual(LName, Value(ASSEMBLY_PATH + '/@name'), 'Assembly name');
  Assert.AreEqual(ParamStr(0), Value(ASSEMBLY_PATH + '/@fullname'), 'Assembly fullname');
end;

procedure TNUnitLoggerTests.CustomNamesAreWritten;
var
  LLogger: TNUnitLogger;
begin
  LLogger := TNUnitLogger.Create;
  try
    LLogger.AddTestSuite('DisallowedList').AddTestCase('Common\Unit1.pas', ntrPassed);

    // Set after adding, the names are resolved when the file is written
    LLogger.Name := 'QualityControl';
    LLogger.FullName := 'C:\Tools\QualityControl.exe';
    LLogger.CommandLine := '"C:\Tools\QualityControl.exe" "C:\Projects"';

    SaveAndLoad(LLogger);
  finally
    LLogger.Free;
  end;

  Assert.AreEqual('QualityControl', Value('/test-run/@name'), 'test-run name');
  Assert.AreEqual('"C:\Tools\QualityControl.exe" "C:\Projects"', Value('/test-run/command-line'), 'command-line');
  Assert.AreEqual('QualityControl', Value(ASSEMBLY_PATH + '/@name'), 'Assembly name');
  Assert.AreEqual('C:\Tools\QualityControl.exe', Value(ASSEMBLY_PATH + '/@fullname'), 'Assembly fullname');

  Assert.AreEqual('TestFixture', Value(FIXTURE_PATH + '/@type'), 'fixture type');
  Assert.AreEqual('DisallowedList', Value(FIXTURE_PATH + '/@name'), 'fixture name');
  Assert.AreEqual('QualityControl.DisallowedList', Value(FIXTURE_PATH + '/@fullname'), 'fixture fullname');
  Assert.AreEqual('QualityControl.DisallowedList', Value(FIXTURE_PATH + '/@classname'), 'fixture classname');
  Assert.AreEqual('Runnable', Value(FIXTURE_PATH + '/@runstate'), 'fixture runstate');

  Assert.AreEqual('Common\Unit1.pas', Value(FIXTURE_PATH + '/test-case/@name'), 'case name');
  Assert.AreEqual('QualityControl.DisallowedList.Common\Unit1.pas', Value(FIXTURE_PATH + '/test-case/@fullname'),
    'case fullname');
  Assert.AreEqual('Common\Unit1.pas', Value(FIXTURE_PATH + '/test-case/@methodname'), 'case methodname');
  Assert.AreEqual('QualityControl.DisallowedList', Value(FIXTURE_PATH + '/test-case/@classname'), 'case classname');
  Assert.AreEqual('Runnable', Value(FIXTURE_PATH + '/test-case/@runstate'), 'case runstate');
end;

procedure TNUnitLoggerTests.CountsAreSummedToSuitesAndRun;
var
  LLogger: TNUnitLogger;
  LTestSuite: TNUnitTestSuite;
begin
  LLogger := TNUnitLogger.Create;
  try
    LTestSuite := LLogger.AddTestSuite('First');
    LTestSuite.AddTestCase('Passed', ntrPassed, 0.0, '', '', 2);
    LTestSuite.AddTestCase('Failed', ntrFailed);
    LTestSuite.AddTestCase('Error', ntrError);
    LTestSuite.AddTestCase('Skipped', ntrSkipped);

    LTestSuite := LLogger.AddTestSuite('Second');
    LTestSuite.AddTestCase('Warning', ntrWarning);
    LTestSuite.AddTestCase('Inconclusive', ntrInconclusive);
    LTestSuite.AddTestCase('Passed', ntrPassed, 0.0, '', '', 3);

    SaveAndLoad(LLogger);
  finally
    LLogger.Free;
  end;

  CheckCounts(FIXTURE_PATH + '[1]', 4, 1, 2, 0, 0, 1, 2);
  CheckCounts(FIXTURE_PATH + '[2]', 3, 1, 0, 1, 1, 0, 3);
  CheckCounts(ASSEMBLY_PATH, 7, 2, 2, 1, 1, 1, 5);
  CheckCounts('/test-run', 7, 2, 2, 1, 1, 1, 5);
end;

procedure TNUnitLoggerTests.TestCaseResultsAreWritten;
const
  EXPECTED_RESULTS: array[TNUnitTestResult] of string = ('Passed', 'Failed', 'Failed', 'Skipped', 'Inconclusive', 'Warning');
var
  LCasePath: string;
  LLogger: TNUnitLogger;
  LTestResult: TNUnitTestResult;
  LTestSuite: TNUnitTestSuite;
begin
  LLogger := TNUnitLogger.Create;
  try
    LTestSuite := LLogger.AddTestSuite('Results');

    for LTestResult := Low(TNUnitTestResult) to High(TNUnitTestResult) do
      LTestSuite.AddTestCase('Case' + Ord(LTestResult).ToString, LTestResult);

    SaveAndLoad(LLogger);
  finally
    LLogger.Free;
  end;

  for LTestResult := Low(TNUnitTestResult) to High(TNUnitTestResult) do
  begin
    LCasePath := FIXTURE_PATH + '/test-case[' + (Ord(LTestResult) + 1).ToString + ']';

    Assert.AreEqual(EXPECTED_RESULTS[LTestResult], Value(LCasePath + '/@result'), LCasePath);

    if LTestResult = ntrError then
      Assert.AreEqual('Error', Value(LCasePath + '/@label'), LCasePath + ' label')
    else
      Assert.AreEqual(0, NodeCount(LCasePath + '/@label'), LCasePath + ' label');
  end;
end;

procedure TNUnitLoggerTests.SuiteResultFollowsNUnitRules;
var
  LLogger: TNUnitLogger;
  LTestSuite: TNUnitTestSuite;
begin
  LLogger := TNUnitLogger.Create;
  try
    LTestSuite := LLogger.AddTestSuite('FailedAndPassed');
    LTestSuite.AddTestCase('A', ntrPassed);
    LTestSuite.AddTestCase('B', ntrFailed);

    LLogger.AddTestSuite('ErrorOnly').AddTestCase('A', ntrError);

    LTestSuite := LLogger.AddTestSuite('WarningAndPassed');
    LTestSuite.AddTestCase('A', ntrWarning);
    LTestSuite.AddTestCase('B', ntrPassed);

    LTestSuite := LLogger.AddTestSuite('WarningAndFailed');
    LTestSuite.AddTestCase('A', ntrWarning);
    LTestSuite.AddTestCase('B', ntrFailed);

    LTestSuite := LLogger.AddTestSuite('PassedAndSkipped');
    LTestSuite.AddTestCase('A', ntrPassed);
    LTestSuite.AddTestCase('B', ntrSkipped);

    LLogger.AddTestSuite('Empty');

    LTestSuite := LLogger.AddTestSuite('InconclusiveAndSkipped');
    LTestSuite.AddTestCase('A', ntrInconclusive);
    LTestSuite.AddTestCase('B', ntrSkipped);

    LTestSuite := LLogger.AddTestSuite('SkippedOnly');
    LTestSuite.AddTestCase('A', ntrSkipped);
    LTestSuite.AddTestCase('B', ntrSkipped);

    SaveAndLoad(LLogger);
  finally
    LLogger.Free;
  end;

  Assert.AreEqual('Failed', Value(FIXTURE_PATH + '[1]/@result'), 'FailedAndPassed');
  Assert.AreEqual('Failed', Value(FIXTURE_PATH + '[2]/@result'), 'ErrorOnly');
  Assert.AreEqual('Warning', Value(FIXTURE_PATH + '[3]/@result'), 'WarningAndPassed');
  Assert.AreEqual('Failed', Value(FIXTURE_PATH + '[4]/@result'), 'WarningAndFailed');
  Assert.AreEqual('Passed', Value(FIXTURE_PATH + '[5]/@result'), 'PassedAndSkipped');
  Assert.AreEqual('Passed', Value(FIXTURE_PATH + '[6]/@result'), 'Empty');
  Assert.AreEqual('Inconclusive', Value(FIXTURE_PATH + '[7]/@result'), 'InconclusiveAndSkipped');
  Assert.AreEqual('Skipped', Value(FIXTURE_PATH + '[8]/@result'), 'SkippedOnly');
  Assert.AreEqual('Failed', Value(ASSEMBLY_PATH + '/@result'), 'Assembly');
  Assert.AreEqual('Failed', Value('/test-run/@result'), 'test-run');
end;

procedure TNUnitLoggerTests.FailedSuitesGetChildFailure;
const
  CHILD_FAILURE = 'One or more child tests had errors';
var
  LLogger: TNUnitLogger;
begin
  LLogger := TNUnitLogger.Create;
  try
    LLogger.AddTestSuite('Failing').AddTestCase('A', ntrFailed);
    LLogger.AddTestSuite('Passing').AddTestCase('A', ntrPassed);

    SaveAndLoad(LLogger);
  finally
    LLogger.Free;
  end;

  Assert.AreEqual(0, NodeCount('/test-run/@site'), 'test-run site');
  Assert.AreEqual('Child', Value(ASSEMBLY_PATH + '/@site'), 'Assembly site');
  Assert.AreEqual(CHILD_FAILURE, Value(ASSEMBLY_PATH + '/failure/message'), 'Assembly failure');
  Assert.AreEqual('Child', Value(FIXTURE_PATH + '[1]/@site'), 'Failing site');
  Assert.AreEqual(CHILD_FAILURE, Value(FIXTURE_PATH + '[1]/failure/message'), 'Failing failure');
  Assert.AreEqual(0, NodeCount(FIXTURE_PATH + '[2]/@site'), 'Passing site');
  Assert.AreEqual(0, NodeCount(FIXTURE_PATH + '[2]/failure'), 'Passing failure');
end;

procedure TNUnitLoggerTests.FailureHasMessageAndStackTrace;
var
  LLogger: TNUnitLogger;
  LTestSuite: TNUnitTestSuite;
begin
  LLogger := TNUnitLogger.Create;
  try
    LTestSuite := LLogger.AddTestSuite('Failures');
    LTestSuite.AddTestCase('WithStackTrace', ntrFailed, 0.0, 'Expected 1, got 2', 'at TFoo.Bar');
    LTestSuite.AddTestCase('WithoutMessage', ntrFailed);
    LTestSuite.AddTestCase('Error', ntrError, 0.0, 'Access violation');

    SaveAndLoad(LLogger);
  finally
    LLogger.Free;
  end;

  Assert.AreEqual('Expected 1, got 2', Value(FIXTURE_PATH + '/test-case[1]/failure/message'), 'message');
  Assert.AreEqual('at TFoo.Bar', Value(FIXTURE_PATH + '/test-case[1]/failure/stack-trace'), 'stack-trace');

  // A failure always has a message element, stack-trace only when there is one
  Assert.AreEqual(1, NodeCount(FIXTURE_PATH + '/test-case[2]/failure/message'), 'empty message');
  Assert.AreEqual('', Value(FIXTURE_PATH + '/test-case[2]/failure/message'), 'empty message text');
  Assert.AreEqual(0, NodeCount(FIXTURE_PATH + '/test-case[2]/failure/stack-trace'), 'no stack-trace');

  Assert.AreEqual('Access violation', Value(FIXTURE_PATH + '/test-case[3]/failure/message'), 'error message');
  Assert.AreEqual(0, NodeCount(FIXTURE_PATH + '/test-case/reason'), 'reason');
end;

procedure TNUnitLoggerTests.ReasonIsWrittenOnlyWithMessage;
var
  LLogger: TNUnitLogger;
  LTestSuite: TNUnitTestSuite;
begin
  LLogger := TNUnitLogger.Create;
  try
    LTestSuite := LLogger.AddTestSuite('Reasons');
    LTestSuite.AddTestCase('SkippedWithMessage', ntrSkipped, 0.0, 'Not applicable');
    LTestSuite.AddTestCase('PassedWithMessage', ntrPassed, 0.0, 'All good');
    LTestSuite.AddTestCase('PassedWithoutMessage', ntrPassed);
    LTestSuite.AddTestCase('SkippedWithStackTraceOnly', ntrSkipped, 0.0, '', 'at TFoo.Bar');
    LTestSuite.AddTestCase('InconclusiveWithMessage', ntrInconclusive, 0.0, 'Could not decide');

    SaveAndLoad(LLogger);
  finally
    LLogger.Free;
  end;

  Assert.AreEqual('Not applicable', Value(FIXTURE_PATH + '/test-case[1]/reason/message'), 'skipped');
  Assert.AreEqual('All good', Value(FIXTURE_PATH + '/test-case[2]/reason/message'), 'passed');
  Assert.AreEqual(0, NodeCount(FIXTURE_PATH + '/test-case[3]/*'), 'passed without message');
  Assert.AreEqual(0, NodeCount(FIXTURE_PATH + '/test-case[4]/*'), 'stack trace only');
  Assert.AreEqual('Could not decide', Value(FIXTURE_PATH + '/test-case[5]/reason/message'), 'inconclusive');
  Assert.AreEqual(0, NodeCount(FIXTURE_PATH + '/test-case/failure'), 'failure');
end;

procedure TNUnitLoggerTests.SpecialCharactersRoundTrip;
const
  MESSAGE_TEXT = 'Ends ]]> here' + #13#10 + 'Second ]]]]> line <&> ' + #$E4#$F6' '#$20AC' '#$D83D#$DE00;
  // XML parsers normalize CRLF to LF in text content, character references in attributes are kept
  MESSAGE_PARSED = 'Ends ]]> here' + #10 + 'Second ]]]]> line <&> ' + #$E4#$F6' '#$20AC' '#$D83D#$DE00;
  NAME_TEXT = 'Unit "1" & <2> ''3''' + #9 + 'tab' + #13#10 + 'line ' + #$E4#$20AC'.pas';
  // MSXML also turns the &#xD;&#xA; character references of an attribute into a single LF when reading
  NAME_PARSED = 'Unit "1" & <2> ''3''' + #9 + 'tab' + #10 + 'line ' + #$E4#$20AC'.pas';
  NAME_WRITTEN = 'name="Unit &quot;1&quot; &amp; &lt;2&gt; ''3''&#x9;tab&#xD;&#xA;line ' + #$E4#$20AC'.pas"';
var
  LLogger: TNUnitLogger;
begin
  LLogger := TNUnitLogger.Create;
  try
    LLogger.CommandLine := '"C:\A & B\Tool.exe" <in> ' + #$E4;
    LLogger.AddTestSuite('Suite & <Co>').AddTestCase(NAME_TEXT, ntrFailed, 0.0, MESSAGE_TEXT, MESSAGE_TEXT);

    SaveAndLoad(LLogger);
  finally
    LLogger.Free;
  end;

  Assert.AreEqual('"C:\A & B\Tool.exe" <in> ' + #$E4, Value('/test-run/command-line'), 'command-line');
  Assert.AreEqual('Suite & <Co>', Value(FIXTURE_PATH + '/@name'), 'suite name');
  Assert.IsTrue(TFile.ReadAllText(FFileName, TEncoding.UTF8).Contains(NAME_WRITTEN), 'case name written');
  Assert.AreEqual(NAME_PARSED, Value(FIXTURE_PATH + '/test-case/@name'), 'case name');
  Assert.AreEqual(MESSAGE_PARSED, Value(FIXTURE_PATH + '/test-case/failure/message'), 'message');
  Assert.AreEqual(MESSAGE_PARSED, Value(FIXTURE_PATH + '/test-case/failure/stack-trace'), 'stack-trace');
end;

procedure TNUnitLoggerTests.InvalidXmlCharactersAreReplaced;
var
  LLogger: TNUnitLogger;
begin
  LLogger := TNUnitLogger.Create;
  try
    LLogger.AddTestSuite('Suite').AddTestCase('Bell'#7'Name', ntrSkipped, 0.0, 'Null'#0'Escape'#27'Message'#$FFFF);

    SaveAndLoad(LLogger);
  finally
    LLogger.Free;
  end;

  Assert.AreEqual('Bell?Name', Value(FIXTURE_PATH + '/test-case/@name'), 'name');
  Assert.AreEqual('Null?Escape?Message?', Value(FIXTURE_PATH + '/test-case/reason/message'), 'message');
end;

procedure TNUnitLoggerTests.FileIsUtf8WithoutBomAndIndented;
var
  LBytes: TBytes;
  LLines: TArray<string>;
  LLogger: TNUnitLogger;
  LText: string;
begin
  LLogger := TNUnitLogger.Create;
  try
    LLogger.AddTestSuite('Suite').AddTestCase(#$E4'.pas', ntrPassed);

    SaveAndLoad(LLogger);
  finally
    LLogger.Free;
  end;

  LBytes := TFile.ReadAllBytes(FFileName);
  LText := TEncoding.UTF8.GetString(LBytes);
  LLines := LText.Split([#13#10]);

  Assert.AreEqual('<?xml version="1.0" encoding="utf-8"?>', LLines[0], 'declaration without BOM');
  Assert.IsTrue(LText.Contains('name="' + #$E4 + '.pas"'), 'UTF-8 decoded');
  Assert.IsFalse(LText.Replace(#13#10, '').Contains(#10), 'lone LF');
  Assert.IsFalse(LText.Replace(#13#10, '').Contains(#13), 'lone CR');
  Assert.IsTrue(LText.EndsWith('</test-run>' + #13#10), 'ends with line break');

  Assert.IsTrue(LLines[1].StartsWith('<test-run '), 'test-run indent');
  Assert.IsTrue(LLines[2].StartsWith('  <command-line>'), 'command-line indent');
  Assert.IsTrue(LLines[3].StartsWith('  <test-suite type="Assembly"'), 'Assembly indent');
  Assert.IsTrue(LLines[4].StartsWith('    <environment '), 'environment indent');
  Assert.IsTrue(LLines[5].StartsWith('    <test-suite type="TestFixture"'), 'fixture indent');
  Assert.IsTrue(LLines[6].StartsWith('      <test-case '), 'test-case indent');
  Assert.IsTrue(LLines[6].EndsWith(' />'), 'test-case without children is self-closing');
end;

procedure TNUnitLoggerTests.DurationAndAssertsAreWritten;
var
  LDuration: Double;
  LLogger: TNUnitLogger;
  LTestSuite: TNUnitTestSuite;
begin
  LLogger := TNUnitLogger.Create;
  try
    LTestSuite := LLogger.AddTestSuite('Timings');
    LTestSuite.AddTestCase('Default', ntrPassed);
    LTestSuite.AddTestCase('OneAndHalf', ntrPassed, 1.5, '', '', 7);
    LTestSuite.AddTestCase('Tiny', ntrPassed, 0.0004);

    SaveAndLoad(LLogger);
  finally
    LLogger.Free;
  end;

  Assert.AreEqual('0.000', Value(FIXTURE_PATH + '/test-case[1]/@duration'), 'default duration');
  Assert.AreEqual('0', Value(FIXTURE_PATH + '/test-case[1]/@asserts'), 'default asserts');
  Assert.AreEqual('1.500', Value(FIXTURE_PATH + '/test-case[2]/@duration'), 'duration');
  Assert.AreEqual('7', Value(FIXTURE_PATH + '/test-case[2]/@asserts'), 'asserts');
  Assert.AreEqual('0.000', Value(FIXTURE_PATH + '/test-case[3]/@duration'), 'rounded duration');

  // The suite and the run cover the 1.5 seconds that ended when the test case was added
  LDuration := StrToFloat(Value(FIXTURE_PATH + '/@duration'), TFormatSettings.Invariant);
  Assert.IsTrue(LDuration >= 1.499, 'suite duration ' + LDuration.ToString);

  LDuration := StrToFloat(Value('/test-run/@duration'), TFormatSettings.Invariant);
  Assert.IsTrue(LDuration >= 1.499, 'run duration ' + LDuration.ToString);
end;

procedure TNUnitLoggerTests.TimesIgnoreFormatSettings;
var
  LFormatSettings: TFormatSettings;
  LLogger: TNUnitLogger;
begin
  LFormatSettings := FormatSettings;
  try
    FormatSettings.DateSeparator := '.';
    FormatSettings.DecimalSeparator := ',';
    FormatSettings.TimeSeparator := '.';

    LLogger := TNUnitLogger.Create;
    try
      LLogger.AddTestSuite('Suite').AddTestCase('A', ntrPassed, 2.25);

      SaveAndLoad(LLogger);
    finally
      LLogger.Free;
    end;
  finally
    FormatSettings := LFormatSettings;
  end;

  Assert.AreEqual('2.250', Value(FIXTURE_PATH + '/test-case/@duration'), 'duration');
  Assert.IsTrue(TRegEx.IsMatch(Value(FIXTURE_PATH + '/test-case/@start-time'), TIME_PATTERN), 'start-time');
  Assert.IsTrue(TRegEx.IsMatch(Value(FIXTURE_PATH + '/test-case/@end-time'), TIME_PATTERN), 'end-time');
  Assert.IsTrue(TRegEx.IsMatch(Value('/test-run/@start-time'), TIME_PATTERN), 'run start-time');
end;

procedure TNUnitLoggerTests.IdsAreUniqueInDocumentOrder;
var
  LIndex: Integer;
  LLogger: TNUnitLogger;
  LNodes: IXMLDOMNodeList;
  LTestSuite: TNUnitTestSuite;
begin
  LLogger := TNUnitLogger.Create;
  try
    LTestSuite := LLogger.AddTestSuite('First');
    LTestSuite.AddTestCase('A', ntrPassed);
    LTestSuite.AddTestCase('B', ntrFailed);

    LTestSuite := LLogger.AddTestSuite('Second');
    LTestSuite.AddTestCase('C', ntrPassed);

    SaveAndLoad(LLogger);
  finally
    LLogger.Free;
  end;

  Assert.AreEqual('2', Value('/test-run/@id'), 'test-run id');

  LNodes := FDocument.selectNodes('//test-suite | //test-case');
  Assert.AreEqual(6, LNodes.length, 'node count');

  for LIndex := 0 to LNodes.length - 1 do
    Assert.AreEqual('0-' + (LIndex + 1).ToString, LNodes.item[LIndex].attributes.getNamedItem('id').text,
      'id of ' + LNodes.item[LIndex].nodeName + ' ' + LIndex.ToString);
end;

procedure TNUnitLoggerTests.SaveToFileRaisesWhenFileExists;
var
  LLogger: TNUnitLogger;
begin
  WriteOldFile;

  LLogger := TNUnitLogger.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        LLogger.SaveToFile(FFileName);
      end,
      ENUnitLogger);
  finally
    LLogger.Free;
  end;

  Assert.AreEqual(OLD_CONTENT, TFile.ReadAllText(FFileName), 'file left untouched');
end;

procedure TNUnitLoggerTests.SaveToFileOverwritesWhenAllowed;
var
  LLogger: TNUnitLogger;
  LTestSuite: TNUnitTestSuite;
begin
  WriteOldFile;

  LLogger := TNUnitLogger.Create;
  try
    LTestSuite := LLogger.AddTestSuite('Suite');
    LTestSuite.AddTestCase('A', ntrPassed);
    LLogger.SaveToFile(FFileName, True);

    // Saving again writes the current state
    LTestSuite.AddTestCase('B', ntrPassed);
    LLogger.SaveToFile(FFileName, True);
  finally
    LLogger.Free;
  end;

  LoadResultFile;

  Assert.AreEqual(2, NodeCount('//test-case'), 'test cases');
end;

procedure TNUnitLoggerTests.SaveToFileRaisesWhenFileCannotBeDeleted;
var
  LLogger: TNUnitLogger;
begin
  WriteOldFile;
  FileSetReadOnly(FFileName, True);

  LLogger := TNUnitLogger.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        LLogger.SaveToFile(FFileName, True);
      end,
      ENUnitLogger);
  finally
    LLogger.Free;
  end;

  Assert.AreEqual(OLD_CONTENT, TFile.ReadAllText(FFileName), 'file left untouched');
end;

procedure TNUnitLoggerTests.SaveToFileCreatesMissingDirectory;
var
  LLogger: TNUnitLogger;
begin
  FFileName := TPath.Combine(FDirectory, 'Sub\Deeper\Result.xml');

  LLogger := TNUnitLogger.Create;
  try
    SaveAndLoad(LLogger);
  finally
    LLogger.Free;
  end;

  Assert.IsTrue(FileExists(FFileName), 'file');
end;

end.
