program IsExeSigned;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.StrUtils,
  CIESUnit.Types in 'Source\CIESUnit.Types.pas',
  CIESUnit.Utils in 'Source\CIESUnit.Utils.pas';

const
  EXIT_CODE_NOT_SIGNED = 1;
  EXIT_CODE_PARAM_NOT_FOUND = 2;
  EXIT_CODE_PARAM_VALUE_ERROR = 3;

function GetCmdLineSwitch(const ASwitchName: string; var ASwitchValue: string): Boolean;
begin
  Result := FindCmdLineSwitch(ASwitchName, ASwitchValue);

  Result := Result and not ASwitchValue.IsEmpty;

  if not Result then
  begin
    Writeln('Parameter ' + ASwitchName.QuotedString('"') + ' not found or don''t have value');
    ExitCode := EXIT_CODE_PARAM_NOT_FOUND;
  end;
end;

procedure SetParamValueError(const AParamName, AErrorSuffix: string);
begin
  Writeln('Error in Parameter ' + AParamName.QuotedString('"') + ' - ' + AErrorSuffix);
  ExitCode := EXIT_CODE_PARAM_VALUE_ERROR;
end;

const
  PARAM_FILE_NAME = 'FileName';
  PARAM_ERROR_IF_NOT_SIGNED = 'ErrorIfNotSigned';
begin
  try
    var LFileName: string;
    if not GetCmdLineSwitch(PARAM_FILE_NAME, LFileName) then
      Exit;

    var LErrorIfNotSignedStr: string;
    if not GetCmdLineSwitch(PARAM_ERROR_IF_NOT_SIGNED, LErrorIfNotSignedStr) then
      Exit;

    if not FileExists(LFileName) then
    begin
      SetParamValueError(PARAM_FILE_NAME, 'file does not exists');
      Exit;
    end;

    var LErrorIfNotSigned: Boolean := False;

    if not TryStrToBool(LErrorIfNotSignedStr, LErrorIfNotSigned) then
      LErrorIfNotSigned := False;

    var LExeIsSigned := CIESUnit.Utils.IsExeSigned(LFileName);

    if LExeIsSigned then
      Writeln('Exe is Signed by ' + GetSignerName(LFileName).QuotedString('"'))
    else
    begin
      Writeln('Exe is Signed NOT Signed');

      if LErrorIfNotSigned then
      begin
        ExitCode := EXIT_CODE_NOT_SIGNED;
        Exit;
      end;
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
