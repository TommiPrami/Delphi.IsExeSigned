unit CIESUnit.Integration.Parameters.Tests;

// IsExeSigned.exe run as a separate process: invalid command lines and their exit codes, and the settings Verbose
// writes.

interface

uses
  DUnitX.TestFramework, CIESUnit.Tests.Common;

type
  [TestFixture]
  TIsExeSignedParameterTests = class(TObject)
  strict private
    FFiles: TTestFiles;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure NoParametersShowsUsage;
    [Test] procedure InvalidBooleanValueShowsUsage;
    [Test] procedure InvalidFailModeShowsUsage;
    [Test] procedure MissingFile;
    [Test] procedure PatternWithoutDirectory;
    [Test] procedure MissingDirectory;
    [Test] procedure NoFilesMatchThePattern;
    [Test] procedure SignFilterWithoutCommand;
    [Test]
    [TestCase('Zero', '0')]
    [TestCase('Over one day', '86401')]
    procedure SignTimeoutOutOfRange(const ASeconds: string);
    [Test] procedure SignCommandWithoutPlaceholder;
    // Command line errors are not results of the run, they set the exit code also with LogOnly
    [Test] procedure ParameterErrorWithLogOnly;

    [Test] procedure VerboseWritesSettingsByDefault;
    [Test] procedure VerboseFalseWritesNoSettings;
    [Test] procedure VerboseShowsAutoFailModeWithLog;
    [Test] procedure VerboseShowsExplicitFailMode;
    [Test] procedure VerboseShowsImpliedSettings;
    // Written before the parameter values are checked
    [Test] procedure VerboseWritesSettingsWhenValueIsNotValid;
  end;

implementation

uses
  System.SysUtils, CIESUnit.Consts;

// Line of one setting, as Verbose writes it
function SettingLine(const AName, AValue: string): string;
begin
  Result := '  ' + AName.PadRight(21) + ' : ' + AValue;
end;

{ TIsExeSignedParameterTests }

procedure TIsExeSignedParameterTests.Setup;
begin
  FFiles := TTestFiles.Create;
end;

procedure TIsExeSignedParameterTests.TearDown;
begin
  FFiles.Free;
end;

procedure TIsExeSignedParameterTests.InvalidBooleanValueShowsUsage;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-Recursive:Maybe']);

  Assert.AreEqual(EXIT_CODE_PARAM_NOT_FOUND, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'Usage');
end;

procedure TIsExeSignedParameterTests.InvalidFailModeShowsUsage;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-FailMode:Maybe']);

  Assert.AreEqual(EXIT_CODE_PARAM_NOT_FOUND, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'Usage');
end;

procedure TIsExeSignedParameterTests.MissingDirectory;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('Missing\*.exe')]);

  Assert.AreEqual(EXIT_CODE_PARAM_VALUE_ERROR, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'does not exist');
end;

procedure TIsExeSignedParameterTests.MissingFile;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('Missing.exe')]);

  Assert.AreEqual(EXIT_CODE_PARAM_VALUE_ERROR, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'does not exist');
end;

procedure TIsExeSignedParameterTests.NoFilesMatchThePattern;
begin
  FFiles.Add('Signed.exe', tfkSigned);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('*.dll')]);

  Assert.AreEqual(EXIT_CODE_PARAM_VALUE_ERROR, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'no files match');
end;

procedure TIsExeSignedParameterTests.NoParametersShowsUsage;
begin
  var LResult := RunIsExeSigned([]);

  Assert.AreEqual(EXIT_CODE_PARAM_NOT_FOUND, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'Usage');
end;

procedure TIsExeSignedParameterTests.ParameterErrorWithLogOnly;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('Missing.exe'), '-FailMode:LogOnly']);

  Assert.AreEqual(EXIT_CODE_PARAM_VALUE_ERROR, LResult.ExitCode, LResult.Output);
end;

