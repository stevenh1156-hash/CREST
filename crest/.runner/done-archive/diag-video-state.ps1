$ErrorActionPreference = 'Continue'
Add-Type -Path 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'

$mb = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\bin\Win64_Shipping_Client\TaleWorlds.MountAndBlade.dll'
$a = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($mb)
try {
    foreach ($t in $a.MainModule.Types) {
        $tname = "$($t.Namespace).$($t.Name)"
        if ($tname -match 'VideoPlayback|VideoPlay') {
            Write-Host ("==== $tname ====") -ForegroundColor Cyan
            Write-Host ("  Base: {0}" -f $t.BaseType)
            foreach ($f in $t.Fields) {
                Write-Host ("  field: {0,-30} {1}" -f $f.Name, $f.FieldType.Name)
            }
            foreach ($m in $t.Methods) {
                $params = ($m.Parameters | ForEach-Object { $_.ParameterType.Name }) -join ', '
                $vis = if ($m.IsPublic) { 'pub' } elseif ($m.IsAssembly) { 'int' } else { 'pri' }
                Write-Host ("  [{0}] {1}({2})" -f $vis, $m.Name, $params)
            }
            Write-Host ""
        }
    }

    # Search for TWLogo/Partners string literals - find which method holds them
    Write-Host "==== Methods with TWLogo/Partners in IL string literals ====" -ForegroundColor Cyan
    foreach ($t in $a.MainModule.Types) {
        foreach ($m in $t.Methods) {
            if (-not $m.HasBody) { continue }
            foreach ($instr in $m.Body.Instructions) {
                if ($instr.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldstr -and $instr.Operand -is [string]) {
                    $s = [string]$instr.Operand
                    if ($s -match 'TWLogo|Partners') {
                        Write-Host ("  FOUND in {0}.{1}::{2}  -> '{3}'" -f $t.Namespace, $t.Name, $m.Name, $s) -ForegroundColor Yellow
                    }
                }
            }
        }
    }
} finally { $a.Dispose() }
