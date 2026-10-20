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
  DNLUnit.NUnitLogger in 'Source\3rdParty\Delphi.NUnitLogger\Source\DNLUnit.NUnitLogger.pas',
  CIESUnit.Consts in 'Source\CIESUnit.Consts.pas',
  CIESUnit.Commandline in 'Source\CIESUnit.Commandline.pas',
  CIESUnit.Runner in 'Source\CIESUnit.Runner.pas',
  CIESUnit.Types in 'Source\CIESUnit.Types.pas',
  CIESUnit.Utils in 'Source\CIESUnit.Utils.pas';

begin
  try
    var LCommandLine := TCommandLineParameters.Create;
    try
      if ParseCommandLine(LCommandLine) then
      begin
        var LRunner := TCIESRunner.Create(LCommandLine);
        try
          LRunner.Run;
        finally
          LRunner.Free;
        end;
      end;
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

