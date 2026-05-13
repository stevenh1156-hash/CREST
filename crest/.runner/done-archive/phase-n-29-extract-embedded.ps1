$ErrorActionPreference = 'Continue'

$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'
$sharedDll = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.BLSE.Shared.dll'
$cecilDll = Join-Path $gameRoot 'Modules\CREST\bin\Win64_Shipping_Client\Mono.Cecil.dll'

[Reflection.Assembly]::LoadFrom($cecilDll) | Out-Null

Write-Host '==> Extract embedded LauncherEx from deployed BLSE.Shared.dll' -ForegroundColor Cyan
Write-Host ('  Shared DLL timestamp: ' + (Get-Item $sharedDll).LastWriteTime.ToString('HH:mm:ss'))

$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($sharedDll)
$resources = $asm.MainModule.Resources | Where-Object { $_.Name -match 'LauncherEx' }
Write-Host ''
Write-Host 'Embedded LauncherEx resources:' -ForegroundColor Cyan
foreach ($r in $resources) {
    Write-Host ('  ' + $r.Name + '  ' + $r.GetResourceData().Length + 'B')
}

# Decompress the v1.4.0 one and Cecil-load it
$res140 = $resources | Where-Object { $_.Name -match 'v1\.4\.0' } | Select-Object -First 1
if ($res140) {
    Write-Host ''
    Write-Host '==> Decompressing v1.4.0 LauncherEx' -ForegroundColor Cyan
    $bytes = $res140.GetResourceData()
    $ms = New-Object System.IO.MemoryStream(,$bytes)
    $gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
    $out = New-Object System.IO.MemoryStream
    $gz.CopyTo($out); $gz.Dispose(); $ms.Dispose()
    $rawBytes = $out.ToArray()
    Write-Host ('   raw size: ' + $rawBytes.Length + 'B')

    # Save to temp and cecil-load
    $tmpDll = Join-Path $env:TEMP 'launcherex-extracted.dll'
    [System.IO.File]::WriteAllBytes($tmpDll, $rawBytes)

    $extracted = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($tmpDll)
    $hide = $extracted.MainModule.Types | Where-Object { $_.Name -eq 'HideCrestStubsPatch' }
    if ($hide) {
        Write-Host ''
        Write-Host '==> HideCrestStubsPatch is embedded:' -ForegroundColor Green
        foreach ($m in $hide.Methods) { Write-Host ('   method: ' + $m.Name) }
    } else {
        Write-Host '==> HideCrestStubsPatch type NOT FOUND in embedded LauncherEx!' -ForegroundColor Red
    }

    # Check Manager.Enable for our call
    $mgr = $extracted.MainModule.Types | Where-Object { $_.Name -eq 'Manager' -and $_.Namespace -eq 'Bannerlord.LauncherEx' }
    if ($mgr) {
        $enable = $mgr.Methods | Where-Object { $_.Name -eq 'Enable' }
        if ($enable -and $enable.Body) {
            $callsHide = $enable.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'HideCrestStubsPatch' }
            if ($callsHide) {
                Write-Host ('==> Manager.Enable calls HideCrestStubsPatch (' + ($callsHide | Measure-Object).Count + ' refs)') -ForegroundColor Green
            } else {
                Write-Host '==> Manager.Enable does NOT call HideCrestStubsPatch!' -ForegroundColor Red
                Write-Host 'All method calls in Manager.Enable:'
                $enable.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] } |
                    ForEach-Object { Write-Host ('   ' + $_.Operand.DeclaringType.Name + '.' + $_.Operand.Name) }
            }
        }
    } else {
        Write-Host '==> Manager class NOT found' -ForegroundColor Red
    }
    $extracted.Dispose()
}

$asm.Dispose()
