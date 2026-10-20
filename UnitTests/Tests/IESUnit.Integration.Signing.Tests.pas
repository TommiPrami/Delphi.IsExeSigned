unit IESUnit.Integration.Signing.Tests;

// IsExeSigned.exe run as a separate process: signing unsigned files with a (fake) sign command.

interface

uses
  DUnitX.TestFramework, IESUnit.Tests.Common;

type
  [TestFixture]
  TIsExeSignedSigningTests = class(TObject)
  strict private
    FFiles: TTestFiles;
    function IsSigned(const AFileName: string): Boolean;
    function SignCommand(const AKind: TSignToolKind): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure SignsAllUnsignedFiles;
    [Test] procedure AlreadySignedFileIsNotSigned;
    [Test] procedure SignFilterSignsOnlyMatchingFiles;
    [Test] procedure FailingSignCommandLeavesFileUnsigned;
    [Test] procedure SigningThatGivesInvalidSignature;
    [Test] procedure SignTimeoutStops;
    [Test] procedure ContinueOnSignTimeoutChecksAllFiles;
  end;

implementation

uses
  System.SysUtils, IESUnit.Consts, IESUnit.Utils;

{ TIsExeSignedSigningTests }

procedure TIsExeSignedSigningTests.Setup;
begin
  FFiles := TTestFiles.Create;
end;

procedure TIsExeSignedSigningTests.TearDown;
begin
  FFiles.Free;
end;

function TIsExeSignedSigningTests.IsSigned(const AFileName: string): Boolean;
var
  LSignerName: string;
begin
  Result := IsExeSigned(AFileName, LSignerName);
end;

function TIsExeSignedSigningTests.SignCommand(const AKind: TSignToolKind): string;
begin
  Result := '-SignCommand:' + FFiles.CreateSignTool(AKind) + ' %filename%';
end;

procedure TIsExeSignedSigningTests.AlreadySignedFileIsNotSigned;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), SignCommand(stkSign)]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.AreEqual('', FFiles.SignToolLog, 'Sign tool was run');
end;

procedure TIsExeSignedSigningTests.ContinueOnSignTimeoutChecksAllFiles;
begin
  FFiles.Add('a.exe', tfkUnsigned);
  FFiles.Add('b.exe', tfkUnsigned);
  FFiles.Add('c.exe', tfkSigned);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('*.exe'), SignCommand(stkHang), '-SignTimeout:1',
    '-ContinueOnSignTimeout:True']);

  Assert.AreEqual(EXIT_CODE_NOT_SIGNED, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, '3 file(s) checked, 2 of them unsigned, 0 signed now, 2 sign command timeout(s)');
end;

procedure TIsExeSignedSigningTests.FailingSignCommandLeavesFileUnsigned;
begin
  var LFileName := FFiles.Add('Unsigned.exe', tfkUnsigned);

  var LResult := RunIsExeSigned(['-Files:' + LFileName, SignCommand(stkFail)]);

  Assert.AreEqual(EXIT_CODE_NOT_SIGNED, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'Sign command returned exit code 7');
  Assert.IsFalse(IsSigned(LFileName));
end;

procedure TIsExeSignedSigningTests.SignFilterSignsOnlyMatchingFiles;
begin
  var LSignMe := FFiles.Add('Sign Me\a.dll', tfkUnsigned);
  var LLeaveMe := FFiles.Add('Leave Me\b.dll', tfkUnsigned);

  // Matched against the full path
  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('*.dll'), SignCommand(stkSign),
    '-SignFilter:*\Sign Me\*;*\Nothing\*']);

  Assert.AreEqual(EXIT_CODE_NOT_SIGNED, LResult.ExitCode, LResult.Output);
  Assert.IsTrue(IsSigned(LSignMe), 'Matching file not signed');
  Assert.IsFalse(IsSigned(LLeaveMe), 'Not matching file signed');
end;

procedure TIsExeSignedSigningTests.SignTimeoutStops;
begin
  FFiles.Add('a.exe', tfkUnsigned);
  FFiles.Add('b.exe', tfkUnsigned);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('*.exe'), SignCommand(stkHang), '-SignTimeout:1']);

  Assert.AreEqual(EXIT_CODE_SIGN_TIMEOUT, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'did not finish in 1 seconds');
  // Stopped at the first file
  Assert.AreEqual(1, Integer(Length(FFiles.SignToolLog.Trim.Split([sLineBreak]))), FFiles.SignToolLog);
end;

procedure TIsExeSignedSigningTests.SigningThatGivesInvalidSignature;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Unsigned.exe', tfkUnsigned), SignCommand(stkSignInvalid)]);

  // Just signed files are always checked
  Assert.AreEqual(EXIT_CODE_SIGNATURE_NOT_VALID, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'is Signed now by');
  Assert.Contains(LResult.Output, 'signature is NOT valid');
end;

procedure TIsExeSignedSigningTests.SignsAllUnsignedFiles;
begin
  var LFirst := FFiles.Add('a.exe', tfkUnsigned);
  var LSecond := FFiles.Add('Sub Dir\b.dll', tfkUnsigned);
  FFiles.Add('c.exe', tfkSigned);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('*.exe;*.dll'), SignCommand(stkSign)]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, '3 file(s) checked, 0 of them unsigned, 2 signed now, 0 with invalid signature.');
  Assert.IsTrue(IsSigned(LFirst));
  Assert.IsTrue(IsSigned(LSecond));
end;

end.
