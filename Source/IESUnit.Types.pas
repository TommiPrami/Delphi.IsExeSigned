unit IESUnit.Types;

interface

uses
  Winapi.Windows, System.Classes, Delphi.CommandLineParser, IESUnit.Consts;

type
  // Auto: LogOnly if a log is written, otherwise FailOnError. FailOnError: any error sets its exit code. LogOnly: errors
  // are only reported, as errors on the console and in the log, the exit code is not set
  TFailMode = (Auto, FailOnError, LogOnly);

  TCommandLineParameters = class(TObject)
  strict private
    FFiles: string;
    FFailMode: TFailMode;
    FRecursive: Boolean;
    FVerify: Boolean;
    FVerifySigners: string;
    FCertificateExpirationWarning: Integer;
    FCertificateExpirationError: Integer;
    FSignCommand: string;
    FSignFilter: string;
    FSignTimeout: Integer;
    FContinueOnSignTimeout: Boolean;
    FLog: Boolean;
    FLogFile: string;
    FLogOverwrite: Boolean;
    FVerbose: Boolean;
  public
    // Full path of the NUnit XML log file to write, '' when no log is written: LogFile if given, otherwise
    // LOG_FILE_NAME_DEFAULT in the application folder if Log is True
    function GetLogFileName: string;
    // FailMode with Auto resolved, never Auto
    function GetEffectiveFailMode: TFailMode;
    // Verify, or VerifySigners given
    function GetEffectiveVerify: Boolean;

    [CLPLongName('Files'),  CLPDescription('File, or directory and patterns separated by ";"', '<file|dir\pattern[;pattern]>'), CLPDefault(''), CLPRequired]
    property Files: string read FFiles write FFiles;

    [CLPLongName('FailMode'), CLPDescription('Auto: LogOnly if a log is written, otherwise FailOnError. FailOnError: return an exit code on any error, e.g. [1] if a file is not signed. LogOnly: only report the errors, as errors in the log too, exit code [0]', '<Auto|FailOnError|LogOnly>'), CLPDefault('Auto')]
    property FailMode: TFailMode read FFailMode write FFailMode;

    [CLPLongName('Recursive'), CLPDescription('Search the sub directories too, when Files has patterns', '<True|False>'), CLPDefault('True')]
    property Recursive: Boolean read FRecursive write FRecursive;

    [CLPLongName('Verify'), CLPDescription('Verify the signatures, return exit code [5] if one is not valid', '<True|False>'), CLPDefault('False')]
    property Verify: Boolean read FVerify write FVerify;

    [CLPLongName('VerifySigners'), CLPDescription('Verify only the signatures of matching signers, implies Verify', '<*Signer*[;Signer*]>'), CLPDefault('')]
    property VerifySigners: string read FVerifySigners write FVerifySigners;

    [CLPLongName('CertificateExpirationWarning'), CLPDescription('Warn when the signing certificate expires in this many days or less. Checked for files signed now, and for files of the VerifySigners signers. 0 = off', '<0..3650>'), CLPDefault('60'), CLPRange(0, CERTIFICATE_EXPIRATION_DAYS_MAX)]
    property CertificateExpirationWarning: Integer read FCertificateExpirationWarning write FCertificateExpirationWarning;

    [CLPLongName('CertificateExpirationError'), CLPDescription('Error when the signing certificate expires in this many days or less, return exit code [8]. Checked like CertificateExpirationWarning. 0 = off', '<0..3650>'), CLPDefault('14'), CLPRange(0, CERTIFICATE_EXPIRATION_DAYS_MAX)]
    property CertificateExpirationError: Integer read FCertificateExpirationError write FCertificateExpirationError;

    [CLPLongName('SignCommand'), CLPDescription('Command to sign unsigned files with, %filename% is replaced with the file name. Return exit code [6] if %filename% is missing', '<C:\SignFile.bat %filename%>'), CLPDefault('')]
    property SignCommand: string read FSignCommand write FSignCommand;

    [CLPLongName('SignFilter'), CLPDescription('Sign only unsigned files whose full path matches, all unsigned files if not given', '<*\Dir\*.dll[;*\Other\*]>'), CLPDefault('')]
    property SignFilter: string read FSignFilter write FSignFilter;

    [CLPLongName('SignTimeout'), CLPDescription('Seconds to wait for the sign command, then it is stopped', '<1..86400>'), CLPDefault('60'), CLPRange(1, SIGN_TIMEOUT_MAX)]
    property SignTimeout: Integer read FSignTimeout write FSignTimeout;

    [CLPLongName('ContinueOnSignTimeout'), CLPDescription('Continue with the next file when the sign command times out, otherwise stop and return exit code [7]', '<True|False>'), CLPDefault('False')]
    property ContinueOnSignTimeout: Boolean read FContinueOnSignTimeout write FContinueOnSignTimeout;

    [CLPLongName('Log'), CLPDescription('Write NUnit XML log, to LogFile or to IsExeSigned.xml in the application folder', '<True|False>'), CLPDefault('False')]
    property Log: Boolean read FLog write FLog;

    [CLPLongName('LogFile'), CLPDescription('NUnit XML log file, implies Log. The directory must exist', '<path\filename.xml>'), CLPDefault('')]
    property LogFile: string read FLogFile write FLogFile;

    [CLPLongName('LogOverwrite'), CLPDescription('Overwrite an existing log file, if False and the log file exists, return exit code [3]', '<True|False>'), CLPDefault('True')]
    property LogOverwrite: Boolean read FLogOverwrite write FLogOverwrite;

    [CLPLongName('Verbose'), CLPDescription('Write the effective settings before anything else is done', '<True|False>'), CLPDefault('True')]
    property Verbose: Boolean read FVerbose write FVerbose;
  end;

