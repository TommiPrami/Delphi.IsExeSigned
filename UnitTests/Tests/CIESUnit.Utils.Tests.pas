unit CIESUnit.Utils.Tests;

// CIESUnit.Utils called directly, in this process.

interface

uses
  DUnitX.TestFramework, CIESUnit.Tests.Common;

type
  [TestFixture]
  TCIESUtilsTests = class(TObject)
  strict private
    FFiles: TTestFiles;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure IsExeSignedReturnsSignerName;
    [Test] procedure IsExeSignedIsFalseForUnsignedFile;
    [Test] procedure IsExeSignedIsFalseForMissingFile;
    [Test] procedure IsSignatureValidForSignedFile;
    [Test] procedure IsSignatureValidIsFalseForTamperedFile;

    [Test] procedure GetFilesReturnsPlainFileNameAsIs;
    [Test] procedure GetFilesMatchesFileNameOnly;
    [Test] procedure GetFilesIsCaseInsensitive;
    [Test] procedure GetFilesMatchesAnyOfThePatterns;
    [Test] procedure GetFilesWithoutRecurseSkipsSubDirs;

    [Test] procedure RunSignFileCommandPassesQuotedFileName;
    [Test] procedure RunSignFileCommandDoesNotQuoteTwice;
    [Test] procedure RunSignFileCommandReturnsExitCode;
    [Test] procedure RunSignFileCommandTimeoutStopsProcessTree;
  end;

implementation

uses
  Winapi.Windows, System.IOUtils, System.SysUtils, CIESUnit.Utils;

{ TCIESUtilsTests }

procedure TCIESUtilsTests.Setup;
begin
  FFiles := TTestFiles.Create;
end;

procedure TCIESUtilsTests.TearDown;
begin
  FFiles.Free;
end;

procedure TCIESUtilsTests.GetFilesIsCaseInsensitive;
begin
  FFiles.Add('a.exe', tfkUnsigned);
  FFiles.Add('B.Exe', tfkUnsigned);

  Assert.AreEqual(2, Integer(Length(GetFiles(FFiles.PathOf('*.EXE'), True))));
end;

procedure TCIESUtilsTests.GetFilesMatchesAnyOfThePatterns;
begin
  FFiles.Add('a.exe', tfkUnsigned);
  FFiles.Add('b.dll', tfkUnsigned);
  FFiles.Add('c.txt', tfkUnsigned);

  Assert.AreEqual(2, Integer(Length(GetFiles(FFiles.PathOf('*.exe;*.dll'), True))));
end;

procedure TCIESUtilsTests.GetFilesMatchesFileNameOnly;
begin
  var LExpected := FFiles.Add('Sub\Sx12.exe', tfkUnsigned);
  // 'S*' would match these too, if the pattern was matched against the path after the directory
  FFiles.Add('Sub\x12.exe', tfkUnsigned);
  FFiles.Add('Sub\Sx1.exe', tfkUnsigned);

  var LFiles := GetFiles(FFiles.PathOf('S*<##>.exe'), True);

  Assert.AreEqual(1, Integer(Length(LFiles)));
  Assert.AreEqual(LExpected, LFiles[0]);
end;

procedure TCIESUtilsTests.GetFilesReturnsPlainFileNameAsIs;
begin
  // '[', ']' and '#' are allowed in file names, so this is not a pattern
  var LFileName := FFiles.PathOf('App[x64] #2.exe');

  var LFiles := GetFiles(LFileName, True);

  Assert.AreEqual(1, Integer(Length(LFiles)));
  Assert.AreEqual(LFileName, LFiles[0]);
end;

procedure TCIESUtilsTests.GetFilesWithoutRecurseSkipsSubDirs;
begin
  FFiles.Add('a.exe', tfkUnsigned);
  FFiles.Add('Sub\b.exe', tfkUnsigned);

  Assert.AreEqual(1, Integer(Length(GetFiles(FFiles.PathOf('*.exe'), False))));
  Assert.AreEqual(2, Integer(Length(GetFiles(FFiles.PathOf('*.exe'), True))));
end;

procedure TCIESUtilsTests.IsExeSignedIsFalseForMissingFile;
var
  LSignerName: string;
