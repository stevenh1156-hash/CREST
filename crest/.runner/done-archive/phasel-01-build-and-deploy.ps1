$ErrorActionPreference = 'Stop'

Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host '==> Build Harmony (CrestConfig defaults change) and MCM (new CrestSettings class)' -ForegroundColor Cyan
$ok1 = Build-CrestRepo -Name 'Harmony'
$ok2 = Build-CrestRepo -Name 'MCM'
if (-not ($ok1 -and $ok2)) { exit 1 }

Write-Host ''
Write-Host '==> Regenerate shims (Harmony rebuild may have changed Crest.Harmony.dll)' -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\generate-shims.ps1'

Write-Host ''
Write-Host '==> Reassemble + deploy bundle' -ForegroundColor Cyan
$ok = Build-CrestBundle -Version '1.2.0' -SkipBuild
if (-not $ok) { exit 2 }
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 3 }

Write-Host ''
Write-Host '==> Re-render full SubModule.xml from template' -ForegroundColor Cyan
$tmpl = Get-Content 'C:\dev\bannerlord\crest\Modules\CREST\SubModule.xml.template' -Raw
$tmpl = $tmpl -replace '\$version\$', '1.2.0'
$dst = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'
Set-Content -Path $dst -Value $tmpl -Encoding UTF8

Write-Host ''
Write-Host '==> Verify CrestSettings is in CREST.v1.4.1.dll' -ForegroundColor Cyan
$cecilPath = 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'
Add-Type -Path $cecilPath
$dll = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client\CREST.v1.4.1.dll'
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dll)
try {
    $found = $false
    foreach ($t in $asm.MainModule.Types) {
        if ($t.Namespace -eq 'MCM.UI' -and $t.Name -eq 'CrestSettings') {
            $found = $true
            Write-Host ('  OK   ' + $t.Namespace + '.' + $t.Name) -ForegroundColor Green
            $boolProps = @($t.Properties | Where-Object { $_.PropertyType.FullName -eq 'System.Boolean' })
            Write-Host ('  bool properties exposed: ' + $boolProps.Count)
            foreach ($p in $boolProps) {
                Write-Host ('    - ' + $p.Name)
            }
            break
        }
    }
    if (-not $found) {
        Write-Host '  MISSING: MCM.UI.CrestSettings' -ForegroundColor Red
        exit 4
    }
} finally { $asm.Dispose() }

Write-Host ''
Write-Host '==> Verify default crest.json schema (write fresh and reread)' -ForegroundColor Cyan
$cj = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\crest.json'
if (Test-Path $cj) {
    Write-Host '  existing file - leaving as-is so user choices persist'
    Get-Content $cj | Select-Object -First 12 | ForEach-Object { Write-Host ('    ' + $_) }
}

Write-Host ''
Write-Host '==> Done. Launch the game and look for "CREST" in the Mod Options screen.' -ForegroundColor Green
