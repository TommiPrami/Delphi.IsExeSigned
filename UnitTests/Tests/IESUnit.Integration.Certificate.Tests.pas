unit IESUnit.Integration.Certificate.Tests;

// IsExeSigned.exe run as a separate process: expiration of the signing certificate. The limits are set relative to the
// expiration of the test files' certificate (a Windows file's), so the tests do not depend on when they run.

interface

uses
  DUnitX.TestFramework, IESUnit.Tests.Common;

type
  [TestFixture]
  TIsExeSignedCertificateTests = class(TObject)
  strict private
    FDaysLeft: Integer;
    FFiles: TTestFiles;
    FSignerName: string;
    function DaysArgument(const AName: string; const ADays: Integer): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure PassesWhenNotExpiringSoon;
    [Test] procedure WarningWithinWarningDays;
    [Test] procedure ErrorWithinErrorDays;
    [Test] procedure ErrorWithLogOnlyIsOnlyReported;
    [Test] procedure SignedNowFileIsChecked;
    [Test] procedure NotCheckedWithVerifyOnly;
    [Test] procedure NotCheckedForOtherSigners;
    [Test] procedure ZeroTurnsChecksOff;
    [Test] procedure ErrorGreaterThanWarning;
    [Test] procedure NegativeDays;
  end;

implementation

uses
  System.IOUtils, System.Math, System.SysUtils, IESUnit.Consts, IESUnit.Utils;

const
  // The settings Verbose writes have the parameter names, which have "Certificate" too
  NOT_VERBOSE = '-Verbose:False';

{ TIsExeSignedCertificateTests }

procedure TIsExeSignedCertificateTests.Setup;
var
  LSignatureInfo: TSignatureInfo;
begin
  FFiles := TTestFiles.Create;

  GetSignatureInfo(SignedSystemFile, LSignatureInfo);

  FDaysLeft := CertificateDaysLeft(LSignatureInfo.CertificateExpiration);
  FSignerName := LSignatureInfo.SignerName;
end;

procedure TIsExeSignedCertificateTests.TearDown;
begin
  FFiles.Free;
end;

function TIsExeSignedCertificateTests.DaysArgument(const AName: string; const ADays: Integer): string;
begin
  Result := '-' + AName + ':' + ADays.ToString;
end;

procedure TIsExeSignedCertificateTests.ErrorGreaterThanWarning;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned),
    DaysArgument(PARAM_CERTIFICATE_EXPIRATION_WARNING, 10), DaysArgument(PARAM_CERTIFICATE_EXPIRATION_ERROR, 20)]);

  Assert.AreEqual(EXIT_CODE_PARAM_VALUE_ERROR, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'must not be greater than');
end;

procedure TIsExeSignedCertificateTests.ErrorWithinErrorDays;
begin
  // Reached also when the certificate has already expired
  var LDays := Max(FDaysLeft + 1, 1);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-VerifySigners:' + FSignerName,
    DaysArgument(PARAM_CERTIFICATE_EXPIRATION_WARNING, LDays), DaysArgument(PARAM_CERTIFICATE_EXPIRATION_ERROR, LDays)]);

  Assert.AreEqual(EXIT_CODE_CERTIFICATE_EXPIRING, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, '! "');
  Assert.Contains(LResult.Output, 'signature is valid, but the certificate');
end;

procedure TIsExeSignedCertificateTests.ErrorWithLogOnlyIsOnlyReported;
begin
  var LDays := Max(FDaysLeft + 1, 1);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-VerifySigners:' + FSignerName,
    DaysArgument(PARAM_CERTIFICATE_EXPIRATION_WARNING, LDays), DaysArgument(PARAM_CERTIFICATE_EXPIRATION_ERROR, LDays),
    '-FailMode:LogOnly']);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, '! ERROR: "');
end;

procedure TIsExeSignedCertificateTests.NegativeDays;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned),
    DaysArgument(PARAM_CERTIFICATE_EXPIRATION_WARNING, -1)]);

  // CLPRange, a command line parsing error
  Assert.AreEqual(EXIT_CODE_PARAM_NOT_FOUND, LResult.ExitCode, LResult.Output);
