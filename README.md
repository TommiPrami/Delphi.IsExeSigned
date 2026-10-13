# Delphi.IsExeSigned

A small utility to check if `.exe` / `.dll` files are signed, grab the signer’s name, and optionally check that the signature is valid.  

Right now it’s mainly used in CI as a sanity check: making sure the `.exe` files that *should* be signed actually are.  

## Usage

```
IsExeSigned.exe -FileName:"<FILENAME|PATH\PATTERN>" [-ErrorIfNotSigned:<True|False>] [-RecurseSubDirs:<True|False>]
  [-CheckIsSignatureValid:<True|False>] [-CheckSignatureSignerFilter:"<PATTERN>"]
```

Examples:

```
IsExeSigned.exe -FileName:"C:\Build\MyApp.exe"
IsExeSigned.exe -FileName:"C:\Build\*.exe;*.dll"
IsExeSigned.exe -FileName:"C:\Build\MyApp_<##>*.exe" -RecurseSubDirs:False
IsExeSigned.exe -FileName:"C:\Build\*.exe" -CheckIsSignatureValid:True
IsExeSigned.exe -FileName:"C:\Build\*.exe;*.dll" -CheckSignatureSignerFilter:"*MyCompanyLtd*"
```

Output, one line per file:

- `-` signed (and signature valid, when checked)  
- `*` not signed  
- `!` signed, but the signature is not valid (with the reason)  

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

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | All files signed (or `ErrorIfNotSigned` is `False`), and all checked signatures are valid |
| `1` | At least one file is not signed and `ErrorIfNotSigned` is `True` (takes precedence over `5`) |
| `2` | Invalid command line: `FileName` missing or a parameter value is invalid |
| `3` | File not found, pattern without a directory, directory not found, or no files match the pattern |
| `4` | Something unexpected happened (like an unhandled exception) |
| `5` | At least one checked signature is not valid |

## Limitations

- Only signatures embedded in the file are detected; catalog-signed files (e.g. many Windows system files) are reported as not signed.  
- Certificate revocation is not checked, as it needs network access, which CI machines might not have.  
- For a file with multiple signatures (e.g. SHA-1 + SHA-256), only the primary one is checked.  
