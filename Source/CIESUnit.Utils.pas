unit CIESUnit.Utils;

interface

  function IsExeSigned(const AExeFileName: string): Boolean;
  function GetSignerName(const AExeFileName: string): string;

implementation

uses
  Winapi.Windows, System.SysUtils, CIESUnit.Types;

function IsExeSigned(const AExeFileName: string): Boolean;
var
  LEncoding: DWORD;
  LContentType: DWORD;
  LFormatType: DWORD;
begin
  Result := False;

  if not FileExists(AExeFileName) then
    Exit;

  var LStore: HCERTSTORE := nil;
  var LMsg: HCRYPTMSG := nil;
  try
    // Check if the file has an embedded signature
    Result := CryptQueryObject(CERT_QUERY_OBJECT_FILE, PChar(AExeFileName), CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED_EMBED,
      CERT_QUERY_FORMAT_FLAG_BINARY, 0, @LEncoding, @LContentType, @LFormatType, @LStore, @LMsg, nil);
  finally
    if Assigned(LStore) then
      CertCloseStore(LStore, 0);

    if Assigned(LMsg) then
      CryptMsgClose(LMsg);
  end;
end;

function GetSignerName(const AExeFileName: string): string;
begin
  Result := '';

  if not FileExists(AExeFileName) then
    Exit;

  var LStore: HCERTSTORE := nil;
  var LMsg: HCRYPTMSG := nil;
  var LEncoding: DWORD;
  var LContentType: DWORD;
  var LFormatType: DWORD;

  if not CryptQueryObject(CERT_QUERY_OBJECT_FILE, PChar(AExeFileName), CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED_EMBED,
    CERT_QUERY_FORMAT_FLAG_BINARY, 0, @LEncoding, @LContentType, @LFormatType, @LStore, @LMsg, nil) then
    Exit;

  try
    // Get signer information size
    var LSignerInfoSize: DWORD := 0;
    CryptMsgGetParam(LMsg, CMSG_SIGNER_INFO_PARAM, 0, nil, @LSignerInfoSize);

    if LSignerInfoSize = 0 then
      Exit;

    var LSignerInfo: PCMSG_SIGNER_INFO;
    GetMem(LSignerInfo, LSignerInfoSize);
    try
      // Get signer information
      if not CryptMsgGetParam(LMsg, CMSG_SIGNER_INFO_PARAM, 0, LSignerInfo, @LSignerInfoSize) then
        Exit;

      // Prepare CERT_INFO structure to search for the certificate
      var LCertInfo: CERT_INFO;
      FillChar(LCertInfo, SizeOf(LCertInfo), 0);
      LCertInfo.Issuer := LSignerInfo.Issuer;
      LCertInfo.SerialNumber := LSignerInfo.SerialNumber;

      // Search for the signer certificate in the store
      var LCertContext: PCCERT_CONTEXT;
      LCertContext := CertFindCertificateInStore(LStore, X509_ASN_ENCODING or PKCS_7_ASN_ENCODING, 0, CERT_FIND_SUBJECT_CERT,
        @LCertInfo, nil);

      if LCertContext <> nil then
      begin
        try
          // Get the subject name length (in characters, including the terminating null)
          var LNameLen := CertGetNameString(LCertContext, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, nil, nil, 0);

          if LNameLen > 1 then
          begin
            SetLength(Result, LNameLen);
            LNameLen := CertGetNameString(LCertContext, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, nil, PChar(Result), LNameLen);
            // Drop the terminating null that CertGetNameString counts in the length
            SetLength(Result, LNameLen - 1);
          end;
        finally
          CertFreeCertificateContext(LCertContext);
        end;
      end;
    finally
      FreeMem(LSignerInfo);
    end;
  finally
    if Assigned(LStore) then
      CertCloseStore(LStore, 0);
    if Assigned(LMsg) then
      CryptMsgClose(LMsg);
  end;
end;


end.
