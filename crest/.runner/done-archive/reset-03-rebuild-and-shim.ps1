$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

# Step 1: build all 4 forks with the reverted namespaces
Write-Host "==> Step 1: build all 4 forks (Bannerlord.X.* / MCM.* namespaces)" -ForegroundColor Cyan
$ok = Build-AllCrestRepos -Clean
if (-not $ok) { Write-Error "Build-AllCrestRepos failed"; exit 1 }

# Step 2: flip internals to public on the built DLLs
Write-Host ""
Write-Host "==> Step 2: flip internals to public on built Crest.X.dll" -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\flip-internals-public.ps1'

# Step 3: regenerate shims using the pure-Cecil generator
Write-Host ""
Write-Host "==> Step 3: regenerate shims" -ForegroundColor Cyan
& 'C:\dev\bannerlord\crest\shims\generate-shims.ps1'

# Step 4: list final shim outputs
Write-Host ""
Write-Host "==> Step 4: shim outputs" -ForegroundColor Cyan
Get-ChildItem -Recurse -Path 'C:\dev\bannerlord\crest\shims' -Filter '*.dll' -ErrorAction SilentlyContinue |
    Sort-Object Name |
    ForEach-Object { Write-Host ("    {0,9:N0}B  {1}" -f $_.Length, (Split-Path $_.FullName -Leaf)) }

# Step 5: sanity check - dump Harmony shim's first 5 forwarders
Write-Host ""
Write-Host "==> Step 5: shim forwarder sanity check" -ForegroundColor Cyan
Add-Type -Path 'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony\bin\Release\net472\Mono.Cecil.dll'
$harmonyShim = 'C:\dev\bannerlord\crest\shims\Bannerlord.Harmony.Shim\Bannerlord.Harmony.dll'
if (Test-Path $harmonyShim) {
    $a = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($harmonyShim)
    try {
        Write-Host ("  Bannerlord.Harmony.dll: {0} forwarders" -f $a.MainModule.ExportedTypes.Count)
        $a.MainModule.ExportedTypes | Select-Object -First 5 | ForEach-Object {
            Write-Host ("    {0}.{1}  ->  {2}" -f $_.Namespace, $_.Name, $_.Scope.Name)
        }
    } finally { $a.Dispose() }
}
