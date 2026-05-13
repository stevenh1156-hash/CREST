$ErrorActionPreference = 'Continue'
$gameFolder = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

cd C:\dev\bannerlord\Bannerlord.ButterLib

Write-Host "==> Building Crest.ButterLib (main, Release)..." -ForegroundColor Cyan
dotnet build src/Crest.ButterLib/Crest.ButterLib.csproj --configuration Release -p:GameFolder=$gameFolder -p:OverrideGameVersion=v1.4.1 -p:GameVersionConstant=v141 -v quiet -nologo
$mainCode = $LASTEXITCODE

Write-Host ""
Write-Host "==> Building Crest.ButterLib.Implementation (Stable_Release)..." -ForegroundColor Cyan
dotnet build src/Crest.ButterLib.Implementation/Crest.ButterLib.Implementation.csproj --configuration Stable_Release -p:GameFolder=$gameFolder -p:OverrideGameVersion=v1.4.1 -p:GameVersionConstant=v141 -v quiet -nologo
$implCode = $LASTEXITCODE

Write-Host ""
Write-Host "==> exit codes: main=$mainCode, impl=$implCode"

if ($mainCode -eq 0 -and $implCode -eq 0) {
    Write-Host "==> ALL BUILDS GREEN" -ForegroundColor Green
    Get-ChildItem src\Crest.ButterLib\bin\Release -Recurse -Filter Crest.ButterLib.dll -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host ("    {0}KB  {1}" -f [math]::Round($_.Length/1KB,1), $_.FullName)
    }
    Get-ChildItem src\Crest.ButterLib.Implementation\bin -Recurse -Filter Crest.ButterLib.Implementation*.dll -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host ("    {0}KB  {1}" -f [math]::Round($_.Length/1KB,1), $_.FullName)
    }
} else {
    Write-Host "==> BUILD FAILED" -ForegroundColor Red
}
exit 0
