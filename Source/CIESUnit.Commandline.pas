unit CIESUnit.Commandline;

interface

uses
  Delphi.CommandLineParser, CIESUnit.Consts, CIESUnit.Types;

  function ParseCommandLine(const AParameters: TCommandLineParameters): Boolean;
  procedure SetParamValueError(const AParamName, AErrorSuffix: string; const AExitCode: Integer = EXIT_CODE_PARAM_VALUE_ERROR);

implementation

uses
  System.StrUtils, System.SysUtils, Delphi.WildCardMatcher;

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

  if TWildCard.IsWildCard(AParameters.Files) then
  begin
    var LPath := ExtractFilePath(AParameters.Files);

    if LPath.IsEmpty then
    begin
      SetParamValueError(PARAM_FILES, 'file name pattern must include the directory');

      Result := False;
    end
    else if not DirectoryExists(LPath) then
    begin
      SetParamValueError(PARAM_FILES, 'directory ' + LPath.QuotedString('"') + ' does not exist');

      Result := False;
    end;
  end
  else if not FileExists(AParameters.Files) then
  begin
    SetParamValueError(PARAM_FILES, 'file ' + AParameters.Files.QuotedString('"') + ' does not exist');

    Result := False;
  end;

  if not Result then
    Exit;

  if not AParameters.SignCommand.IsEmpty and not ContainsText(AParameters.SignCommand, SIGN_FILE_NAME_PLACEHOLDER) then
  begin
    SetParamValueError(PARAM_SIGN_COMMAND, SIGN_FILE_NAME_PLACEHOLDER + ' is missing from the command line',
      EXIT_CODE_SIGN_COMMAND_NO_FILE_NAME);

    Result := False;
  end
  else if AParameters.SignCommand.IsEmpty and not AParameters.SignFilter.IsEmpty then
  begin
    SetParamValueError(PARAM_SIGN_FILTER, 'can not be used without ' + PARAM_SIGN_COMMAND);

    Result := False;
  end;

  if not Result then
    Exit;

  // Checked before anything is done, rather than failing when the log is saved at the end
  var LLogFileName := AParameters.GetLogFileName;

  if LLogFileName.IsEmpty then
    Exit;

  var LLogDirectory := ExtractFileDir(LLogFileName);

  if ExtractFileName(LLogFileName).IsEmpty then
  begin
    SetParamValueError(PARAM_LOG_FILE, 'file name is missing from ' + LLogFileName.QuotedString('"'));

    Result := False;
  end
  else if not DirectoryExists(LLogDirectory) then
  begin
    SetParamValueError(PARAM_LOG_FILE, 'directory ' + LLogDirectory.QuotedString('"') + ' does not exist');

    Result := False;
  end
  else if FileExists(LLogFileName) and not AParameters.LogOverwrite then
  begin
    SetParamValueError(PARAM_LOG_FILE, 'file ' + LLogFileName.QuotedString('"') + ' exists and LogOverwrite is False');

    Result := False;
  end;
end;

procedure SetParamValueError(const AParamName, AErrorSuffix: string; const AExitCode: Integer = EXIT_CODE_PARAM_VALUE_ERROR);
begin
  Writeln('Error in Parameter ' + AParamName.QuotedString('"') + ' - ' + AErrorSuffix);

  ExitCode := AExitCode;
end;

end.
