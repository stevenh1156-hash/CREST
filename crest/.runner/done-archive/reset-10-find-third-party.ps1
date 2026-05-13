$ErrorActionPreference = 'Continue'

# Find Microsoft.Extensions, Serilog, BUTR.CrashReport DLLs in NuGet cache
$nugetCache = "$env:USERPROFILE\.nuget\packages"

$wantedPackages = @(
    'microsoft.bcl.hashcode',
    'microsoft.extensions.dependencyinjection',
    'microsoft.extensions.dependencyinjection.abstractions',
    'microsoft.extensions.logging',
    'microsoft.extensions.logging.abstractions',
    'microsoft.extensions.options',
    'microsoft.extensions.primitives',
    'serilog',
    'serilog.extensions.logging',
    'serilog.sinks.file',
    'butr.crashreport',
    'butr.crashreport.models',
    'butr.crashreport.renderer.html',
    'butr.crashreport.renderer.imgui',
    'butr.crashreport.renderer.winforms',
    'butr.crashreport.renderer.zip',
    'system.buffers',
    'system.collections.immutable',
    'system.memory',
    'system.numerics.vectors',
    'system.runtime.compilerservices.unsafe'
)

foreach ($pkg in $wantedPackages) {
    $pkgDir = Join-Path $nugetCache $pkg
    if (Test-Path $pkgDir) {
        # Find latest version
        $versions = Get-ChildItem $pkgDir -Directory | Sort-Object Name -Descending
        if ($versions.Count -gt 0) {
            $latestVersion = $versions[0].Name
            $libDir = Join-Path $versions[0].FullName 'lib'
            if (Test-Path $libDir) {
                # Find best TFM match (prefer netstandard2.0, then net472)
                $tfms = @('netstandard2.0','netstandard2.1','net472','net48','net471','net46','net6.0','netstandard1.3')
                $tfm = $tfms | Where-Object { Test-Path (Join-Path $libDir $_) } | Select-Object -First 1
                if ($tfm) {
                    $tfmDir = Join-Path $libDir $tfm
                    $dlls = Get-ChildItem $tfmDir -Filter '*.dll' -ErrorAction SilentlyContinue
                    Write-Host ("[FOUND] {0,-50} v{1,-12} {2,-15} ({3} dlls)" -f $pkg, $latestVersion, $tfm, $dlls.Count) -ForegroundColor Green
                    $dlls | ForEach-Object { Write-Host ("            {0}" -f $_.Name) }
                } else {
                    Write-Host ("[?] {0,-50} v{1} - no matching TFM (have: {2})" -f $pkg, $latestVersion, ((Get-ChildItem $libDir -Directory | ForEach-Object { $_.Name }) -join ', ')) -ForegroundColor Yellow
                }
            }
        }
    } else {
        Write-Host ("[MISS] {0}" -f $pkg) -ForegroundColor Red
    }
}