end;

procedure TIsExeSignedCertificateTests.NotCheckedForOtherSigners;
begin
  var LDays := Max(FDaysLeft + 1, 1);

  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-VerifySigners:*No Such Signer*',
    DaysArgument(PARAM_CERTIFICATE_EXPIRATION_WARNING, LDays), DaysArgument(PARAM_CERTIFICATE_EXPIRATION_ERROR, LDays),
    NOT_VERBOSE]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.DoesNotContain(LResult.Output, 'certificate');
end;

procedure TIsExeSignedCertificateTests.NotCheckedWithVerifyOnly;
begin
  var LDays := Max(FDaysLeft + 1, 1);

  // Without VerifySigners the files are not known to be our own, e.g. timestamped redistributables stay valid after
  // their certificate expires
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-Verify:True',
    DaysArgument(PARAM_CERTIFICATE_EXPIRATION_WARNING, LDays), DaysArgument(PARAM_CERTIFICATE_EXPIRATION_ERROR, LDays),
    NOT_VERBOSE]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'signature is valid');
  Assert.DoesNotContain(LResult.Output, 'certificate');
end;

procedure TIsExeSignedCertificateTests.PassesWhenNotExpiringSoon;
begin
  if FDaysLeft < 2 then
    Assert.Pass('Test file''s certificate expires in ' + FDaysLeft.ToString + ' days, a passing check can not be tested');

  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-VerifySigners:' + FSignerName,
    DaysArgument(PARAM_CERTIFICATE_EXPIRATION_WARNING, FDaysLeft - 1), DaysArgument(PARAM_CERTIFICATE_EXPIRATION_ERROR, 0)]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'signature is valid, certificate valid until');
end;

procedure TIsExeSignedCertificateTests.SignedNowFileIsChecked;
begin
  var LDays := Max(FDaysLeft + 1, 1);

  // No VerifySigners: a file signed now is our own anyway
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Unsigned.exe', tfkUnsigned),
    '-SignCommand:' + FFiles.CreateSignTool(stkSign) + ' %filename%',
    DaysArgument(PARAM_CERTIFICATE_EXPIRATION_WARNING, LDays), DaysArgument(PARAM_CERTIFICATE_EXPIRATION_ERROR, LDays)]);

  Assert.AreEqual(EXIT_CODE_CERTIFICATE_EXPIRING, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'is Signed now by');
  Assert.Contains(LResult.Output, 'but the certificate');
end;

procedure TIsExeSignedCertificateTests.WarningWithinWarningDays;
begin
  var LLogFileName := FFiles.PathOf('Result.xml');

  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-VerifySigners:' + FSignerName,
    DaysArgument(PARAM_CERTIFICATE_EXPIRATION_WARNING, Max(FDaysLeft + 1, 1)), DaysArgument(PARAM_CERTIFICATE_EXPIRATION_ERROR, 0),
    '-LogFile:' + LLogFileName, '-FailMode:FailOnError']);

  // A warning does not change the exit code
  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'signature is valid - WARNING: certificate');
  Assert.Contains(TFile.ReadAllText(LLogFileName, TEncoding.UTF8), 'result="Warning"');
end;

procedure TIsExeSignedCertificateTests.ZeroTurnsChecksOff;
begin
  var LResult := RunIsExeSigned(['-Files:' + FFiles.Add('Signed.exe', tfkSigned), '-VerifySigners:' + FSignerName,
    DaysArgument(PARAM_CERTIFICATE_EXPIRATION_WARNING, 0), DaysArgument(PARAM_CERTIFICATE_EXPIRATION_ERROR, 0), NOT_VERBOSE]);

  Assert.AreEqual(0, LResult.ExitCode, LResult.Output);
  Assert.Contains(LResult.Output, 'signature is valid');
  Assert.DoesNotContain(LResult.Output, 'certificate');
end;

end.
