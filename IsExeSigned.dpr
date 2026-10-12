program IsExeSigned;

{$APPTYPE CONSOLE}

// Disable the "new" RTTI to make exe smaller
{$WEAKLINKRTTI ON}

{$IF DECLARED(TVisibilityClasses)}
  {$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}
{$ENDIF}

{$R *.res}

uses
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  System.StrUtils,
  Delphi.CommandLineParser in 'Source\3rdParty\Delphi.CommandLineParser\Delphi.CommandLineParser.pas',
  Delphi.WildCardMatcher in 'Source\3rdParty\Delphi.WildCardMatcher\Source\Delphi.WildCardMatcher.pas',
  CIESUnit.Consts in 'Source\CIESUnit.Consts.pas',
  CIESUnit.Commandline in 'CIESUnit.Commandline.pas',
  CIESUnit.Types in 'Source\CIESUnit.Types.pas',
  CIESUnit.Utils in 'Source\CIESUnit.Utils.pas';


function GetFiles(const AFileNamePattern: string; const ARecurseSubDirs: Boolean): TArray<string>;
begin
  if HasWildcard(AFileNamePattern) then
  begin
    var LPath := ExtractFilePath(AFileNamePattern);
    var LFilterString := ExtractFileName(AFileNamePattern);


    var LAllFiles := TDirectory.GetFiles(LPath, '*',
      if ARecurseSubDirs then TSearchOption.soAllDirectories else TSearchOption.soTopDirectoryOnly);

    var LFilter := TWildCardFilter.Create(LFilterString.Split([';']), [], [wcoCaseSensitive]);

    Result := LFilter.Filter(LAllFiles);
  end
  else
    Result := [AFileNamePattern];
end;

procedure SetParamValueError(const AParamName, AErrorSuffix: string);
begin
  Writeln('Error in Parameter ' + AParamName.QuotedString('"') + ' - ' + AErrorSuffix);

  ExitCode := EXIT_CODE_PARAM_VALUE_ERROR;
end;

begin
  try
    var LCommandLine := TCommandLineParameters.Create;
    try
      if not ParseCommandLine(LCommandLine) then
        Exit;

      var LFiles := GetFiles(LCommandLine.FileName, LCommandLine.RecurseSubDirs);
      var LFilesCount := Length(LFiles);
      var LUnsignedFiles := 0;
      var LMultipleFiles := LFilesCount > 1;
      var LLineIndent := if LMultipleFiles then '  ' else '';

      if LMultipleFiles then
        Writeln(LFilesCount.ToString + ' files found.');

      for var LCurrentFile in LFiles do
      begin
        if not FileExists(LCurrentFile) then
        begin
          SetParamValueError(PARAM_FILE_NAME, 'file does not exist');
          Exit;
        end;

        var LExeIsSigned := CIESUnit.Utils.IsExeSigned(LCurrentFile);

        if LExeIsSigned then
          Writeln(LLineIndent + '- ' + LCurrentFile.QuotedString('"') +  ' - is Signed by ' + GetSignerName(LCurrentFile).QuotedString('"'))
        else
        begin
          Writeln(LLineIndent + '* ' + LCurrentFile.QuotedString('"') +  ' - is NOT Signed');

          Inc(LUnsignedFiles);
        end;
      end;

      if LMultipleFiles then
        Writeln(Length(LFiles).ToString + 'File(s) checked, ' + LUnsignedFiles.ToString + ' of them unsigned.');

      if LUnsignedFiles > 0 then
        if LCommandLine.ErrorIfNotSigned then
          ExitCode := EXIT_CODE_NOT_SIGNED;
    finally
      LCommandLine.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := EXIT_CODE_EXCEPTION;
    end;
  end;

{$IF DEFINED(DEBUG)}
  WriteLn('Press [enter} to continue');
  ReadLn;
{$ENDIF}
end.

