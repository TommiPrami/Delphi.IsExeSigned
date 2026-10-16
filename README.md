# Delphi.IsExeSigned

A small utility to check if `.exe` / `.dll` files are signed, grab the signer’s name, optionally sign the unsigned ones, and verify that the signature is valid.  

Right now it’s mainly used in CI as a sanity check: making sure the `.exe` files that *should* be signed actually are.  

## Usage

```
IsExeSigned.exe -Files:"<FILE|DIR\PATTERN[;PATTERN]>" [-FailMode:<Auto|FailOnError|LogOnly>] [-Recursive:<True|False>]
  [-Verify:<True|False>] [-VerifySigners:"<PATTERN>"]
  [-SignCommand:"<COMMAND %filename%>"] [-SignFilter:"<PATTERN>"]
  [-SignTimeout:<SECONDS>] [-ContinueOnSignTimeout:<True|False>]
  [-Log:<True|False>] [-LogFile:"<FILENAME>"] [-LogOverwrite:<True|False>]
  [-Verbose:<True|False>]
```

Examples:

```
IsExeSigned.exe -Files:"C:\Build\MyApp.exe"
IsExeSigned.exe -Files:"C:\Build\*.exe;*.dll"
IsExeSigned.exe -Files:"C:\Build\MyApp_<##>*.exe" -Recursive:False
IsExeSigned.exe -Files:"C:\Build\*.exe" -Verify:True
IsExeSigned.exe -Files:"C:\Build\*.exe;*.dll" -VerifySigners:"*MyCompanyLtd*"
IsExeSigned.exe -Files:"C:\Build\*.exe;*.dll" -SignCommand:"C:\SignFile.bat %filename%"
IsExeSigned.exe -Files:"C:\Build\*.dll" -SignCommand:"C:\SignFile.bat %filename%" -SignFilter:"*\DllFiles\fb*.dll;*\Redistributables\*"
IsExeSigned.exe -Files:"C:\Build\*.exe;*.dll" -VerifySigners:"*MyCompanyLtd*" -LogFile:"C:\Build\Signatures.xml"
IsExeSigned.exe -Files:"C:\Build\*.exe;*.dll" -Verify:True -FailMode:FailOnError -LogFile:"C:\Build\Signatures.xml"
```

Output, with `Verbose` (the default) first the settings, then one line per file:

- `-` signed (and signature valid, when verified)  
- `*` not signed  
- `!` signed, but the signature is not valid (with the reason)  
- `>` not signed, running the sign command; the sign command's own output and the file's result line follow  

With `FailMode` `LogOnly` the lines of the files that failed the check have `ERROR:` after the marker. With several files a summary line follows, e.g. `3 file(s) checked, 1 of them unsigned, 1 signed now, 0 with invalid signature.`, and when a log is written, `Log written to "<file>"` is the last line.  

## Parameters

The parameters were renamed in 2026-10: `FileName` is now `Files`, and `ErrorIfNotSigned` is replaced by `FailMode`.

- **Files**  
  - Mandatory  
  - Either a single file, or a directory followed by one or more wildcard patterns separated by `;`  
  - Patterns are matched against the file name only, case-insensitively  
  - Wildcards (see [Delphi.WildCardMatcher](Source/3rdParty/Delphi.WildCardMatcher)):  
    - `*` zero or more characters, `?` exactly one character  
    - `<#>`, `<###>` exactly that many digits  
    - `<abc>`, `<a-z>`, `<!abc>` one character in / not in the set  
    - `<"foo"|"bar">` one of the listed strings  
  - All wildcard characters are ones Windows does not allow in file names, so any valid file name is taken as a plain file name, e.g. `C:\Build\App[x64] #2.exe`  

