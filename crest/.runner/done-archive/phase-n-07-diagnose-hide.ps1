$ErrorActionPreference = 'Continue'

Write-Host '==> Phase N: diagnose why HideCrestStubsPatch is not hiding stubs' -ForegroundColor Cyan

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$blseDll = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.LauncherEx.dll'

# ----- 1. Confirm CREST_SHOW_STUBS not set -----
Write-Host ''
Write-Host '[1/5] Environment variable CREST_SHOW_STUBS' -ForegroundColor Cyan
Write-Host ("  process-scope: " + ($env:CREST_SHOW_STUBS))
Write-Host ("  user-scope:    " + [Environment]::GetEnvironmentVariable('CREST_SHOW_STUBS','User'))
Write-Host ("  machine-scope: " + [Environment]::GetEnvironmentVariable('CREST_SHOW_STUBS','Machine'))

# ----- 2. Confirm deployed LauncherEx is fresh -----
Write-Host ''
Write-Host '[2/5] Deployed LauncherEx fingerprint' -ForegroundColor Cyan
$f = Get-Item $blseDll
Write-Host ("  path:    " + $f.FullName)
Write-Host ("  size:    " + ([math]::Round($f.Length/1KB)) + " KB")
Write-Host ("  written: " + $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
$srcDll = 'C:\dev\bannerlord\Bannerlord.BLSE\src\Bannerlord.LauncherEx\bin\Release_140\netstandard2.0\Bannerlord.LauncherEx.dll'
$srcF = Get-Item $srcDll
$identical = ((Get-FileHash $blseDll).Hash -eq (Get-FileHash $srcDll).Hash)
Write-Host ("  matches build output? " + $identical)

# ----- 3. Inspect the deployed DLL with Cecil to see if HideCrestStubsPatch is in there -----
Write-Host ''
Write-Host '[3/5] Cecil inspection: HideCrestStubsPatch type present?' -ForegroundColor Cyan
$cecilDll = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client\Mono.Cecil.dll'
[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($blseDll)
$hideTypes = $asm.MainModule.Types | Where-Object { $_.FullName -match 'HideCrestStubsPatch|Patches\..*Hide' }
if ($hideTypes) {
    foreach ($t in $hideTypes) {
        Write-Host ("  FOUND " + $t.FullName) -ForegroundColor Green
        foreach ($m in $t.Methods) {
            Write-Host ("    method: " + $m.Name + "(" + ($m.Parameters | ForEach-Object { $_.ParameterType.Name }) + ")")
        }
    }
} else {
    Write-Host '  NOT FOUND -- patch class is missing from deployed DLL' -ForegroundColor Red
}

# ----- 4. Confirm Manager.Enable references HideCrestStubsPatch -----
Write-Host ''
Write-Host '[4/5] Cecil inspection: Manager.Enable calls HideCrestStubsPatch.Enable?' -ForegroundColor Cyan
$mgr = $asm.MainModule.Types | Where-Object { $_.Name -eq 'Manager' -and $_.Namespace -eq 'Bannerlord.LauncherEx' }
if ($mgr) {
    $enable = $mgr.Methods | Where-Object { $_.Name -eq 'Enable' }
    if ($enable -and $enable.Body) {
        $callsHide = $enable.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'HideCrestStubsPatch' }
        if ($callsHide) {
            Write-Host ("  YES -- " + ($callsHide | Measure-Object).Count + " call(s) to HideCrestStubsPatch found in Manager.Enable") -ForegroundColor Green
        } else {
            Write-Host '  NO -- Manager.Enable does not call HideCrestStubsPatch' -ForegroundColor Red
        }
    }
}

# ----- 5. Inspect BUTRLauncherModuleVM.IsVisible to confirm property shape -----
Write-Host ''
Write-Host '[5/5] BUTRLauncherModuleVM.IsVisible property shape' -ForegroundColor Cyan
$vm = $asm.MainModule.Types | Where-Object { $_.Name -eq 'BUTRLauncherModuleVM' }
if ($vm) {
    $prop = $vm.Properties | Where-Object { $_.Name -eq 'IsVisible' }
    if ($prop) {
        Write-Host ("  property type: " + $prop.PropertyType.Name)
        Write-Host ("  has getter:    " + ($prop.GetMethod -ne $null))
        Write-Host ("  getter name:   " + $prop.GetMethod.Name)
        Write-Host ("  getter is private/internal? " + ($prop.GetMethod.IsAssembly))
    } else {
        Write-Host '  IsVisible property NOT FOUND on BUTRLauncherModuleVM' -ForegroundColor Red
    }
} else {
    Write-Host '  BUTRLauncherModuleVM type NOT FOUND' -ForegroundColor Red
}

$asm.Dispose()
