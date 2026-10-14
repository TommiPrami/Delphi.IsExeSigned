program IsExeSigned;

{$APPTYPE CONSOLE}

// Disable the "new" RTTI to make exe smaller
{$WEAKLINKRTTI ON}

{$IF DECLARED(TVisibilityClasses)}
  {$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}
{$ENDIF}

{$R *.res}

uses
  System.SysUtils,
  Delphi.CommandLineParser in 'Source\3rdParty\Delphi.CommandLineParser\Delphi.CommandLineParser.pas',
  Delphi.WildCardMatcher in 'Source\3rdParty\Delphi.WildCardMatcher\Source\Delphi.WildCardMatcher.pas',
  CIESUnit.Consts in 'Source\CIESUnit.Consts.pas',
  CIESUnit.Commandline in 'Source\CIESUnit.Commandline.pas',
  CIESUnit.Types in 'Source\CIESUnit.Types.pas',
  CIESUnit.Utils in 'Source\CIESUnit.Utils.pas';

begin
  try
    var LCommandLine := TCommandLineParameters.Create;
    try
      if not ParseCommandLine(LCommandLine) then
        Exit;

      var LFiles := GetFiles(LCommandLine.FileName, LCommandLine.RecurseSubDirs);
      var LFilesCount := Length(LFiles);
      var LUnsignedFiles := 0;

      if LFilesCount = 0 then
      begin
        SetParamValueError(PARAM_FILE_NAME, 'no files match the pattern ' + LCommandLine.FileName.QuotedString('"'));
        Exit;
      end;

      var LMultipleFiles := LFilesCount > 1;
      var LLineIndent := if LMultipleFiles then '  ' else '';
      var LInvalidSignatures := 0;
      var LCheckSignatures := LCommandLine.CheckIsSignatureValid or not LCommandLine.CheckSignatureSignerFilter.IsEmpty;
      // No patterns, accepts all signers
      var LSignerFilter := TWildCardFilter.Create(LCommandLine.CheckSignatureSignerFilter.Split([';'], TStringSplitOptions.ExcludeEmpty), [], []);
      var LSignedFiles := 0;
      var LSignTimeouts := 0;
      var LSignFiles := not LCommandLine.SignFileCommandLine.IsEmpty;
      // Matched against the full path, no patterns accepts all files
      var LSignFileFilter := TWildCardFilter.Create(LCommandLine.SignFileWildCard.Split([';'], TStringSplitOptions.ExcludeEmpty), [], []);

      if LMultipleFiles then
        Writeln(LFilesCount.ToString + ' files found.');

      for var LCurrentFile in LFiles do
      begin
        var LSignerName: string;
        var LIsSigned := CIESUnit.Utils.IsExeSigned(LCurrentFile, LSignerName);
        var LSignedNow := False;

        if not LIsSigned and LSignFiles and LSignFileFilter.Accepts(LCurrentFile) then
        begin
          // Written and flushed before running the command, so sign tool output comes after this line, also
          // when the output is redirected (buffered)
          Writeln(LLineIndent + '> ' + LCurrentFile.QuotedString('"') +  ' - is NOT Signed, signing it');
          Flush(Output);

          var LSignExitCode: Cardinal;

          if not RunSignFileCommand(LCommandLine.SignFileCommandLine, LCurrentFile, LCommandLine.SignTimeout, LSignExitCode) then
          begin
            Writeln(LLineIndent + '  ERROR: Sign command did not finish in ' + LCommandLine.SignTimeout.ToString + ' seconds, it was stopped');

            Inc(LSignTimeouts);

            if not LCommandLine.ContinueOnSignTimeout then
            begin
              Writeln('Stopped, ContinueOnSignTimeout is False');

              ExitCode := EXIT_CODE_SIGN_TIMEOUT;
              Exit;
            end;
          end
          else if LSignExitCode <> 0 then
            Writeln(LLineIndent + '  Sign command returned exit code ' + LSignExitCode.ToString);

          LIsSigned := CIESUnit.Utils.IsExeSigned(LCurrentFile, LSignerName);
          LSignedNow := LIsSigned;

          if LSignedNow then
            Inc(LSignedFiles);
        end;

        if LIsSigned then
        begin
          var LSignedLine := LCurrentFile.QuotedString('"') + (if LSignedNow then ' - is Signed now by ' else ' - is Signed by ')
            + LSignerName.QuotedString('"');

          // Just signed files are always checked, to make sure the signing really worked
          if LSignedNow or (LCheckSignatures and LSignerFilter.Accepts(LSignerName)) then
          begin
            var LErrorMessage: string;

            if IsSignatureValid(LCurrentFile, LErrorMessage) then
              Writeln(LLineIndent + '- ' + LSignedLine + ' - signature is valid')
            else
            begin
              Writeln(LLineIndent + '! ' + LSignedLine + ' - signature is NOT valid: ' + LErrorMessage);

              Inc(LInvalidSignatures);
            end;
          end
          else
            Writeln(LLineIndent + '- ' + LSignedLine);
        end
        else
        begin
          Writeln(LLineIndent + '* ' + LCurrentFile.QuotedString('"') +  ' - is NOT Signed');

          Inc(LUnsignedFiles);
        end;
      end;

      if LMultipleFiles then
      begin
        var LSummary := LFilesCount.ToString + ' file(s) checked, ' + LUnsignedFiles.ToString + ' of them unsigned';

        if LSignFiles then
          LSummary := LSummary + ', ' + LSignedFiles.ToString + ' signed now';

        if LSignTimeouts > 0 then
          LSummary := LSummary + ', ' + LSignTimeouts.ToString + ' sign command timeout(s)';

        if LCheckSignatures or LSignFiles then
          LSummary := LSummary + ', ' + LInvalidSignatures.ToString + ' with invalid signature';

        Writeln(LSummary + '.');
      end;

      if (LUnsignedFiles > 0) and LCommandLine.ErrorIfNotSigned then
        ExitCode := EXIT_CODE_NOT_SIGNED
      else if LInvalidSignatures > 0 then
        ExitCode := EXIT_CODE_SIGNATURE_NOT_VALID;
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
  WriteLn('Press [Enter] to continue');
  ReadLn;
{$ENDIF}
end.

