$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$installBin = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client'

# Try Reflection-only load to avoid trying to actually run TaleWorlds-dependent code
foreach ($name in @('CREST.v1.4.1.dll','Crest.MCM.UI.Adapter.MCMv5.dll','Crest.MCM.dll')) {
    $p = Join-Path $installBin $name
    if (-not (Test-Path $p)) { continue }
    Write-Host ("==> " + $name) -ForegroundColor Cyan
    try {
        $bytes = [System.IO.File]::ReadAllBytes($p)
        $asm = [System.Reflection.Assembly]::ReflectionOnlyLoad($bytes)
        $types = $asm.GetTypes() | Where-Object { $_.FullName -match 'ModOptionsVM|IsCrestInternal' }
        if ($types) {
            foreach ($t in $types) {
                Write-Host ('   ' + $t.FullName) -ForegroundColor Green
                $methods = $t.GetMethods([System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::Static -bor [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::DeclaredOnly)
                foreach ($m in $methods) { Write-Host ('     method: ' + $m.Name) }
            }
        } else {
            Write-Host '   no matching types'
        }
    } catch {
        Write-Host ('   load EX: ' + $_.Exception.Message) -ForegroundColor Red
        if ($_.Exception.LoaderExceptions) {
            $_.Exception.LoaderExceptions | Select-Object -First 3 | ForEach-Object { Write-Host ('     ' + $_.Message) }
        }
    }
}
