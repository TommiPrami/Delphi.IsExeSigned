# Delphi.IsExeSigned

A small utility to check if an `.exe` file is signed and grab the signer’s name.  

⚠️ Note: This tool **does not validate the signature** (at least not yet) — I just haven’t needed that so far. Right now it’s mainly used in CI as a sanity check: making sure the `.exe` files that *should* be signed actually are.  

## Usage

IsExeSigned.exe -FileName:"<FILENAME>" [-ErrorIfNotSigned:<True|False>]

## Parameters

- **FileName**  
  - Mandatory  
  - If missing → ExitCode = `2`  
  - File must exist  
    - If file not found → ExitCode = `3`  

- **ErrorIfNotSigned**  
  - Optional (`True` or `False`)  
  - If set to `True` and the file is not signed → ExitCode = `1`  

- **Other errors**  
  - If something unexpected happens (like an unhandled exception) → ExitCode = `4`