{
  Types, Consts and WinApi declarations.
}

const
  CERT_QUERY_OBJECT_FILE = $00000001;
  CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED_EMBED = $00000400;
  CERT_QUERY_FORMAT_FLAG_BINARY = $00000002;
  CMSG_SIGNER_INFO_PARAM = 6;
  CERT_NAME_SIMPLE_DISPLAY_TYPE = 4;
  CERT_FIND_SUBJECT_CERT = 720896; // CERT_COMPARE_SUBJECT_CERT (11) shl CERT_COMPARE_SHIFT (16) = $000B0000
  X509_ASN_ENCODING = $00000001;
  PKCS_7_ASN_ENCODING = $00010000;

type
  HCERTSTORE = Pointer;
  HCRYPTMSG = Pointer;
  PCCERT_CONTEXT = Pointer;

  CRYPT_DATA_BLOB = record
    cbData: DWORD;
    pbData: PByte;
  end;
  CRYPT_INTEGER_BLOB = CRYPT_DATA_BLOB;
  CERT_NAME_BLOB = CRYPT_DATA_BLOB;

  CRYPT_BIT_BLOB = record
    cbData: DWORD;
    pbData: PByte;
    cUnusedBits: DWORD;
  end;

  PCMSG_SIGNER_INFO = ^CMSG_SIGNER_INFO;
  CMSG_SIGNER_INFO = record
    dwVersion: DWORD;
    Issuer: CERT_NAME_BLOB;
    SerialNumber: CRYPT_INTEGER_BLOB;
    HashAlgorithm: record
      pszObjId: PAnsiChar;
      Parameters: CRYPT_DATA_BLOB;
    end;
    HashEncryptionAlgorithm: record
      pszObjId: PAnsiChar;
      Parameters: CRYPT_DATA_BLOB;
    end;
    EncryptedHash: CRYPT_DATA_BLOB;
    AuthAttrs: record
      cAttr: DWORD;
      rgAttr: Pointer;
    end;
    UnauthAttrs: record
      cAttr: DWORD;
      rgAttr: Pointer;
    end;
  end;

  CERT_INFO = record
    dwVersion: DWORD;
    SerialNumber: CRYPT_INTEGER_BLOB;
    SignatureAlgorithm: record
      pszObjId: PAnsiChar;
      Parameters: CRYPT_DATA_BLOB;
    end;
    Issuer: CERT_NAME_BLOB;
    NotBefore: TFileTime;
    NotAfter: TFileTime;
    Subject: CERT_NAME_BLOB;
    SubjectPublicKeyInfo: record
      Algorithm: record
        pszObjId: PAnsiChar;
        Parameters: CRYPT_DATA_BLOB;
      end;
      PublicKey: CRYPT_BIT_BLOB;
    end;
    IssuerUniqueId: CRYPT_BIT_BLOB;
    SubjectUniqueId: CRYPT_BIT_BLOB;
    cExtension: DWORD;
    rgExtension: Pointer;
  end;
  PCERT_INFO = ^CERT_INFO;

  // PCCERT_CONTEXT above is untyped, cast to this to read the fields
  CERT_CONTEXT = record
    dwCertEncodingType: DWORD;
    pbCertEncoded: PByte;
    cbCertEncoded: DWORD;
    pCertInfo: PCERT_INFO;
    hCertStore: HCERTSTORE;
  end;
  PCERT_CONTEXT = ^CERT_CONTEXT;

  function CryptQueryObject(dwObjectType: DWORD; pvObject: Pointer; dwExpectedContentTypeFlags: DWORD; dwExpectedFormatTypeFlags: DWORD;
    dwFlags: DWORD; pdwMsgAndCertEncodingType: PDWORD; pdwContentType: PDWORD; pdwFormatType: PDWORD;
    phCertStore: Pointer; phMsg: Pointer; ppvContext: Pointer): BOOL; stdcall; external 'Crypt32.dll';

  function CertCloseStore(hCertStore: HCERTSTORE; dwFlags: DWORD): BOOL; stdcall; external 'Crypt32.dll';

  function CryptMsgClose(hCryptMsg: HCRYPTMSG): BOOL; stdcall; external 'Crypt32.dll';

  function CryptMsgGetParam(hCryptMsg: HCRYPTMSG; dwParamType: DWORD; dwIndex: DWORD; pvData: Pointer; pcbData: PDWORD): BOOL; stdcall; external 'Crypt32.dll';

  function CertFindCertificateInStore(hCertStore: HCERTSTORE; dwCertEncodingType: DWORD; dwFindFlags: DWORD; dwFindType: DWORD;
    pvFindPara: Pointer; pPrevCertContext: PCCERT_CONTEXT): PCCERT_CONTEXT; stdcall; external 'Crypt32.dll';

  function CertFreeCertificateContext(pCertContext: PCCERT_CONTEXT): BOOL; stdcall; external 'Crypt32.dll';

  function CertGetNameString(pCertContext: PCCERT_CONTEXT; dwType: DWORD; dwFlags: DWORD; pvTypePara: Pointer; pszNameString: PChar;
    cchNameString: DWORD): DWORD; stdcall; external 'Crypt32.dll' name 'CertGetNameStringW';


implementation

uses
  System.SysUtils;

{ TCommandLineParameters }

function TCommandLineParameters.GetEffectiveFailMode: TFailMode;
begin
  if FFailMode <> Auto then
    Result := FFailMode
  else if not GetLogFileName.IsEmpty then
    Result := LogOnly
  else
    Result := FailOnError;
end;

function TCommandLineParameters.GetEffectiveVerify: Boolean;
begin
  Result := FVerify or not FVerifySigners.IsEmpty;
end;

function TCommandLineParameters.GetLogFileName: string;
begin
  if not FLogFile.IsEmpty then
    Result := ExpandFileName(FLogFile)
  else if FLog then
    Result := ExtractFilePath(ParamStr(0)) + LOG_FILE_NAME_DEFAULT
  else
    Result := '';
end;

end.
