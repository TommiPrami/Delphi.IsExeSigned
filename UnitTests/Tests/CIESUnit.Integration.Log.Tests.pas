unit CIESUnit.Integration.Log.Tests;

// IsExeSigned.exe run as a separate process: the NUnit XML log file.

interface

uses
  DUnitX.TestFramework, CIESUnit.Tests.Common;

type
  [TestFixture]
  TIsExeSignedLogTests = class(TObject)
  strict private
    FFiles: TTestFiles;
    function CountOf(const AText, ASubText: string): Integer;
    function LogFileName: string;
    function ReadLog(const AFileName: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure NoLogByDefault;
    [Test] procedure LogWritesToApplicationFolder;
    [Test] procedure LogFileWritesLog;
    [Test] procedure LogFileWithoutFileName;
    [Test] procedure LogDirectoryMissing;
    [Test] procedure ExistingLogIsOverwrittenByDefault;
    [Test] procedure ExistingLogWithoutLogOverwrite;
    [Test] procedure LogOnlyWritesErrors;
    [Test] procedure InvalidSignatureFails;
    [Test] procedure LogIsWrittenWhenSignTimeoutStops;
    [Test] procedure SignTimeoutWithLogOnly;
    [Test] procedure NoFilesMatchWithLogOnly;
    // FailMode Auto, the default, is LogOnly when a log is written
    [Test] procedure AutoWithLogIsLogOnly;
  end;

implementation

uses
  System.IOUtils, System.SysUtils, CIESUnit.Consts, CIESUnit.Utils;

{ TIsExeSignedLogTests }

procedure TIsExeSignedLogTests.AutoWithLogIsLogOnly;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Unsigned.exe', tfkUnsigned), '-LogFile:' + LogFileName]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, '* ERROR: "');
  Assert.Contains(ReadLog(LogFileName), 'label="Error"');
end;

procedure TIsExeSignedLogTests.Setup;
begin
  FFiles := TTestFiles.Create;

  ForceDirectories(ExtractFilePath(LogFileName));
end;

procedure TIsExeSignedLogTests.TearDown;
begin
  FFiles.Free;
end;

function TIsExeSignedLogTests.CountOf(const AText, ASubText: string): Integer;
begin
  Result := 0;

  var LIndex := AText.IndexOf(ASubText);

  while LIndex >= 0 do
  begin
    Inc(Result);

    LIndex := AText.IndexOf(ASubText, LIndex + Length(ASubText));
  end;
end;

function TIsExeSignedLogTests.LogFileName: string;
begin
  Result := TPath.Combine(FFiles.Root, 'Log Files\Result.xml');
end;

function TIsExeSignedLogTests.ReadLog(const AFileName: string): string;
begin
  Assert.IsTrue(TFile.Exists(AFileName), 'Log file not written: ' + AFileName);

  Result := TFile.ReadAllText(AFileName, TEncoding.UTF8);
end;

procedure TIsExeSignedLogTests.ExistingLogIsOverwrittenByDefault;
begin
  TFile.WriteAllText(LogFileName, 'Old log');

  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-LogFile:' + LogFileName]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(ReadLog(LogFileName), '<test-run');
end;

procedure TIsExeSignedLogTests.ExistingLogWithoutLogOverwrite;
begin
  TFile.WriteAllText(LogFileName, 'Old log');

  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-LogFile:' + LogFileName,
    '-LogOverwrite:False']);

  Assert.AreEqual(EXIT_CODE_PARAM_VALUE_ERROR, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'LogOverwrite is False');
  Assert.AreEqual('Old log', ReadLog(LogFileName));
end;

procedure TIsExeSignedLogTests.InvalidSignatureFails;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Tampered.exe', tfkTampered), '-Verify:True',
    '-FailMode:FailOnError', '-LogFile:' + LogFileName]);

  Assert.AreEqual(EXIT_CODE_SIGNATURE_NOT_VALID, LResult.ExitCode, LResult.Output);

  var LLog := ReadLog(LogFileName);

  Assert.Contains(LLog, 'result="Failed" total="1" passed="0" failed="1"');
  Assert.Contains(LLog, 'signature is NOT valid');
end;

procedure TIsExeSignedLogTests.LogDirectoryMissing;
begin
  var LMissing := TPath.Combine(FFiles.Root, 'Missing\Result.xml');

  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-LogFile:' + LMissing]);

  Assert.AreEqual(EXIT_CODE_PARAM_VALUE_ERROR, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'does not exist');
  Assert.IsFalse(TFile.Exists(LMissing));
end;

procedure TIsExeSignedLogTests.LogFileWithoutFileName;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned),
    '-LogFile:' + ExtractFilePath(LogFileName)]);

  Assert.AreEqual(EXIT_CODE_PARAM_VALUE_ERROR, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'file name is missing');
end;

