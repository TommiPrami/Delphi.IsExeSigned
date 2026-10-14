program DNLUnitTests;

{$IF NOT DEFINED(TESTINSIGHT)}
  {$APPTYPE CONSOLE}
{$ENDIF}

{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  {$IF DEFINED(TESTINSIGHT)}
  TestInsight.DUnitX,
  {$ELSE}
  DUnitX.Loggers.Console,
  DUnitX.Loggers.XML.NUnit,
  {$ENDIF }
  DUnitX.TestFramework,
  DNLUnit.NUnitLogger in '..\DNLUnit.NUnitLogger.pas',
  DNLUnit.NUnitLogger.Tests in 'Tests\DNLUnit.NUnitLogger.Tests.pas',
  DNLUnit.NUnitLogger.SpeedTests in 'Tests\DNLUnit.NUnitLogger.SpeedTests.pas';

{ keep comment here to protect the following conditional from being removed by the IDE when adding a unit }
{$IF NOT DEFINED(TESTINSIGHT)}
var
  LLogger: ITestLogger;
  LNUnitLogger: ITestLogger;
  LResults: IRunResults;
  LRunner: ITestRunner;
{$ENDIF}
begin
  {$IF DEFINED(DEBUG)}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}

  {$IF DEFINED(TESTINSIGHT)}
  TestInsight.DUnitX.RunRegisteredTests;
  {$ELSE}
  try
    // Check command line options, will exit if invalid
    TDUnitX.CheckCommandLine;

    LRunner := TDUnitX.CreateRunner;
    // Use RTTI to find the fixtures
    LRunner.UseRTTI := True;
    // When true, assertions must be made during tests
    LRunner.FailsOnNoAsserts := False;

    if TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off then
    begin
      LLogger := TDUnitXConsoleLogger.Create(TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Quiet);
      LRunner.AddLogger(LLogger);
    end;

    // Generate an NUnit compatible XML file
    LNUnitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    LRunner.AddLogger(LNUnitLogger);

    LResults := LRunner.Execute;

    if not LResults.AllPassed then
      System.ExitCode := EXIT_ERRORS;

    {$IF NOT DEFINED(CI)}
    // We don't want this happening when running under CI
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Done.. press <Enter> key to quit.');
      System.Readln;
    end;
    {$ENDIF}
  except
    on E: Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;
  {$ENDIF}
end.