procedure TIsExeSignedParameterTests.PatternWithoutDirectory;
begin
  var LResult := RunIsExeSigned(['-Files:*.exe']);

  Assert.AreEqual(EXIT_CODE_PARAM_VALUE_ERROR, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'must include the directory');
end;

procedure TIsExeSignedParameterTests.SignCommandWithoutPlaceholder;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Unsigned.exe', tfkUnsigned),
    '-SignCommand:' + FFiles.CreateSignTool(stkSign)]);

  Assert.AreEqual(EXIT_CODE_SIGN_COMMAND_NO_FILE_NAME, LResult.ExitCode, LResult.Output);
  Assert.AreEqual('', FFiles.SignToolLog, 'Sign tool was run');
end;

procedure TIsExeSignedParameterTests.SignFilterWithoutCommand;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Unsigned.exe', tfkUnsigned), '-SignFilter:*']);

  Assert.AreEqual(EXIT_CODE_PARAM_VALUE_ERROR, LResult.ExitCode, LResult.Output);
end;

procedure TIsExeSignedParameterTests.SignTimeoutOutOfRange(const ASeconds: string);
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Unsigned.exe', tfkUnsigned),
    '-SignCommand:' + FFiles.CreateSignTool(stkSign) + ' %filename%', '-SignTimeout:' + ASeconds]);

  // CLPRange, so it is a command line parsing error, like an invalid Boolean value
  Assert.AreEqual(EXIT_CODE_PARAM_NOT_FOUND, LResult.ExitCode, LResult.Output);
  Assert.AreEqual('', FFiles.SignToolLog, 'Sign tool was run');
end;

procedure TIsExeSignedParameterTests.VerboseFalseWritesNoSettings;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-Verbose:False']);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.DoesNotContain(LResult.Output, 'Settings:');
end;

procedure TIsExeSignedParameterTests.VerboseShowsAutoFailModeWithLog;
begin
  var LLogFileName := FFiles.PathOf('Result.xml');

  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-LogFile:' + LLogFileName]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, SettingLine('FailMode', 'LogOnly (Auto)'));
  Assert.Contains(LResult.Output, SettingLine('Log', 'True'));
  Assert.Contains(LResult.Output, SettingLine('LogFile', '"' + LLogFileName + '"'));
end;

procedure TIsExeSignedParameterTests.VerboseShowsExplicitFailMode;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-FailMode:FailOnError',
    '-LogFile:' + FFiles.PathOf('Result.xml')]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, SettingLine('FailMode', 'FailOnError'));
  Assert.DoesNotContain(LResult.Output, '(Auto)');
end;

procedure TIsExeSignedParameterTests.VerboseShowsImpliedSettings;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-VerifySigners:*']);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, SettingLine('Verify', 'True'));
  Assert.Contains(LResult.Output, SettingLine('VerifySigners', '"*"'));
end;

procedure TIsExeSignedParameterTests.VerboseWritesSettingsByDefault;
begin
  var LFileName := FFiles.Add('Signed.exe', tfkSigned);

  var LResult := RunIsExeSigned(['-Files:' + LFileName]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.StartsWith('Settings:', LResult.Output);
  Assert.Contains(LResult.Output, SettingLine('Files', '"' + LFileName + '"'));
  Assert.Contains(LResult.Output, SettingLine('FailMode', 'FailOnError (Auto)'));
  Assert.Contains(LResult.Output, SettingLine('Verify', 'False'));
  Assert.Contains(LResult.Output, SettingLine('SignTimeout', '60'));
  Assert.Contains(LResult.Output, SettingLine('Log', 'False'));
  Assert.Contains(LResult.Output, SettingLine('LogFile', '""'));
end;

procedure TIsExeSignedParameterTests.VerboseWritesSettingsWhenValueIsNotValid;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('Missing.exe')]);

  Assert.AreEqual(EXIT_CODE_PARAM_VALUE_ERROR, LResult.ExitCode, LResult.Output);
  Assert.StartsWith('Settings:', LResult.Output);
  Assert.Contains(LResult.Output, 'does not exist');
end;

end.
