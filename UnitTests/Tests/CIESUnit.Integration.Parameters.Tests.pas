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
    [Test] procedure SignFilterWithoutCommand;
    [Test]
    [TestCase('Zero', '0')]
    [TestCase('Over one day', '86401')]
    procedure SignTimeoutOutOfRange(const ASeconds: string);
    [Test] procedure SignCommandWithoutPlaceholder;
    // FileName and ErrorIfNotSigned, the names before 2026-10, are aliases of Files and FailIfUnsigned
    [Test] procedure OldParameterNamesStillWork;
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
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-FailIfUnsigned:Maybe']);

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

procedure TIsExeSignedParameterTests.OldParameterNamesStillWork;
begin
  var LResult := RunIsExeSigned(['-FileName:' + FFiles.Add('Unsigned.exe', tfkUnsigned), '-ErrorIfNotSigned:False']);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'is NOT Signed');
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

end.
