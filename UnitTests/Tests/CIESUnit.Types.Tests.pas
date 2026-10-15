unit CIESUnit.Types.Tests;

// TCommandLineParameters called directly, in this process.

interface

uses
  DUnitX.TestFramework, CIESUnit.Types;

type
  [TestFixture]
  TCommandLineParametersTests = class(TObject)
  strict private
    FParameters: TCommandLineParameters;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure GetLogFileNameIsEmptyWithoutLogParameters;
    [Test] procedure GetLogFileNameDefaultsToApplicationFolder;
    [Test] procedure GetLogFileNameDoesNotChangeLogFile;
    [Test] procedure GetLogFileNameExpandsRelativeLogFile;
    [Test] procedure LogFileIsUsedWithoutLog;
  end;

implementation

uses
  System.SysUtils, CIESUnit.Consts;

{ TCommandLineParametersTests }

procedure TCommandLineParametersTests.Setup;
begin
  FParameters := TCommandLineParameters.Create;
end;

procedure TCommandLineParametersTests.TearDown;
begin
  FParameters.Free;
end;

procedure TCommandLineParametersTests.GetLogFileNameDefaultsToApplicationFolder;
begin
  FParameters.Log := True;

  Assert.AreEqual(ExtractFilePath(ParamStr(0)) + LOG_FILE_NAME_DEFAULT, FParameters.GetLogFileName);
end;

procedure TCommandLineParametersTests.GetLogFileNameDoesNotChangeLogFile;
begin
  FParameters.Log := True;
  FParameters.LogFile := 'Relative.xml';

  FParameters.GetLogFileName;

  Assert.AreEqual('Relative.xml', FParameters.LogFile);

  FParameters.LogFile := '';

  FParameters.GetLogFileName;

  Assert.AreEqual('', FParameters.LogFile, 'Default file name stored into LogFile');
end;

procedure TCommandLineParametersTests.GetLogFileNameExpandsRelativeLogFile;
begin
  FParameters.LogFile := 'Logs\Result.xml';

  Assert.AreEqual(ExpandFileName('Logs\Result.xml'), FParameters.GetLogFileName);
end;

procedure TCommandLineParametersTests.GetLogFileNameIsEmptyWithoutLogParameters;
begin
  Assert.AreEqual('', FParameters.GetLogFileName);
end;

procedure TCommandLineParametersTests.LogFileIsUsedWithoutLog;
begin
  FParameters.Log := False;
  FParameters.LogFile := 'C:\Logs\Result.xml';

  Assert.AreEqual('C:\Logs\Result.xml', FParameters.GetLogFileName);
end;

end.