- **FailMode**  
  - Optional (`Auto`, `FailOnError` or `LogOnly`), default `Auto`  
  - `Auto`: `LogOnly` if a log is written (`Log` or `LogFile` given), otherwise `FailOnError`  
  - `FailOnError`: any error found while checking sets its exit code: a file not signed → `1`, a verified signature not valid → `5`, sign command timeout → `7`, no files match the pattern → `3`  
  - `LogOnly`: the errors are only reported, the exit code stays `0`. On the console the file's line has `ERROR:`, and in the log the test case is an error (`label="Error"`), so the log is where the failures show  
  - Command line errors (exit codes `2`, `3` and `6` found before checking any file) and exit code `4` are set in every mode  

- **Recursive**  
  - Optional (`True` or `False`), default `True`  
  - Only used with a pattern: also search the sub directories  

- **Verify**  
  - Optional (`True` or `False`), default `False`  
  - Verifies the signature of every signed file → ExitCode = `5` if any is not valid (with `FailMode` `FailOnError`)  
  - A signature is valid when:  
    - the file has not been modified after signing  
    - the signing certificate chains up to a trusted root certificate  
    - the signing certificate was valid when the file was signed (timestamped signature), or is still valid now (no timestamp) — so a non-timestamped file goes invalid when its certificate expires  

- **VerifySigners**  
  - Optional, one or more signer name patterns separated by `;` (same wildcards as above, case-insensitive)  
  - Verifies the signature only for the files whose signer name matches, other signed files are just listed  
  - Giving it turns verifying on, `Verify` is not needed  

- **SignCommand**  
  - Optional, command run for each unsigned file, before the signature checks  
  - Must contain `%filename%` (case-insensitive), it is replaced with the quoted full path of the file → if missing, ExitCode = `6`  
  - Run through `cmd.exe`, so batch files work; its output goes to the same console, and a non-zero exit code is reported  
  - After the command the file is checked again: if it is signed now, its signature is always verified, also without `Verify` and whatever `VerifySigners` says; if it is still not signed, it counts as unsigned  
  - Quotes inside the value do not get through the command line parsing, so a sign tool in a path with spaces (e.g. `signtool.exe` under `Program Files`) has to be called from a batch file  
  - The sign command gets the file name as its parameter, e.g. in `SignFile.bat` as `%1` (quoted) or `%~1` (without quotes)  
  - If IsExeSigned itself is started from a batch file (e.g. a CI build script), write `%%filename%%` there, otherwise `cmd.exe` expands `%filename%` as an environment variable before IsExeSigned sees it  

- **SignFilter**  
  - Optional, one or more patterns separated by `;` (same wildcards as above, case-insensitive), needs `SignCommand`  
  - Matched against the **full path** of the file, e.g. `*\DllFiles\fb*.dll;*\Redistributables\*`  
  - Only unsigned files that match are signed; if not given, all unsigned files are signed  

- **SignTimeout**  
  - Optional, seconds (`1`–`86400`), default `60`  
  - How long the sign command may run for one file; after that it is stopped, including any processes it started  
  - The timeout is reported as an error on the file's line  

- **ContinueOnSignTimeout**  
  - Optional (`True` or `False`), default `False`  
  - `False`: stop at the first sign command timeout → ExitCode = `7` (with `FailMode` `FailOnError`); the log is still written  
  - `True`: continue with the next file; the timed out file counts as unsigned (unless the command signed it before it was stopped)  

- **Log**  
  - Optional (`True` or `False`), default `False`  
  - Writes an NUnit 3 XML log; without `LogFile` to `IsExeSigned.xml` in the folder of `IsExeSigned.exe`  

- **LogFile**  
  - Optional, the NUnit 3 XML log file; giving it writes the log, `Log` is not needed  
  - The directory must exist, the file does not have to; a relative name is relative to the current directory  

- **LogOverwrite**  
  - Optional (`True` or `False`), default `True`  
  - `False` and the log file exists → ExitCode = `3`, checked before anything else is done  

- **Verbose**  
  - Optional (`True` or `False`), default `True`  
  - Writes the effective settings before anything else is done, also before the parameter values are checked: the defaults filled in, `FailMode` `Auto` resolved (e.g. `LogOnly (Auto)`), `Verify` `True` when `VerifySigners` is given, and the full path of the log file  