begin
  Assert.IsFalse(IsExeSigned(FFiles.PathOf('Missing.exe'), LSignerName));
  Assert.AreEqual('', LSignerName);
end;

procedure TCIESUtilsTests.IsExeSignedIsFalseForUnsignedFile;
var
  LSignerName: string;
begin
  Assert.IsFalse(IsExeSigned(FFiles.Add('Unsigned.exe', tfkUnsigned), LSignerName));
  Assert.AreEqual('', LSignerName);
end;

procedure TCIESUtilsTests.IsExeSignedReturnsSignerName;
var
  LExpectedSignerName: string;
  LSignerName: string;
begin
  IsExeSigned(SignedSystemFile, LExpectedSignerName);

  Assert.IsTrue(IsExeSigned(FFiles.Add('Signed.exe', tfkSigned), LSignerName));
  Assert.IsNotEmpty(LSignerName);
  Assert.AreEqual(LExpectedSignerName, LSignerName);
end;

procedure TCIESUtilsTests.IsSignatureValidForSignedFile;
var
  LErrorMessage: string;
begin
  Assert.IsTrue(IsSignatureValid(FFiles.Add('Signed.exe', tfkSigned), LErrorMessage), LErrorMessage);
  Assert.AreEqual('', LErrorMessage);
end;

procedure TCIESUtilsTests.IsSignatureValidIsFalseForTamperedFile;
var
  LErrorMessage: string;
  LSignerName: string;
begin
  var LFileName := FFiles.Add('Tampered.exe', tfkTampered);

  // Still signed, the signature just does not match the content anymore
  Assert.IsTrue(IsExeSigned(LFileName, LSignerName));
  Assert.IsFalse(IsSignatureValid(LFileName, LErrorMessage));
  // TRUST_E_BAD_DIGEST
  Assert.Contains(LErrorMessage, '0x80096010');
end;

procedure TCIESUtilsTests.RunSignFileCommandDoesNotQuoteTwice;
var
  LExitCode: Cardinal;
begin
  var LFileName := FFiles.Add('Unsigned.exe', tfkUnsigned);
  var LTool := FFiles.CreateSignTool(stkSign);

  // Placeholder already quoted, and in another case
  Assert.IsTrue(RunSignFileCommand(LTool + ' "%FileName%"', LFileName, 30, LExitCode));

  Assert.AreEqual(0, Integer(LExitCode));
  Assert.AreEqual('"' + LFileName + '"', FFiles.SignToolLog.Trim);
end;

procedure TCIESUtilsTests.RunSignFileCommandPassesQuotedFileName;
var
  LExitCode: Cardinal;
  LSignerName: string;
begin
  var LFileName := FFiles.Add('Sub Dir\Unsigned.exe', tfkUnsigned);

  Assert.IsTrue(RunSignFileCommand(FFiles.CreateSignTool(stkSign) + ' %filename%', LFileName, 30, LExitCode));

  Assert.AreEqual(0, Integer(LExitCode));
  Assert.AreEqual('"' + LFileName + '"', FFiles.SignToolLog.Trim);
  Assert.IsTrue(IsExeSigned(LFileName, LSignerName), 'Sign tool did not sign the file');
end;

procedure TCIESUtilsTests.RunSignFileCommandReturnsExitCode;
var
  LExitCode: Cardinal;
begin
  var LFileName := FFiles.Add('Unsigned.exe', tfkUnsigned);

  Assert.IsTrue(RunSignFileCommand(FFiles.CreateSignTool(stkFail) + ' %filename%', LFileName, 30, LExitCode));

  Assert.AreEqual(7, Integer(LExitCode));
end;

procedure TCIESUtilsTests.RunSignFileCommandTimeoutStopsProcessTree;
var
  LExitCode: Cardinal;
begin
  var LFileName := FFiles.Add('Unsigned.exe', tfkUnsigned);

  Assert.IsFalse(RunSignFileCommand(FFiles.CreateSignTool(stkHang) + ' %filename%', LFileName, 1, LExitCode),
    'Timeout not reported');

  // The hanging grandchild would write its marker about 3 seconds after it started, if it was left running
  Sleep(4500);

  Assert.IsFalse(TFile.Exists(FFiles.HangMarker), 'Sign command''s child process was left running after the timeout');
end;

end.
