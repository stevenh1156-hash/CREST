# Round 3 diagnostic: latest launch crashed before CREST runtime hook ran.
# Pull the most recent ModLogs/default file, check any BEW error.htm,
# verify each shim DLL can be loaded into a sandboxed AppDomain by Cecil,
# and inspect the deployed shim files for size/timestamp.

$ErrorActionPreference = 'Continue'
$documents = [Environment]::GetFolderPath('MyDocuments')
$cfgRoot   = Join-Path $documents 'Mount and Blade II Bannerlord'

Write-Host "==> Most recent ModLogs files (last 200 lines of newest)" -ForegroundColor Cyan
$latest = Get-ChildItem (Join-Path $cfgRoot 'Configs\ModLogs') -Filter 'default*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latest) {
    Write-Host ("  reading: {0}  modified {1}" -f $latest.FullName, $latest.LastWriteTime)
    Get-Content $latest.FullName -Tail 200 | ForEach-Object { Write-Host "    $_" }
} else {
    Write-Host "  (no ModLogs/default*.log)"
}

Write-Host ""
Write-Host "==> BEW error report (errorhtml.htm or similar)" -ForegroundColor Cyan
$bewArtifacts = @(
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\errorhtml.htm',
    'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\error.htm'
)
foreach ($p in $bewArtifacts) {
    if (Test-Path $p) {
        $f = Get-Item $p
        Write-Host ("  found: {0}  ({1} bytes, {2})" -f $f.Name, $f.Length, $f.LastWriteTime)
    }
}

Write-Host ""
Write-Host "==> Shim DLLs deployed in CREST bin (size, mtime, valid PE?)" -ForegroundColor Cyan
$shimNames = @('Bannerlord.Harmony.dll','Bannerlord.ButterLib.dll','Bannerlord.UIExtenderEx.dll','MCMv5.dll')
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$cecilPath = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'
Add-Type -Path $cecilPath
foreach ($n in $shimNames) {
    $p = Join-Path $bin $n
    if (-not (Test-Path $p)) {
        Write-Host "  MISSING: $n" -ForegroundColor Red
        continue
    }
    $f = Get-Item $p
    Write-Host ("  {0,-30} {1,9:N0}B  {2}" -f $n, $f.Length, $f.LastWriteTime)
    try {
        $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($p)
        try {
            Write-Host ("      Name={0}  Version={1}  ExportedTypes={2}" -f $asm.Name.Name, $asm.Name.Version, $asm.MainModule.ExportedTypes.Count)
            # Test that scope references resolve (i.e. each ExportedType points at a referenced assembly that exists)
            $scopes = $asm.MainModule.ExportedTypes | Group-Object { $_.Scope.Name } | ForEach-Object { $_.Name }
            Write-Host ("      Scopes referenced: {0}" -f ($scopes -join ', '))
            foreach ($s in $scopes) {
                $sf = Join-Path $bin "$s.dll"
                $present = Test-Path $sf
                $color = 'Green'; $st = 'OK'
                if (-not $present) { $color = 'Red'; $st = 'MISSING' }
                Write-Host ("        {0,-30} {1}" -f "$s.dll", $st) -ForegroundColor $color
            }
        } finally { $asm.Dispose() }
    } catch {
        Write-Host ("      CECIL READ FAILED: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "==> SubModule.xml currently deployed (first 60 lines)" -ForegroundColor Cyan
$sm = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'
if (Test-Path $sm) {
    Get-Content $sm -TotalCount 60 | ForEach-Object { Write-Host "  $_" }
}
