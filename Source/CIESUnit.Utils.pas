unit CIESUnit.Utils;

interface

  function IsExeSigned(const AExeFileName: string): Boolean;
  function GetSignerName(const AExeFileName: string): string;

implementation

uses
  Winapi.Windows, System.SysUtils, CIESUnit.Types;

function IsExeSigned(const AExeFileName: string): Boolean;
var
  dwEncoding, dwContentType, dwFormatType: DWORD;
begin
  Result := False;

  if not FileExists(AExeFileName) then
    Exit;

  var hFile := CreateFile(PChar(AExeFileName), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);

  if hFile = INVALID_HANDLE_VALUE then
    Exit;

  var hStore: HCERTSTORE := nil;
  var hMsg: HCRYPTMSG := nil;
  try
    // Check if the file has an embedded signature
    Result := CryptQueryObject(CERT_QUERY_OBJECT_FILE, PChar(AExeFileName), CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED_EMBED,
      CERT_QUERY_FORMAT_FLAG_BINARY, 0, @dwEncoding, @dwContentType, @dwFormatType, @hStore, @hMsg, nil);
  finally
    if Result then
    begin
      if Assigned(hStore) then
        CertCloseStore(hStore, 0);

      if Assigned(hMsg) then
        CryptMsgClose(hMsg);
    end;

    CloseHandle(hFile);
  end;
end;

function GetSignerName(const AExeFileName: string): string;
var
  dwEncoding, dwContentType, dwFormatType, cbSignerInfo: DWORD;
  hStore: HCERTSTORE;
begin
  Result := '';

  if not FileExists(AExeFileName) then
    Exit;

  var LhMsg: HCRYPTMSG;

  if not CryptQueryObject(CERT_QUERY_OBJECT_FILE, PChar(AExeFileName), CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED_EMBED,
    CERT_QUERY_FORMAT_FLAG_BINARY, 0, @dwEncoding, @dwContentType, @dwFormatType, @hStore, @LhMsg, nil) then
    Exit;

  try
    // Get signer information size
    cbSignerInfo := 0;
    CryptMsgGetParam(LhMsg, CMSG_SIGNER_INFO_PARAM, 0, nil, @cbSignerInfo);

    if cbSignerInfo = 0 then
      Exit;

    var pSignerInfo: PCMSG_SIGNER_INFO;
    GetMem(pSignerInfo, cbSignerInfo);
    try
      // Get signer information
      if not CryptMsgGetParam(LhMsg, CMSG_SIGNER_INFO_PARAM, 0, pSignerInfo, @cbSignerInfo) then
        Exit;

      // Prepare CERT_INFO structure to search for the certificate
      var LCertInfo: CERT_INFO;
      FillChar(LCertInfo, SizeOf(LCertInfo), 0);
      LCertInfo.Issuer := pSignerInfo.Issuer;
      LCertInfo.SerialNumber := pSignerInfo.SerialNumber;

      // Search for the signer certificate in the store
      var pCertContext: PCCERT_CONTEXT;
      pCertContext := CertFindCertificateInStore(hStore, X509_ASN_ENCODING or PKCS_7_ASN_ENCODING, 0, CERT_FIND_SUBJECT_CERT,
        @LCertInfo, nil);

      if pCertContext <> nil then
      begin
        try
          var LdwData: DWORD;
          var LszName: array[0..255] of Char;

          // Get the subject name
          LdwData := CertGetNameString(pCertContext, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, nil, @LszName[0], Length(LszName));

          if LdwData > 1 then
            Result := LszName;
        finally
          CertFreeCertificateContext(pCertContext);
        end;
      end;
    finally
      FreeMem(pSignerInfo);
    end;
  finally
    if hStore <> nil then
      CertCloseStore(hStore, 0);
    if LhMsg <> nil then
      CryptMsgClose(LhMsg);
  end;
end;


end.
