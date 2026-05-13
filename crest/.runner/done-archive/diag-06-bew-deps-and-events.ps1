$ErrorActionPreference = 'Continue'
$outFile = 'C:\dev\bannerlord\crest\diag-output.txt'
'BEW dep + EventViewer probe - ' + (Get-Date -Format 'HH:mm:ss') | Set-Content $outFile

# 1. Inspect BEW's assembly references via Cecil
$bin = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'
Add-Type -Path (Join-Path $bin 'Mono.Cecil.dll')

function Show-Refs($path, $label) {
    "" | Add-Content $outFile
    "=== $label ($([System.IO.Path]::GetFileName($path))) ===" | Add-Content $outFile
    if (-not (Test-Path $path)) { "  MISSING" | Add-Content $outFile; return }
    try {
        $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($path)
        "  AssemblyName: $($asm.Name.Name) v$($asm.Name.Version)" | Add-Content $outFile
        "  AssemblyReferences:" | Add-Content $outFile
        foreach ($mod in $asm.Modules) {
            foreach ($r in $mod.AssemblyReferences) {
                "    -> $($r.Name) v$($r.Version)" | Add-Content $outFile
            }
        }
        $asm.Dispose()
    } catch {
        "  Cecil error: $_" | Add-Content $outFile
    }
}

Show-Refs (Join-Path $bin 'BetterExceptionWindow.dll') 'BEW main'
Show-Refs (Join-Path $bin 'BetterExceptionWindowConfigUI.dll') 'BEW config UI'
Show-Refs (Join-Path $bin 'Crest.Harmony.dll') 'Crest.Harmony'
Show-Refs (Join-Path $bin 'Crest.ButterLib.Implementation.dll') 'Crest.ButterLib.Implementation'

# 2. Pull recent .NET CLR / Application errors from Windows Event Viewer
"" | Add-Content $outFile
"=== Windows Event Viewer: Application errors in last 30 min ===" | Add-Content $outFile
$cutoff = (Get-Date).AddMinutes(-30)
try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        Level = 1,2,3        # Critical, Error, Warning
        StartTime = $cutoff
    } -MaxEvents 50 -ErrorAction Stop | Where-Object {
        $_.ProviderName -in '.NET Runtime','Application Error','Windows Error Reporting','.NET Runtime Optimization Service' -or
        $_.Message -match 'Bannerlord|Mount.*Blade|TaleWorlds|Crest|CREST|ButterLib|UIExtender|MCM|Harmony|Lib\.Harmony'
    }
    "  Found $($events.Count) relevant events." | Add-Content $outFile
    foreach ($e in ($events | Select-Object -First 10)) {
        "" | Add-Content $outFile
        "  --- Event $($e.Id) at $($e.TimeCreated) [$($e.ProviderName)] ---" | Add-Content $outFile
        ($e.Message -split "`n" | Select-Object -First 30) | ForEach-Object {
            "    $_" | Add-Content $outFile
        }
    }
} catch {
    "  Event Viewer query error: $_" | Add-Content $outFile
}

"" | Add-Content $outFile
"=== Done ===" | Add-Content $outFile
