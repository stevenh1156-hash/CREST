$ErrorActionPreference = 'Continue'

Write-Host "==> Last 3 Application Error event entries (last 10 min)..." -ForegroundColor Cyan
$evts = Get-WinEvent -LogName Application -MaxEvents 200 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.TimeCreated -gt (Get-Date).AddMinutes(-10) -and
        ($_.ProviderName -like '*Application Error*' -or
         $_.ProviderName -like '*.NET Runtime*')
    } |
    Select-Object -First 3
foreach ($e in $evts) {
    Write-Host ""
    Write-Host ("  {0:HH:mm:ss} {1} (id {2})" -f $e.TimeCreated, $e.ProviderName, $e.Id) -ForegroundColor Yellow
    $msg = $e.Message
    if ($msg.Length -gt 2500) { $msg = $msg.Substring(0,2500) + "..." }
    Write-Host $msg
}

Write-Host ""
Write-Host "==> Sysinternals/WER local crash dumps..." -ForegroundColor Cyan
$dumpDir = "$env:LOCALAPPDATA\CrashDumps"
if (Test-Path $dumpDir) {
    Get-ChildItem $dumpDir -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-10) } |
        ForEach-Object { Write-Host ("    {0:HH:mm:ss}  {1,9:N0}KB  {2}" -f $_.LastWriteTime, ($_.Length/1KB), $_.Name) }
}

Write-Host ""
Write-Host "==> WER ReportArchive (last 10 min)..." -ForegroundColor Cyan
$werRoot = "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive"
if (Test-Path $werRoot) {
    Get-ChildItem $werRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-10) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 3 |
        ForEach-Object {
            $r = Join-Path $_.FullName 'Report.wer'
            if (Test-Path $r) {
                Write-Host ""
                Write-Host "  $($_.Name):" -ForegroundColor Yellow
                Get-Content $r -ErrorAction SilentlyContinue | Select-Object -First 50 | ForEach-Object { Write-Host "    $_" }
            }
        }
}

Write-Host ""
Write-Host "==> Validate deployed SubModule.xml against schema..." -ForegroundColor Cyan
$xml = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'
if (Test-Path $xml) {
    try {
        $doc = [xml](Get-Content $xml -Raw)
        Write-Host "  XML well-formed: yes"
        Write-Host ("  Module Id: {0}" -f $doc.Module.Id.value)
        Write-Host ("  Version: {0}" -f $doc.Module.Version.value)
        $subs = @($doc.Module.SubModules.SubModule)
        Write-Host ("  SubModule count: {0}" -f $subs.Count)
        foreach ($s in $subs) {
            Write-Host ("    - {0}" -f $s.Name.value)
            Write-Host ("      DLL : {0}" -f $s.DLLName.value)
            Write-Host ("      Class: {0}" -f $s.SubModuleClassType.value)
        }
    } catch {
        Write-Host "  XML PARSE ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}
