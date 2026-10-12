unit CIESUnit.Commandline;

interface

uses
  Delphi.CommandLineParser, CIESUnit.Types;

  function ParseCommandLine(const AParameters: TCommandLineParameters): Boolean;

implementation

function ParseCommandLine(const AParameters: TCommandLineParameters): Boolean;
var
  LExtension: string;
  LIndex: Integer;
  LParser: ICommandLineParser;
begin
  LParser := CreateCommandLineParser;

  Result := LParser.Parse(AParameters);

  if not Result then
  begin
    DefaultUsageConsoleOutput(LParser);

    Exit;
  end;
end;

end.
