unit CIESUnit.Types;

interface

uses
  Winapi.Windows;

{
  Types, Conmsts and WinApi declarations.
}

const
  CERT_QUERY_OBJECT_FILE = $00000001;
  CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED_EMBED = $00000400;
  CERT_QUERY_FORMAT_FLAG_BINARY = $00000002;
  CMSG_SIGNER_INFO_PARAM = 6;
  CERT_NAME_SIMPLE_DISPLAY_TYPE = 4;
  CERT_FIND_SUBJECT_CERT = 655360;
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
      PublicKey: CRYPT_DATA_BLOB;
    end;
    IssuerUniqueId: CRYPT_DATA_BLOB;
    SubjectUniqueId: CRYPT_DATA_BLOB;
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


end.
