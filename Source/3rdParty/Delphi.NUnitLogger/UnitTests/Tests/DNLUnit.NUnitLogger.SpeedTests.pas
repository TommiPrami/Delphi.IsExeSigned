unit DNLUnit.NUnitLogger.SpeedTests;

// Write speed. Nothing is asserted about the times, they are reported as the pass message (shown by TestInsight)
// and logged (shown by the console runner). Every 10th test case fails with a message and a stack trace.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Speed')]
  TNUnitLoggerSpeedTests = class(TObject)
  strict private
    FDirectory: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [TestCase('1 000 test cases', '10,100')]
    [TestCase('10 000 test cases', '10,1000')]
    [TestCase('100 000 test cases', '100,1000')]
    procedure WriteSpeed(const ATestSuiteCount, ATestCaseCount: Integer);
  end;

implementation

uses
  System.Diagnostics, System.IOUtils, System.SysUtils, DNLUnit.NUnitLogger;

{ TNUnitLoggerSpeedTests }

procedure TNUnitLoggerSpeedTests.Setup;
begin
  FDirectory := TPath.Combine(TPath.GetTempPath, 'DNLUnitTests.' + TGUID.NewGuid.ToString);
end;

procedure TNUnitLoggerSpeedTests.TearDown;
begin
  if TDirectory.Exists(FDirectory) then
    TDirectory.Delete(FDirectory, True);
end;

procedure TNUnitLoggerSpeedTests.WriteSpeed(const ATestSuiteCount, ATestCaseCount: Integer);
var
  LAddStopwatch: TStopwatch;
  LCaseIndex: Integer;
  LFileName: string;
  LLogger: TNUnitLogger;
  LMessage: string;
  LSaveStopwatch: TStopwatch;
  LSuiteIndex: Integer;
  LTestSuite: TNUnitTestSuite;
  LTotalCount: Integer;
begin
  LFileName := TPath.Combine(FDirectory, 'Result.xml');
  LTotalCount := ATestSuiteCount * ATestCaseCount;

  LLogger := TNUnitLogger.Create;
  try
    LAddStopwatch := TStopwatch.StartNew;

    for LSuiteIndex := 1 to ATestSuiteCount do
    begin
      LTestSuite := LLogger.AddTestSuite('TestSuite' + LSuiteIndex.ToString);

      for LCaseIndex := 1 to ATestCaseCount do
        if LCaseIndex mod 10 = 0 then
          LTestSuite.AddTestCase('Projects\Application\Forms\ApplicationForm.Unit' + LCaseIndex.ToString + '.pas', ntrFailed,
            0.0123, 'Line ' + LCaseIndex.ToString + ': disallowed identifier "Application.ProcessMessages" & <more>',
            'at TQualityControl.CheckFile' + sLineBreak + 'at TQualityControl.Run')
        else
          LTestSuite.AddTestCase('Projects\Application\Forms\ApplicationForm.Unit' + LCaseIndex.ToString + '.pas', ntrPassed,
            0.0012);
    end;

    LAddStopwatch.Stop;

    LSaveStopwatch := TStopwatch.StartNew;
    LLogger.SaveToFile(LFileName);
    LSaveStopwatch.Stop;
  finally
    LLogger.Free;
  end;

  Assert.IsTrue(FileExists(LFileName), 'file');

  LMessage := Format('%d test cases: AddTestCase %s ms, SaveToFile %s ms, %s MB, %s test cases/s', [LTotalCount,
    FormatFloat('0.000', LAddStopwatch.Elapsed.TotalMilliseconds),
    FormatFloat('0.000', LSaveStopwatch.Elapsed.TotalMilliseconds),
    FormatFloat('0.0', TFile.GetSize(LFileName) / (1024 * 1024)),
    FormatFloat('0', LTotalCount / LSaveStopwatch.Elapsed.TotalSeconds)]);

  TDUnitX.CurrentRunner.Log(TLogLevel.Information, LMessage);
  Assert.Pass(LMessage);
end;

end.
