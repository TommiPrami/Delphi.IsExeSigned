unit CIESUnit.Utils;

interface

  function IsExeSigned(const AExeFileName: string; out ASignerName: string): Boolean;
  function IsSignatureValid(const AExeFileName: string; out AErrorMessage: string): Boolean;
  function GetFiles(const AFileNamePattern: string; const ARecurseSubDirs: Boolean): TArray<string>;
  // Returns False if the command did not finish in ATimeoutSeconds, it is then stopped
  function RunSignFileCommand(const ACommandLine, AFileName: string; const ATimeoutSeconds: Integer; out AExitCode: Cardinal): Boolean;


implementation

uses
  Winapi.Windows, System.IOUtils, System.SysUtils, CIESUnit.Consts, CIESUnit.Types, Delphi.WildCardMatcher;

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

function RunSignFileCommand(const ACommandLine, AFileName: string; const ATimeoutSeconds: Integer; out AExitCode: Cardinal): Boolean;
var
  LProcessInfo: TProcessInformation;
  LStartupInfo: TStartupInfo;
begin
  // File name is quoted exactly once, also when the placeholder is already quoted in the command line
  var LCommand := StringReplace(ACommandLine, '"' + SIGN_FILE_NAME_PLACEHOLDER + '"', SIGN_FILE_NAME_PLACEHOLDER, [rfReplaceAll, rfIgnoreCase]);
  LCommand := StringReplace(LCommand, SIGN_FILE_NAME_PLACEHOLDER, AFileName.QuotedString('"'), [rfReplaceAll, rfIgnoreCase]);

  var LComSpec := GetEnvironmentVariable('ComSpec');

  if LComSpec.IsEmpty then
    LComSpec := 'cmd.exe';

  // Run through cmd.exe so batch files work too, /S strips only the outer quotes and keeps the command as is
  var LProcessCommandLine := LComSpec + ' /S /C "' + LCommand + '"';
  // CreateProcessW can modify the command line buffer
  UniqueString(LProcessCommandLine);

  FillChar(LStartupInfo, SizeOf(LStartupInfo), 0);
  LStartupInfo.cb := SizeOf(LStartupInfo);

  Result := False;
  AExitCode := 0;

  // Job object, so on timeout the whole process tree is stopped, not just cmd.exe (the sign tool is its child)
  var LJob := CreateJobObject(nil, nil);

  if LJob = 0 then
    RaiseLastOSError;

  try
    if not CreateProcess(nil, PChar(LProcessCommandLine), nil, nil, False, CREATE_SUSPENDED, nil, nil, LStartupInfo, LProcessInfo) then
      RaiseLastOSError;

    try
      // Assigned before the process runs, so its child processes are in the job too. If this fails (Windows 7, already
      // in a job, no nested jobs), timeout stops only cmd.exe
      var LInJob := AssignProcessToJobObject(LJob, LProcessInfo.hProcess);

      ResumeThread(LProcessInfo.hThread);

      case WaitForSingleObject(LProcessInfo.hProcess, Cardinal(ATimeoutSeconds) * 1000) of
        WAIT_OBJECT_0:
          begin
            if not GetExitCodeProcess(LProcessInfo.hProcess, AExitCode) then
              RaiseLastOSError;

            Result := True;
          end;
        WAIT_TIMEOUT:
          begin
            if LInJob then
              TerminateJobObject(LJob, 1)
            else
              TerminateProcess(LProcessInfo.hProcess, 1);

            // Give the termination a moment, so the file is not locked anymore when it is checked
            WaitForSingleObject(LProcessInfo.hProcess, 5000);
          end;
      else
        RaiseLastOSError;
      end;
    finally
      CloseHandle(LProcessInfo.hThread);
      CloseHandle(LProcessInfo.hProcess);
    end;
  finally
    CloseHandle(LJob);
  end;
end;


end.