procedure TIsExeSignedLogTests.LogFileWritesLog;
var
  LSignerName: string;
begin
  FFiles.Add('Signed.exe', tfkSigned);
  FFiles.Add('Unsigned.exe', tfkUnsigned);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('*.exe'), '-FailMode:FailOnError',
    '-LogFile:' + LogFileName]);

  Assert.AreEqual(EXIT_CODE_NOT_SIGNED, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'Log written to "' + LogFileName + '"');

  var LLog := ReadLog(LogFileName);

  Assert.StartsWith('<?xml version="1.0" encoding="utf-8"?>', LLog);
  Assert.AreEqual(2, CountOf(LLog, '<test-case '), LLog);
  Assert.Contains(LLog, 'name="' + FFiles.PathOf('Signed.exe') + '"');
  Assert.Contains(LLog, 'name="' + FFiles.PathOf('Unsigned.exe') + '"');
  Assert.Contains(LLog, 'result="Failed" total="2" passed="1" failed="1"');
  Assert.Contains(LLog, 'Not signed');

  CIESUnit.Utils.IsExeSigned(SignedSystemFile, LSignerName);

  Assert.Contains(LLog, 'Signed by "' + LSignerName + '"');
end;

procedure TIsExeSignedLogTests.LogIsWrittenWhenSignTimeoutStops;
begin
  FFiles.Add('a.exe', tfkUnsigned);
  FFiles.Add('b.exe', tfkUnsigned);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('*.exe'),
    '-SignCommand:' + FFiles.CreateSignTool(stkHang) + ' %filename%', '-SignTimeout:1', '-FailMode:FailOnError',
    '-LogFile:' + LogFileName]);

  Assert.AreEqual(EXIT_CODE_SIGN_TIMEOUT, LResult.ExitCode, LResult.Output);

  var LLog := ReadLog(LogFileName);

  // Stopped at the first file, which is logged as an error
  Assert.AreEqual(1, CountOf(LLog, '<test-case '), LLog);
  Assert.Contains(LLog, 'label="Error"');
  Assert.Contains(LLog, 'did not finish in 1 seconds');
end;

procedure TIsExeSignedLogTests.LogWritesToApplicationFolder;
begin
  var LExeFileName := FFiles.CopyIsExeSigned;

  var LResult := RunIsExeSigned(LExeFileName, ['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-Log:True']);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(ReadLog(ExtractFilePath(LExeFileName) + LOG_FILE_NAME_DEFAULT), 'result="Passed"');
end;

procedure TIsExeSignedLogTests.NoLogByDefault;
begin
  var LExeFileName := FFiles.CopyIsExeSigned;

  var LResult := RunIsExeSigned(LExeFileName, ['-Files:' + FFiles.Add('Signed.exe', tfkSigned)]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.DoesNotContain(LResult.Output, 'Log written');
  Assert.IsFalse(TFile.Exists(ExtractFilePath(LExeFileName) + LOG_FILE_NAME_DEFAULT));
end;

procedure TIsExeSignedLogTests.LogOnlyWritesErrors;
begin
  FFiles.Add('Signed.exe', tfkSigned);
  FFiles.Add('Tampered.exe', tfkTampered);
  FFiles.Add('Unsigned.exe', tfkUnsigned);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('*.exe'), '-Verify:True', '-FailMode:LogOnly',
    '-LogFile:' + LogFileName]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);

  var LLog := ReadLog(LogFileName);

  Assert.Contains(LLog, 'result="Failed" total="3" passed="1" failed="2"');
  Assert.AreEqual(2, CountOf(LLog, 'label="Error"'), LLog);
  Assert.Contains(LLog, 'Not signed');
  Assert.Contains(LLog, 'signature is NOT valid');
end;

procedure TIsExeSignedLogTests.NoFilesMatchWithLogOnly;
begin
  FFiles.Add('Signed.exe', tfkSigned);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('*.dll'), '-FailMode:LogOnly', '-LogFile:' + LogFileName]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'no files match');

  var LLog := ReadLog(LogFileName);

  Assert.Contains(LLog, 'label="Error"');
  Assert.Contains(LLog, 'no files match');
end;

procedure TIsExeSignedLogTests.SignTimeoutWithLogOnly;
begin
  FFiles.Add('a.exe', tfkUnsigned);
  FFiles.Add('b.exe', tfkUnsigned);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.PathOf('*.exe'),
    '-SignCommand:' + FFiles.CreateSignTool(stkHang) + ' %filename%', '-SignTimeout:1', '-FailMode:LogOnly',
    '-LogFile:' + LogFileName]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);

  var LLog := ReadLog(LogFileName);

  // Still stopped at the first file, as ContinueOnSignTimeout is False
  Assert.AreEqual(1, CountOf(LLog, '<test-case '), LLog);
  Assert.Contains(LLog, 'label="Error"');
end;

end.
