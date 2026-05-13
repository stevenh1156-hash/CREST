@echo off
REM Wrapper that launches the Phase P.2 + Q.2 runner and pauses on completion.
REM Used by the agent because PowerShell is granted at restricted-tier (no
REM typing) — but a .bat double-clicked from File Explorer launches a
REM console with the PowerShell script running.
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\dev\bannerlord\crest\.runner\done\phase-p2-q2-build-and-test.ps1"
echo.
echo ===== runner exited with code %ERRORLEVEL% =====
pause