## Log

The log is an NUnit 3 result file (UTF-8, without BOM), written with [Delphi.NUnitLogger](Source/3rdParty/Delphi.NUnitLogger): `test-run` named `IsExeSigned` > `test-suite` of type Assembly (with the environment) > `test-suite` `Signatures` > one `test-case` per checked file, named by its full path.

- passed: signed (and signature valid, when verified); the message tells the signer, e.g. `Signed by "My Company Ltd", signature is valid`  
- failed: signature not valid, or not signed, with `FailMode` `FailOnError`; the message tells why, e.g. the Windows error of an invalid signature  
- error (`label="Error"`): the same with `FailMode` `LogOnly` (or `Auto`, as a log is written); a sign command timeout that stopped the run; no files match the pattern; or an unexpected exception while checking the file (the message has the exception)  

Times: a file's test case runs from the start of its check to the end, signing included, the `Signatures` suite for the whole run. Durations are measured with a stopwatch and written in seconds with six decimals, like NUnit does. "No files match the pattern" is a zero length test case.

The log is written also when the run stops early (sign command timeout, unexpected exception); not when the command line itself is invalid.  

## Exit codes

Exit codes `1`, `5`, `7` and the "no files match the pattern" case of `3` come from checking the files, so they are set only with `FailMode` `FailOnError`. The others are set in every mode.

| Code | Meaning |
|------|---------|
| `0` | All files signed, and all verified signatures are valid; or `FailMode` is `LogOnly` (or `Auto` with a log) and the command line is valid |
| `1` | At least one file is not signed (takes precedence over `5`) |
| `2` | Invalid command line: `Files` missing, unknown parameter, or a parameter value is invalid (e.g. `SignTimeout` out of range) |
| `3` | File not found, pattern without a directory, directory not found, no files match the pattern, `SignFilter` without `SignCommand`, log file directory not found, or log file exists and `LogOverwrite` is `False` |
| `4` | Something unexpected happened (like an unhandled exception) |
| `5` | At least one verified signature is not valid |
| `6` | `SignCommand` does not contain `%filename%` |
| `7` | Sign command did not finish in `SignTimeout` seconds, and `ContinueOnSignTimeout` is `False` |

## Limitations

- Only signatures embedded in the file are detected; catalog-signed files (e.g. many Windows system files) are reported as not signed.  
- Certificate revocation is not checked, as it needs network access, which CI machines might not have.  
- For a file with multiple signatures (e.g. SHA-1 + SHA-256), only the primary one is verified.  
- The Win32 build runs as a 32-bit program, so Windows redirects paths under `C:\Windows\System32` to `C:\Windows\SysWOW64`; it checks the 32-bit copies of system files (or reports them missing). Use the Win64 build to check 64-bit system files. Your own build output is not affected.  

## Tests

DUnitX tests are in `UnitTests\`, with TestInsight support (the `Debug - TestInsight` / `Release - TestInsight` configurations). `IsExeSignedGroup.groupproj` has all the projects, IsExeSigned and the tests.

Most of the tests are integration tests that run `IsExeSigned.exe`, so build it first. The tests use the most recently built `Win32|Win64\Release|Debug\IsExeSigned.exe`, or the one the `ISEXESIGNED_EXE` environment variable names. Signed test files are copies of a validly signed Windows file (e.g. `tar.exe`), and signing is tested with fake sign tools (batch files), so nothing is installed or changed outside the temp folder.

From the command line (the default configuration is `Debug - TestInsight`, which runs nothing without TestInsight):

```
msbuild IsExeSigned.dproj /t:Build /p:Config=Release /p:Platform=Win32
msbuild UnitTests\IsExeSignedUnitTests.dproj /t:Build /p:Config=Debug /p:Platform=Win32
UnitTests\Win32\Debug\IsExeSignedUnitTests.exe --exitbehavior:Continue
```
