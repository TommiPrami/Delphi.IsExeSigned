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
  IESUnit.Commandline in 'Source\IESUnit.Commandline.pas',
  IESUnit.Consts in 'Source\IESUnit.Consts.pas',
  IESUnit.Runner in 'Source\IESUnit.Runner.pas',
  IESUnit.Types in 'Source\IESUnit.Types.pas',
  IESUnit.Utils in 'Source\IESUnit.Utils.pas';

begin
  try
    var LCommandLine := TCommandLineParameters.Create;
    try
      if ParseCommandLine(LCommandLine) then
      begin
        var LRunner := TIESRunner.Create(LCommandLine);
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

