# Hunt for crash artifacts. Write output to a file I can read directly from Cowork
# (sidesteps the runner stdout-capture race we keep hitting).
$ErrorActionPreference = 'Continue'
$outFile = 'C:\dev\bannerlord\crest\diag-output.txt'

function W($msg) { Add-Content -Path $outFile -Value $msg }

Set-Content -Path $outFile -Value "Crest diagnostic - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

$candidates = @(
    "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord\logs",
    "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord\Crashes",
    "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord\BUTR_CrashReports",
    "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord\CrashUploads",
    "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord\Configs",
    "$env:USERPROFILE\AppData\Local\Mount and Blade II Bannerlord",
    "$env:LOCALAPPDATA\Temp"
)

W ""
W "==> Recent Bannerlord-related files (last 60 minutes):"
$cutoff = (Get-Date).AddMinutes(-60)
$found = @()
foreach ($d in $candidates) {
    if (Test-Path $d) {
        $files = Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt $cutoff }
        foreach ($f in $files) {
            $found += $f
            $age = ((Get-Date) - $f.LastWriteTime).TotalMinutes
            W ("    {0,5:N0}m  {1,8:N1}KB  {2}" -f $age, ($f.Length/1KB), $f.FullName)
        }
    }
}
W ""
W "==> Total found: $($found.Count)"

if ($found.Count -gt 0) {
    W ""
    W "==> Tails of any text/log files found:"
    foreach ($f in ($found | Where-Object { $_.Extension -in '.txt','.log','.html','.json','.xml' } | Select-Object -First 5)) {
        W ""
        W "----- $($f.FullName) -----"
        try {
            Get-Content $f.FullName -Tail 60 -ErrorAction Stop | ForEach-Object { W "    $_" }
        } catch {
            W "    (could not read: $_)"
        }
    }
}

W ""
W "==> Launcher config (LauncherData.xml) — what mods were enabled:"
$cfg = "$env:USERPROFILE\Documents\Mount and Blade II Bannerlord\Configs\LauncherData.xml"
if (Test-Path $cfg) {
    try {
        $xml = [xml](Get-Content $cfg -Raw)
        $modsNode = $xml.SelectNodes('//SingleplayerData/ModDatas/UserModData')
        W "    Singleplayer mod load order:"
        foreach ($m in $modsNode) {
            $marker = if ($m.IsSelected -eq 'true') { 'X' } else { ' ' }
            W ("       [$marker] $($m.Id)")
        }
    } catch {
        W "    (parse error: $_)"
    }
} else {
    W "    LauncherData.xml not found"
}

W ""
W "==> CREST module folder integrity check:"
$crestDir = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
if (Test-Path $crestDir) {
    $sm = Join-Path $crestDir 'SubModule.xml'
    if (Test-Path $sm) {
        try {
            $xml = [xml](Get-Content $sm -Raw)
            W "    SubModule.xml: parsed OK"
            W ("    Module Id: {0}, Name: {1}, Version: {2}" -f $xml.Module.Id.value, $xml.Module.Name.value, $xml.Module.Version.value)
            W "    SubModule entries:"
            foreach ($s in $xml.Module.SubModules.SubModule) {
                W ("       - {0}: DLL={1}, Class={2}" -f $s.Name.value, $s.DLLName.value, $s.SubModuleClassType.value)
            }
        } catch {
            W "    SubModule.xml PARSE ERROR: $_"
        }
    }
    $bin = Join-Path $crestDir 'bin\Win64_Shipping_Client'
    $dlls = Get-ChildItem $bin -Filter '*.dll' -ErrorAction SilentlyContinue
    W ("    bin DLL count: $($dlls.Count)")
}

W ""
W "==> Diagnostic complete."
"DONE: $outFile"
