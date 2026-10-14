unit CIESUnit.Integration.Parameters.Tests;

// IsExeSigned.exe run as a separate process: invalid command lines and their exit codes.

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
    [Test] procedure MissingFile;
    [Test] procedure PatternWithoutDirectory;
    [Test] procedure MissingDirectory;
    [Test] procedure NoFilesMatchThePattern;
    [Test] procedure SignFileWildCardWithoutCommand;
    [Test]
    [TestCase('Zero', '0')]
    [TestCase('Over one day', '86401')]
    procedure SignTimeoutOutOfRange(const ASeconds: string);
    [Test] procedure SignCommandWithoutPlaceholder;
  end;

implementation

uses
  CIESUnit.Consts;

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
  var LResult := RunIsExeSigned(['-FileName:' + FFiles.Add('Signed.exe', tfkSigned), '-ErrorIfNotSigned:Maybe']);

  Assert.AreEqual(EXIT_CODE_PARAM_NOT_FOUND, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'Usage');
end;

procedure TIsExeSignedParameterTests.MissingDirectory;
begin
  var LResult := RunIsExeSigned(['-FileName:' + FFiles.PathOf('Missing\*.exe')]);

  Assert.AreEqual(EXIT_CODE_PARAM_VALUE_ERROR, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'does not exist');
end;

procedure TIsExeSignedParameterTests.MissingFile;
begin
  var LResult := RunIsExeSigned(['-FileName:' + FFiles.PathOf('Missing.exe')]);

  Assert.AreEqual(EXIT_CODE_PARAM_VALUE_ERROR, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'does not exist');
end;

procedure TIsExeSignedParameterTests.NoFilesMatchThePattern;
begin
  FFiles.Add('Signed.exe', tfkSigned);

  var LResult := RunIsExeSigned(['-FileName:' + FFiles.PathOf('*.dll')]);

  Assert.AreEqual(EXIT_CODE_PARAM_VALUE_ERROR, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'no files match');
end;

procedure TIsExeSignedParameterTests.NoParametersShowsUsage;
begin
  var LResult := RunIsExeSigned([]);

  Assert.AreEqual(EXIT_CODE_PARAM_NOT_FOUND, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'Usage');
end;

procedure TIsExeSignedParameterTests.PatternWithoutDirectory;
begin
  var LResult := RunIsExeSigned(['-FileName:*.exe']);

  Assert.AreEqual(EXIT_CODE_PARAM_VALUE_ERROR, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'must include the directory');
end;

procedure TIsExeSignedParameterTests.SignCommandWithoutPlaceholder;
begin
  var LResult := RunIsExeSigned(['-FileName:' + FFiles.Add('Unsigned.exe', tfkUnsigned),
    '-SignFileCommandLine:' + FFiles.CreateSignTool(stkSign)]);

  Assert.AreEqual(EXIT_CODE_SIGN_COMMAND_NO_FILE_NAME, LResult.ExitCode, LResult.Output);
  Assert.AreEqual('', FFiles.SignToolLog, 'Sign tool was run');
end;

procedure TIsExeSignedParameterTests.SignFileWildCardWithoutCommand;
begin
  var LResult := RunIsExeSigned(['-FileName:' + FFiles.Add('Unsigned.exe', tfkUnsigned), '-SignFileWildCard:*']);

  Assert.AreEqual(EXIT_CODE_PARAM_VALUE_ERROR, LResult.ExitCode, LResult.Output);
end;

procedure TIsExeSignedParameterTests.SignTimeoutOutOfRange(const ASeconds: string);
begin
  var LResult := RunIsExeSigned(['-FileName:' + FFiles.Add('Unsigned.exe', tfkUnsigned),
    '-SignFileCommandLine:' + FFiles.CreateSignTool(stkSign) + ' %filename%', '-SignTimeout:' + ASeconds]);

  Assert.AreEqual(EXIT_CODE_PARAM_VALUE_ERROR, LResult.ExitCode, LResult.Output);
  Assert.AreEqual('', FFiles.SignToolLog, 'Sign tool was run');
end;

end.
