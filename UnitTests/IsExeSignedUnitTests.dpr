program IsExeSignedUnitTests;

{$IF NOT DEFINED(TESTINSIGHT)}
  {$APPTYPE CONSOLE}
{$ENDIF}

{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  {$IFDEF TESTINSIGHT}
  TestInsight.DUnitX,
  {$ELSE}
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  {$ENDIF }
  DUnitX.TestFramework,
  Delphi.CommandLineParser in '..\Source\3rdParty\Delphi.CommandLineParser\Delphi.CommandLineParser.pas',
  Delphi.WildCardMatcher in '..\Source\3rdParty\Delphi.WildCardMatcher\Source\Delphi.WildCardMatcher.pas',
  CIESUnit.Consts in '..\Source\CIESUnit.Consts.pas',
  CIESUnit.Types in '..\Source\CIESUnit.Types.pas',
  CIESUnit.Utils in '..\Source\CIESUnit.Utils.pas',
  CIESUnit.Tests.Common in 'Tests\CIESUnit.Tests.Common.pas',
  CIESUnit.Utils.Tests in 'Tests\CIESUnit.Utils.Tests.pas',
  CIESUnit.Types.Tests in 'Tests\CIESUnit.Types.Tests.pas',
  CIESUnit.Integration.Parameters.Tests in 'Tests\CIESUnit.Integration.Parameters.Tests.pas',
  CIESUnit.Integration.Check.Tests in 'Tests\CIESUnit.Integration.Check.Tests.pas',
  CIESUnit.Integration.Signing.Tests in 'Tests\CIESUnit.Integration.Signing.Tests.pas',
  CIESUnit.Integration.Log.Tests in 'Tests\CIESUnit.Integration.Log.Tests.pas';

{ keep comment here to protect the following conditional from being removed by the IDE when adding a unit }
{$IF NOT DEFINED(TESTINSIGHT)}
var
  LRunner: ITestRunner;
  LResults: IRunResults;
  LLogger: ITestLogger;
  LNunitLogger : ITestLogger;
{$ENDIF}
begin
{$IF DEFINED(TESTINSIGHT)}
  TestInsight.DUnitX.RunRegisteredTests;
{$ELSE}
  try
    //Check command line options, will exit if invalid
    TDUnitX.CheckCommandLine;
    //Create the test runner
    LRunner := TDUnitX.CreateRunner;
    //Tell the runner to use RTTI to find Fixtures
    LRunner.UseRTTI := True;
    //When true, Assertions must be made during tests;
    LRunner.FailsOnNoAsserts := False;

    //tell the runner how we will log things
    //Log to the console window if desired
    if TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off then
    begin
      LLogger := TDUnitXConsoleLogger.Create(TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Quiet);
      LRunner.AddLogger(LLogger);
    end;

    //Generate an NUnit compatible XML File
    LNunitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    LRunner.AddLogger(LNunitLogger);

    //Run tests
    LResults := LRunner.Execute;

    if not LResults.AllPassed then
      System.ExitCode := EXIT_ERRORS;

  {$IF NOT DEFINED(CI)}
    //We don't want this happening when running under CI.
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Done.. press <Enter> key to quit.');
      System.Readln;
    end;
  {$ENDIF}
  except
    on E: Exception do
    begin
      System.Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := EXIT_ERRORS;
    end;
  end;
{$ENDIF}
end.
