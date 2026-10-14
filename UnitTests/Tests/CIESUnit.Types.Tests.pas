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
    [Test] procedure GetLogFileNameDoesNotChangeLogFileName;
    [Test] procedure GetLogFileNameExpandsRelativeLogFileName;
    [Test] procedure LogFileNameIsUsedWithoutLogToFile;
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
  FParameters.LogToFile := True;

  Assert.AreEqual(ExtractFilePath(ParamStr(0)) + LOG_FILE_NAME_DEFAULT, FParameters.GetLogFileName);
end;

procedure TCommandLineParametersTests.GetLogFileNameDoesNotChangeLogFileName;
begin
  FParameters.LogToFile := True;
  FParameters.LogFileName := 'Relative.xml';

  FParameters.GetLogFileName;

  Assert.AreEqual('Relative.xml', FParameters.LogFileName);

  FParameters.LogFileName := '';

  FParameters.GetLogFileName;

  Assert.AreEqual('', FParameters.LogFileName, 'Default file name stored into LogFileName');
end;

procedure TCommandLineParametersTests.GetLogFileNameExpandsRelativeLogFileName;
begin
  FParameters.LogFileName := 'Logs\Result.xml';

  Assert.AreEqual(ExpandFileName('Logs\Result.xml'), FParameters.GetLogFileName);
end;

procedure TCommandLineParametersTests.GetLogFileNameIsEmptyWithoutLogParameters;
begin
  Assert.AreEqual('', FParameters.GetLogFileName);
end;

procedure TCommandLineParametersTests.LogFileNameIsUsedWithoutLogToFile;
begin
  FParameters.LogToFile := False;
  FParameters.LogFileName := 'C:\Logs\Result.xml';

  Assert.AreEqual('C:\Logs\Result.xml', FParameters.GetLogFileName);
end;

end.
