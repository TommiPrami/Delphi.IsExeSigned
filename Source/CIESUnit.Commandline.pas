unit CIESUnit.Commandline;

interface

uses
  Delphi.CommandLineParser, CIESUnit.Consts, CIESUnit.Types;

  function ParamValueErrorText(const AParamName, AErrorSuffix: string): string;
  function ParseCommandLine(const AParameters: TCommandLineParameters): Boolean;
  procedure SetParamValueError(const AParamName, AErrorSuffix: string; const AExitCode: Integer = EXIT_CODE_PARAM_VALUE_ERROR);

implementation

uses
  System.StrUtils, System.SysUtils, System.TypInfo, Delphi.WildCardMatcher;

const
  // Length of the longest parameter name, ContinueOnSignTimeout
  SETTING_NAME_WIDTH = 21;

procedure WriteSetting(const AName, AValue: string);
begin
  Writeln('  ' + AName.PadRight(SETTING_NAME_WIDTH) + ' : ' + AValue);
end;

function BooleanText(const AValue: Boolean): string;
begin
  Result := BoolToStr(AValue, True);
end;

function QuotedText(const AValue: string): string;
begin
  Result := AValue.QuotedString('"');
end;

// The settings the run uses: the parameters with their defaults, Auto resolved, and the implied ones applied
procedure WriteSettings(const AParameters: TCommandLineParameters);
begin
  var LFailMode := GetEnumName(TypeInfo(TFailMode), Ord(AParameters.GetEffectiveFailMode));

  if AParameters.FailMode = Auto then
    LFailMode := LFailMode + ' (Auto)';

  var LLogFileName := AParameters.GetLogFileName;

  Writeln('Settings:');
  WriteSetting('Files', QuotedText(AParameters.Files));
  WriteSetting('FailMode', LFailMode);
  WriteSetting('Recursive', BooleanText(AParameters.Recursive));
  WriteSetting('Verify', BooleanText(AParameters.GetEffectiveVerify));
  WriteSetting('VerifySigners', QuotedText(AParameters.VerifySigners));
  WriteSetting('SignCommand', QuotedText(AParameters.SignCommand));
  WriteSetting('SignFilter', QuotedText(AParameters.SignFilter));
  WriteSetting('SignTimeout', AParameters.SignTimeout.ToString);
  WriteSetting('ContinueOnSignTimeout', BooleanText(AParameters.ContinueOnSignTimeout));
  WriteSetting('Log', BooleanText(not LLogFileName.IsEmpty));
  WriteSetting('LogFile', QuotedText(LLogFileName));
  WriteSetting('LogOverwrite', BooleanText(AParameters.LogOverwrite));
  Writeln;
end;

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

  // Before the parameter values are checked, so the settings show also when one is not valid
  if AParameters.Verbose then
    WriteSettings(AParameters);

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
  Writeln(ParamValueErrorText(AParamName, AErrorSuffix));

  ExitCode := AExitCode;
end;

function ParamValueErrorText(const AParamName, AErrorSuffix: string): string;
begin
  Result := 'Error in Parameter ' + AParamName.QuotedString('"') + ' - ' + AErrorSuffix;
end;

end.
