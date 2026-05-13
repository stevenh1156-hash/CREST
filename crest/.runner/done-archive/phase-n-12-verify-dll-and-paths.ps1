$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$blseDll = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.LauncherEx.dll'

# 1. Confirm deployed DLL has the DEBUG-LOGGING version
Write-Host '==> Cecil: does deployed DLL contain DebugLog method?' -ForegroundColor Cyan
$cecilDll = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client\Mono.Cecil.dll'
[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($blseDll)
$hide = $asm.MainModule.Types | Where-Object { $_.Name -eq 'HideCrestStubsPatch' }
foreach ($m in $hide.Methods) {
    $params = ($m.Parameters | ForEach-Object { $_.ParameterType.Name }) -join ', '
    Write-Host ("   " + $m.Name + "(" + $params + ")")
}
$asm.Dispose()
Write-Host ("   deployed at: " + (Get-Item $blseDll).LastWriteTime.ToString('HH:mm:ss'))

# 2. Look for ANY CREST/BLSE log files that DID get written this launcher session
Write-Host ''
Write-Host '==> Recent log files (any) under ModLogs / Configs ==' -ForegroundColor Cyan
$docs = [Environment]::GetFolderPath('MyDocuments')
$modLogs = Join-Path $docs 'Mount and Blade II Bannerlord\Configs\ModLogs'
if (Test-Path $modLogs) {
    Get-ChildItem $modLogs -File | Sort-Object LastWriteTime -Descending | Select-Object -First 8 |
        ForEach-Object { Write-Host ("   " + $_.LastWriteTime.ToString('HH:mm:ss') + "  " + $_.Name + "  " + $_.Length + "B") }
} else {
    Write-Host "   (ModLogs dir not found at $modLogs)"
}

# 3. CREST runtime.log, BLSE_lasterror.log
Write-Host ''
Write-Host '==> CREST runtime.log' -ForegroundColor Cyan
$rtLog = Join-Path $gameRoot 'Modules\CREST\runtime.log'
if (Test-Path $rtLog) {
    $lf = Get-Item $rtLog
    Write-Host ("   " + $lf.LastWriteTime.ToString('HH:mm:ss') + "  " + $lf.Length + "B")
    Get-Content $rtLog -Tail 20 | ForEach-Object { Write-Host ("     " + $_) }
} else {
    Write-Host "   (no runtime.log)"
}

Write-Host ''
Write-Host '==> BLSE_lasterror.log' -ForegroundColor Cyan
$blseErr = Join-Path $gameRoot 'bin\Win64_Shipping_Client\BLSE_lasterror.log'
if (Test-Path $blseErr) {
    $lf = Get-Item $blseErr
    Write-Host ("   " + $lf.LastWriteTime.ToString('HH:mm:ss') + "  " + $lf.Length + "B")
    Get-Content $blseErr -Tail 30 | ForEach-Object { Write-Host ("     " + $_) }
} else {
    Write-Host "   (no BLSE_lasterror.log)"
}

# 4. Did the launcher process even load our patched DLL? Check NTFS Zone.Identifier
Write-Host ''
Write-Host '==> Zone.Identifier on deployed BLSE DLL' -ForegroundColor Cyan
$ads = Get-Content $blseDll -Stream Zone.Identifier -ErrorAction SilentlyContinue
if ($ads) {
    Write-Host "   ADS PRESENT (file may be blocked):" -ForegroundColor Yellow
    $ads | ForEach-Object { Write-Host ("     " + $_) }
} else {
    Write-Host "   no Zone.Identifier (file is unblocked)"
}
