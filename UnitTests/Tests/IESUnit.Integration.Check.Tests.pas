unit IESUnit.Integration.Check.Tests;

// IsExeSigned.exe run as a separate process: checking signed, unsigned and tampered files.

interface

uses
  DUnitX.TestFramework, IESUnit.Tests.Common;

type
  [TestFixture]
  TIsExeSignedCheckTests = class(TObject)
  strict private
    FFiles: TTestFiles;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure SignedFile;
    [Test] procedure UnsignedFile;
    [Test] procedure UnsignedFileWithLogOnly;
    [Test] procedure FileNameWithBracketsAndHashIsNotAPattern;
    [Test] procedure PatternIsCaseInsensitive;
    [Test] procedure PatternWithoutRecurseSkipsSubDirs;
    [Test] procedure SummaryCountsUnsignedFiles;

    [Test] procedure TamperedFileIsNotCheckedByDefault;
    [Test] procedure TamperedFileWithVerify;
    [Test] procedure TamperedFileWithVerifyAndLogOnly;
    [Test] procedure SignerFilterNotMatchingSkipsCheck;
    [Test] procedure SignerFilterMatchingChecks;
    [Test] procedure UnsignedTakesPrecedenceOverInvalidSignature;
  end;

implementation

uses
  System.SysUtils, IESUnit.Consts, IESUnit.Utils;

{ TIsExeSignedCheckTests }

procedure TIsExeSignedCheckTests.Setup;
begin
  FFiles := TTestFiles.Create;
end;

procedure TIsExeSignedCheckTests.TearDown;
begin
  FFiles.Free;
end;

procedure TIsExeSignedCheckTests.FileNameWithBracketsAndHashIsNotAPattern;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('App[x64] #2.exe', tfkSigned)]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'App[x64] #2.exe" - is Signed by');
end;

procedure TIsExeSignedCheckTests.PatternIsCaseInsensitive;
begin
  FFiles.Add('a.exe', tfkSigned);
  FFiles.Add('B.Exe', tfkSigned);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('*.EXE')]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, '2 files found');
end;

procedure TIsExeSignedCheckTests.PatternWithoutRecurseSkipsSubDirs;
begin
  FFiles.Add('Signed.exe', tfkSigned);
  FFiles.Add('Sub\Unsigned.exe', tfkUnsigned);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('*.exe'), '-Recursive:False']);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.DoesNotContain(LResult.Output, 'Unsigned.exe');
end;

procedure TIsExeSignedCheckTests.SignedFile;
var
  LSignerName: string;
begin
  IsExeSigned(SignedSystemFile, LSignerName);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned)]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'is Signed by "' + LSignerName + '"');
end;

procedure TIsExeSignedCheckTests.SignerFilterMatchingChecks;
var
  LSignerName: string;
begin
  IsExeSigned(SignedSystemFile, LSignerName);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Tampered.exe', tfkTampered),
    '-VerifySigners:' + LSignerName.ToUpper]);

  Assert.AreEqual(EXIT_CODE_SIGNATURE_NOT_VALID, LResult.ExitCode, LResult.Output);
end;

procedure TIsExeSignedCheckTests.SignerFilterNotMatchingSkipsCheck;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Tampered.exe', tfkTampered),
    '-VerifySigners:*No Such Signer*;Other*']);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.DoesNotContain(LResult.Output, 'signature is');
end;

procedure TIsExeSignedCheckTests.SummaryCountsUnsignedFiles;
begin
  FFiles.Add('a.exe', tfkSigned);
  FFiles.Add('b.exe', tfkSigned);
  FFiles.Add('c.exe', tfkUnsigned);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('*.exe')]);

  Assert.AreEqual(EXIT_CODE_NOT_SIGNED, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, '3 file(s) checked, 1 of them unsigned.');
end;

procedure TIsExeSignedCheckTests.TamperedFileIsNotCheckedByDefault;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Tampered.exe', tfkTampered)]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
end;

procedure TIsExeSignedCheckTests.TamperedFileWithVerify;
begin
  FFiles.Add('Signed.exe', tfkSigned);
  FFiles.Add('Tampered.exe', tfkTampered);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('*.exe'), '-Verify:True']);

  Assert.AreEqual(EXIT_CODE_SIGNATURE_NOT_VALID, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'Signed.exe" - is Signed by');
  Assert.Contains(LResult.Output, 'signature is valid');
  Assert.Contains(LResult.Output, '! "' + FFiles.PathOf('Tampered.exe'));
  // TRUST_E_BAD_DIGEST
  Assert.Contains(LResult.Output, '0x80096010');
  Assert.Contains(LResult.Output, '1 with invalid signature');
end;

procedure TIsExeSignedCheckTests.TamperedFileWithVerifyAndLogOnly;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Tampered.exe', tfkTampered), '-Verify:True',
    '-FailMode:LogOnly']);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, '! ERROR: "' + FFiles.PathOf('Tampered.exe'));
  Assert.Contains(LResult.Output, 'signature is NOT valid');
end;

procedure TIsExeSignedCheckTests.UnsignedFile;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Unsigned.exe', tfkUnsigned)]);

  Assert.AreEqual(EXIT_CODE_NOT_SIGNED, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'is NOT Signed');
end;

procedure TIsExeSignedCheckTests.UnsignedFileWithLogOnly;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Unsigned.exe', tfkUnsigned), '-FailMode:LogOnly']);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, '* ERROR: "' + FFiles.PathOf('Unsigned.exe') + '" - is NOT Signed');
end;

procedure TIsExeSignedCheckTests.UnsignedTakesPrecedenceOverInvalidSignature;
begin
  FFiles.Add('Tampered.exe', tfkTampered);
  FFiles.Add('Unsigned.exe', tfkUnsigned);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('*.exe'), '-Verify:True']);

  Assert.AreEqual(EXIT_CODE_NOT_SIGNED, LResult.ExitCode, LResult.Output);
end;

end.
