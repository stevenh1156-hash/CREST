@echo off
set OUT=C:\dev\bannerlord\crest\.runner\done\run-phase-t.out.log
echo === run started %DATE% %TIME% === > "%OUT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\dev\bannerlord\crest\.runner\done\phase-t-build.ps1" >> "%OUT%" 2>&1
echo === run finished, exit code %ERRORLEVEL% === >> "%OUT%"
