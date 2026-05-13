@echo off
set OUT=C:\dev\bannerlord\crest\.runner\done\run-phase-u1.out.log
echo === run started %DATE% %TIME% === > "%OUT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\dev\bannerlord\crest\.runner\done\phase-u1-rebuild-against-v142.ps1" >> "%OUT%" 2>&1
echo === run finished, exit code %ERRORLEVEL% === >> "%OUT%"
