unit CIESUnit.Commandline;

interface

uses
  Delphi.CommandLineParser, CIESUnit.Types;

  function ParseCommandLine(const AParameters: TCommandLineParameters): Boolean;
  procedure SetParamValueError(const AParamName, AErrorSuffix: string);

implementation

uses
  System.SysUtils, Delphi.WildCardMatcher, CIESUnit.Consts;

function ParseCommandLine(const AParameters: TCommandLineParameters): Boolean;
var
  LParser: ICommandLineParser;
begin
  LParser := CreateCommandLineParser;

  Result := LParser.Parse(AParameters);

  if not Result then
  begin
    DefaultUsageConsoleOutput(LParser);

    ExitCode := EXIT_CODE_PARAM_NOT_FOUND;

    Exit;
  end;

  if TWildCard.IsWildCard(AParameters.FileName) then
  begin
    var LPath := ExtractFilePath(AParameters.FileName);

    if LPath.IsEmpty then
    begin
      SetParamValueError(PARAM_FILE_NAME, 'file name pattern must include the directory');

      Result := False;
    end
    else if not DirectoryExists(LPath) then
    begin
      SetParamValueError(PARAM_FILE_NAME, 'directory ' + LPath.QuotedString('"') + ' does not exist');

      Result := False;
    end;
  end
  else if not FileExists(AParameters.FileName) then
  begin
    SetParamValueError(PARAM_FILE_NAME, 'file ' + AParameters.FileName.QuotedString('"') + ' does not exist');

    Result := False;
  end;
end;

procedure SetParamValueError(const AParamName, AErrorSuffix: string);
begin
  Writeln('Error in Parameter ' + AParamName.QuotedString('"') + ' - ' + AErrorSuffix);

  ExitCode := EXIT_CODE_PARAM_VALUE_ERROR;
end;

end.
