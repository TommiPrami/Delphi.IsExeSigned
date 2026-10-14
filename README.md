# Delphi.IsExeSigned

A small utility to check if `.exe` / `.dll` files are signed, grab the signer’s name, optionally sign the unsigned ones, and check that the signature is valid.  

Right now it’s mainly used in CI as a sanity check: making sure the `.exe` files that *should* be signed actually are.  

## Usage

```
IsExeSigned.exe -FileName:"<FILENAME|PATH\PATTERN>" [-ErrorIfNotSigned:<True|False>] [-RecurseSubDirs:<True|False>]
  [-CheckIsSignatureValid:<True|False>] [-CheckSignatureSignerFilter:"<PATTERN>"]
  [-SignFileCommandLine:"<COMMAND %filename%>"] [-SignFileWildCard:"<PATTERN>"]
  [-SignTimeout:<SECONDS>] [-ContinueOnSignTimeout:<True|False>]
  [-LogToFile:<True|False>] [-LogFileName:"<FILENAME>"] [-AllowLogOverwrite:<True|False>]
```

Examples:

```
IsExeSigned.exe -FileName:"C:\Build\MyApp.exe"
IsExeSigned.exe -FileName:"C:\Build\*.exe;*.dll"
IsExeSigned.exe -FileName:"C:\Build\MyApp_<##>*.exe" -RecurseSubDirs:False
IsExeSigned.exe -FileName:"C:\Build\*.exe" -CheckIsSignatureValid:True
IsExeSigned.exe -FileName:"C:\Build\*.exe;*.dll" -CheckSignatureSignerFilter:"*MyCompanyLtd*"
IsExeSigned.exe -FileName:"C:\Build\*.exe;*.dll" -SignFileCommandLine:"C:\SignFile.bat %filename%"
IsExeSigned.exe -FileName:"C:\Build\*.dll" -SignFileCommandLine:"C:\SignFile.bat %filename%" -SignFileWildCard:"*\DllFiles\fb*.dll;*\Redistributables\*"
```

Output, one line per file:

- `-` signed (and signature valid, when checked)  
- `*` not signed  
- `!` signed, but the signature is not valid (with the reason)  
- `>` not signed, running the sign command; the sign command's own output and the file's result line follow  

## Parameters

- **FileName**  
  - Mandatory  
  - Either a single file, or a directory followed by one or more wildcard patterns separated by `;`  
  - Patterns are matched against the file name only, case-insensitively  
  - Wildcards (see [Delphi.WildCardMatcher](Source/3rdParty/Delphi.WildCardMatcher)):  
    - `*` zero or more characters, `?` exactly one character  
    - `<#>`, `<###>` exactly that many digits  
    - `<abc>`, `<a-z>`, `<!abc>` one character in / not in the set  
    - `<"foo"|"bar">` one of the listed strings  
  - All wildcard characters are ones Windows does not allow in file names, so any valid file name is taken as a plain file name, e.g. `C:\Build\App[x64] #2.exe`  

- **ErrorIfNotSigned**  
  - Optional (`True` or `False`), default `True`  
  - If `True` and any checked file is not signed → ExitCode = `1`  

- **RecurseSubDirs**  
  - Optional (`True` or `False`), default `True`  
  - Only used with a pattern: also search the sub directories  

- **CheckIsSignatureValid**  
  - Optional (`True` or `False`), default `False`  
  - Checks the signature of every signed file → ExitCode = `5` if any is not valid  
  - A signature is valid when:  
    - the file has not been modified after signing  
    - the signing certificate chains up to a trusted root certificate  
    - the signing certificate was valid when the file was signed (timestamped signature), or is still valid now (no timestamp) — so a non-timestamped file goes invalid when its certificate expires  

- **CheckSignatureSignerFilter**  
  - Optional, one or more signer name patterns separated by `;` (same wildcards as above, case-insensitive)  
  - Checks the signature validity only for the files whose signer name matches, other signed files are just listed  
  - Giving a filter enables the signature check, `CheckIsSignatureValid` is not needed  

- **SignFileCommandLine**  
  - Optional, command run for each unsigned file, before the signature checks  
  - Must contain `%filename%` (case-insensitive), it is replaced with the quoted full path of the file → if missing, ExitCode = `6`  
  - Run through `cmd.exe`, so batch files work; its output goes to the same console, and a non-zero exit code is reported  
  - After the command the file is checked again: if it is signed now, its signature validity is always checked (exit code `5` if not valid); if it is still not signed, it counts as unsigned  
  - Quotes inside the value do not get through the command line parsing, so a sign tool in a path with spaces (e.g. `signtool.exe` under `Program Files`) has to be called from a batch file  
  - The sign command gets the file name as its parameter, e.g. in `SignFile.bat` as `%1` (quoted) or `%~1` (without quotes)  
  - If IsExeSigned itself is started from a batch file (e.g. a CI build script), write `%%filename%%` there, otherwise `cmd.exe` expands `%filename%` as an environment variable before IsExeSigned sees it  

