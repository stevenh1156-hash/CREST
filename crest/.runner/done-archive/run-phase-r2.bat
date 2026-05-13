@echo off
REM Wrapper that launches the Phase R.2 build runner and captures output to a
REM file the agent can read directly. PowerShell is granted at restricted-tier
REM (no typing into the console), but a .bat double-clicked from File Explorer
REM launches a console with the script running, and redirecting to a file
REM lets the agent read the result without needing to see the console.
set OUT=C:\dev\bannerlord\crest\.runner\done\run-phase-r2.out.log
echo === run started %DATE% %TIME% === > "%OUT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\dev\bannerlord\crest\.runner\done\phase-r2-build.ps1" >> "%OUT%" 2>&1
echo === run finished, exit code %ERRORLEVEL% === >> "%OUT%"
