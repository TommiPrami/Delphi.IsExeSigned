unit CIESUnit.Types;

interface

uses
  Winapi.Windows, System.Classes, Delphi.CommandLineParser, CIESUnit.Consts;

type
  TCommandLineParameters = class(TObject)
  strict private
    FFileName: string;
    FErrorIfNotSigned: Boolean;
    FRecurseSubDirs: Boolean;
    FCheckIsSignatureValid: Boolean;
    FCheckSignatureSignerFilter: string;
    FSignFileCommandLine: string;
    FSignFileWildCard: string;
    FSignTimeout: Integer;
    FContinueOnSignTimeout: Boolean;
    FLogToFile: Boolean;
    FLogFileName: string;
    FAllowLogOverwrite: Boolean;
  public
    // Full path of the NUnit XML log file to write, '' when no log is written: LogFileName if given, otherwise
    // LOG_FILE_NAME_DEFAULT in the application folder if LogToFile is True
    function GetLogFileName: string;

    [CLPLongName('FileName'), CLPDescription('Filename', '<path\[filename/*.dll;File<##>Util*.exe]>'), CLPDefault(''), CLPRequired]
    property FileName: string read FFileName write FFileName;

    [CLPLongName('ErrorIfNotSigned'), CLPDescription('Return exit code [1] if exe/dll not signed', '<Boolean>'), CLPDefault('True')]
    property ErrorIfNotSigned: Boolean read FErrorIfNotSigned write FErrorIfNotSigned;

    [CLPLongName('RecurseSubDirs'), CLPDescription('Recurse sub dirs if filename has search pattern', '<Boolean>'), CLPDefault('True')]
    property RecurseSubDirs: Boolean read FRecurseSubDirs write FRecurseSubDirs;

    [CLPLongName('CheckIsSignatureValid'), CLPDescription('Return exit code [5] if signature is not valid', '<Boolean>'), CLPDefault('False')]
    property CheckIsSignatureValid: Boolean read FCheckIsSignatureValid write FCheckIsSignatureValid;

    [CLPLongName('CheckSignatureSignerFilter'), CLPDescription('Check signature validity only for matching signers, implies CheckIsSignatureValid', '<*Signer*;Signer*>'), CLPDefault('')]
    property CheckSignatureSignerFilter: string read FCheckSignatureSignerFilter write FCheckSignatureSignerFilter;

    [CLPLongName('SignFileCommandLine'), CLPDescription('Command to sign unsigned files with, %filename% is replaced with the file name. Return exit code [6] if %filename% is missing', '<C:\SignFile.bat %filename%>'), CLPDefault('')]
    property SignFileCommandLine: string read FSignFileCommandLine write FSignFileCommandLine;

    [CLPLongName('SignFileWildCard'), CLPDescription('Sign only unsigned files whose full path matches, all unsigned files if not given', '<*\Dir\*.dll;*\Other\*>'), CLPDefault('')]
    property SignFileWildCard: string read FSignFileWildCard write FSignFileWildCard;

    [CLPLongName('SignTimeout'), CLPDescription('Seconds to wait for the sign command, then it is stopped', '<1..86400>'), CLPDefault('60')]
    property SignTimeout: Integer read FSignTimeout write FSignTimeout;

    [CLPLongName('ContinueOnSignTimeout'), CLPDescription('Continue with the next file when the sign command times out, otherwise stop and return exit code [7]', '<Boolean>'), CLPDefault('False')]
    property ContinueOnSignTimeout: Boolean read FContinueOnSignTimeout write FContinueOnSignTimeout;

    [CLPLongName('LogToFile'), CLPDescription('Write NUnit XML log, to LogFileName or to IsExeSigned.xml in the application folder', '<Boolean>'), CLPDefault('False')]
    property LogToFile: Boolean read FLogToFile write FLogToFile;

    [CLPLongName('LogFileName'), CLPDescription('NUnit XML log file, implies LogToFile. The directory must exist', '<path\filename.xml>'), CLPDefault('')]
    property LogFileName: string read FLogFileName write FLogFileName;

    [CLPLongName('AllowLogOverwrite'), CLPDescription('Overwrite an existing log file, if False and the log file exists, return exit code [3]', '<Boolean>'), CLPDefault('True')]
    property AllowLogOverwrite: Boolean read FAllowLogOverwrite write FAllowLogOverwrite;
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

function TCommandLineParameters.GetLogFileName: string;
begin
  if not FLogFileName.IsEmpty then
    Result := ExpandFileName(FLogFileName)
  else if FLogToFile then
    Result := ExtractFilePath(ParamStr(0)) + LOG_FILE_NAME_DEFAULT
  else
    Result := '';
end;

end.