- **SignFileWildCard**  
  - Optional, one or more patterns separated by `;` (same wildcards as above, case-insensitive), needs `SignFileCommandLine`  
  - Matched against the **full path** of the file, e.g. `*\DllFiles\fb*.dll;*\Redistributables\*`  
  - Only unsigned files that match are signed; if not given, all unsigned files are signed  

- **SignTimeout**  
  - Optional, seconds (`1`–`86400`), default `60`  
  - How long the sign command may run for one file; after that it is stopped, including any processes it started  
  - The timeout is reported as an error on the file's line  

- **ContinueOnSignTimeout**  
  - Optional (`True` or `False`), default `False`  
  - `False`: stop at the first sign command timeout → ExitCode = `7`  
  - `True`: continue with the next file; the timed out file counts as unsigned (unless the command signed it before it was stopped)  

- **LogToFile**  
  - Optional (`True` or `False`), default `False`  
  - Writes an NUnit 3 XML log; without `LogFileName` to `IsExeSigned.xml` in the folder of `IsExeSigned.exe`  

- **LogFileName**  
  - Optional, the NUnit 3 XML log file; giving it writes the log, `LogToFile` is not needed  
  - The directory must exist, the file does not have to; a relative name is relative to the current directory  

- **AllowLogOverwrite**  
  - Optional (`True` or `False`), default `True`  
  - `False` and the log file exists → ExitCode = `3`, checked before anything else is done  

The log has one test case per checked file, named by its full path:

- passed: signed (and signature valid, when checked); the message tells the signer  
- failed: signature not valid, or not signed with `ErrorIfNotSigned` `True`  
- warning: not signed with `ErrorIfNotSigned` `False`  
- error: sign command timeout that stopped the run, or no files match the pattern  

The log is written also when the run stops early (sign command timeout); not when the command line itself is invalid.  

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | All files signed (or `ErrorIfNotSigned` is `False`), and all checked signatures are valid |
| `1` | At least one file is not signed and `ErrorIfNotSigned` is `True` (takes precedence over `5`) |
| `2` | Invalid command line: `FileName` missing or a parameter value is invalid |
| `3` | File not found, pattern without a directory, directory not found, no files match the pattern, `SignFileWildCard` without `SignFileCommandLine`, `SignTimeout` out of range, log file directory not found, or log file exists and `AllowLogOverwrite` is `False` |
| `4` | Something unexpected happened (like an unhandled exception) |
| `5` | At least one checked signature is not valid |
| `6` | `SignFileCommandLine` does not contain `%filename%` |
| `7` | Sign command did not finish in `SignTimeout` seconds, and `ContinueOnSignTimeout` is `False` |

## Limitations

- Only signatures embedded in the file are detected; catalog-signed files (e.g. many Windows system files) are reported as not signed.  
- Certificate revocation is not checked, as it needs network access, which CI machines might not have.  
- For a file with multiple signatures (e.g. SHA-1 + SHA-256), only the primary one is checked.  

## Tests

DUnitX tests are in `UnitTests\`, with TestInsight support (the `Debug - TestInsight` / `Release - TestInsight` configurations). `IsExeSignedGroup.groupproj` has all the projects, IsExeSigned and the tests.

Most of the tests are integration tests that run `IsExeSigned.exe`, so build it first. The tests use the most recently built `Win32|Win64\Release|Debug\IsExeSigned.exe`, or the one the `ISEXESIGNED_EXE` environment variable names. Signed test files are copies of a validly signed Windows file (e.g. `tar.exe`), and signing is tested with fake sign tools (batch files), so nothing is installed or changed outside the temp folder.

From the command line (the default configuration is `Debug - TestInsight`, which runs nothing without TestInsight):

```
msbuild IsExeSigned.dproj /t:Build /p:Config=Release /p:Platform=Win32
msbuild UnitTests\IsExeSignedUnitTests.dproj /t:Build /p:Config=Debug /p:Platform=Win32
UnitTests\Win32\Debug\IsExeSignedUnitTests.exe --exitbehavior:Continue
```
