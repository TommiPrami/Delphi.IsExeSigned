unit CIESUnit.Utils;

interface

  function IsExeSigned(const AExeFileName: string; out ASignerName: string): Boolean;
  function IsSignatureValid(const AExeFileName: string; out AErrorMessage: string): Boolean;
  function GetFiles(const AFileNamePattern: string; const ARecurseSubDirs: Boolean): TArray<string>;


implementation

uses
  Winapi.Windows, System.IOUtils, System.SysUtils, CIESUnit.Types, Delphi.WildCardMatcher;

function GetSignerName(const AStore: HCERTSTORE; const AMsg: HCRYPTMSG): string;
begin
  Result := '';

  // Get signer information size
  var LSignerInfoSize: DWORD := 0;
  CryptMsgGetParam(AMsg, CMSG_SIGNER_INFO_PARAM, 0, nil, @LSignerInfoSize);

  if LSignerInfoSize = 0 then
    Exit;

  var LSignerInfo: PCMSG_SIGNER_INFO;
  GetMem(LSignerInfo, LSignerInfoSize);
  try
    // Get signer information
    if not CryptMsgGetParam(AMsg, CMSG_SIGNER_INFO_PARAM, 0, LSignerInfo, @LSignerInfoSize) then
      Exit;

    // Prepare CERT_INFO structure to search for the certificate
    var LCertInfo: CERT_INFO;
    FillChar(LCertInfo, SizeOf(LCertInfo), 0);
    LCertInfo.Issuer := LSignerInfo.Issuer;
    LCertInfo.SerialNumber := LSignerInfo.SerialNumber;

    // Search for the signer certificate in the store
    var LCertContext: PCCERT_CONTEXT;
    LCertContext := CertFindCertificateInStore(AStore, X509_ASN_ENCODING or PKCS_7_ASN_ENCODING, 0, CERT_FIND_SUBJECT_CERT,
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
end;

function IsExeSigned(const AExeFileName: string; out ASignerName: string): Boolean;
var
  LContentType: DWORD;
  LEncoding: DWORD;
  LFormatType: DWORD;
begin
  ASignerName := '';

  var LStore: HCERTSTORE := nil;
  var LMsg: HCRYPTMSG := nil;
  try
    // Check if the file has an embedded signature
    Result := CryptQueryObject(CERT_QUERY_OBJECT_FILE, PChar(AExeFileName), CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED_EMBED,
      CERT_QUERY_FORMAT_FLAG_BINARY, 0, @LEncoding, @LContentType, @LFormatType, @LStore, @LMsg, nil);

    if Result then
      ASignerName := GetSignerName(LStore, LMsg);
  finally
    if Assigned(LStore) then
      CertCloseStore(LStore, 0);

    if Assigned(LMsg) then
      CryptMsgClose(LMsg);
  end;
end;

function IsSignatureValid(const AExeFileName: string; out AErrorMessage: string): Boolean;
var
  LFileInfo: WINTRUST_FILE_INFO;
  LTrustData: WINTRUST_DATA;
begin
  AErrorMessage := '';

  FillChar(LFileInfo, SizeOf(LFileInfo), 0);
  LFileInfo.cbStruct := SizeOf(LFileInfo);
  LFileInfo.pcwszFilePath := PChar(AExeFileName);

  FillChar(LTrustData, SizeOf(LTrustData), 0);
  LTrustData.cbStruct := SizeOf(LTrustData);
  LTrustData.dwUIChoice := WTD_UI_NONE;
  // No revocation check, it needs network access (CRL/OCSP), which CI machines might not have
  LTrustData.fdwRevocationChecks := WTD_REVOKE_NONE;
  LTrustData.dwUnionChoice := WTD_CHOICE_FILE;
  LTrustData.pFile := @LFileInfo;

  // Checks that the file is not modified after signing, the certificate chain up to a trusted root, and that the
  // signing certificate was valid at the time of signing (timestamped signature) or is still valid (no timestamp)
  var LResult := WinVerifyTrust(0, WINTRUST_ACTION_GENERIC_VERIFY_V2, @LTrustData);

  Result := LResult = ERROR_SUCCESS;

  if not Result then
    AErrorMessage := SysErrorMessage(Cardinal(LResult)) + ' (0x' + IntToHex(Cardinal(LResult), 8) + ')';
end;

function GetFiles(const AFileNamePattern: string; const ARecurseSubDirs: Boolean): TArray<string>;
begin
  if TWildCard.IsWildCard(AFileNamePattern) then
  begin
    var LPath := ExtractFilePath(AFileNamePattern);
    var LFilterString := ExtractFileName(AFileNamePattern);

    var LAllFiles := TDirectory.GetFiles(LPath, '*',
      if ARecurseSubDirs then TSearchOption.soAllDirectories else TSearchOption.soTopDirectoryOnly);

    var LFilter := TWildCardFilter.Create(LFilterString.Split([';']), [], []);
    var LCount := 0;

    SetLength(Result, Length(LAllFiles));

    // Match the file name only, pattern is anchored to the start of the input
    for var LFile in LAllFiles do
      if LFilter.Accepts(ExtractFileName(LFile)) then
      begin
        Result[LCount] := LFile;
        Inc(LCount);
      end;

    SetLength(Result, LCount);
  end
  else
    Result := [AFileNamePattern];
end;


end.
