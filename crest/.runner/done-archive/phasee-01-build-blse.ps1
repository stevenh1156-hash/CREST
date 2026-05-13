$ErrorActionPreference = 'Continue'

Write-Host '==> Building BLSE from source' -ForegroundColor Cyan
$blseRoot = 'C:\dev\bannerlord\Bannerlord.BLSE'
$gameFolder = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord'

Push-Location $blseRoot
try {
    Write-Host '  branch / sha:'
    & git status --short --branch | Select-Object -First 1 | ForEach-Object { Write-Host ('    ' + $_) }
    Write-Host ''

    # Build the four launcher variants in dependency order
    # (Shared first, then each loader)
    $projects = @(
        'src\Bannerlord.BLSE.Shared\Bannerlord.BLSE.Shared.csproj',
        'src\Bannerlord.BLSE\Bannerlord.BLSE.csproj',
        'src\Bannerlord.LauncherEx\Bannerlord.LauncherEx.csproj',
        'src\Bannerlord.BLSE.Loaders.Launcher\Bannerlord.BLSE.Loaders.Launcher.csproj',
        'src\Bannerlord.BLSE.Loaders.LauncherEx\Bannerlord.BLSE.Loaders.LauncherEx.csproj',
        'src\Bannerlord.BLSE.Loaders.Standalone\Bannerlord.BLSE.Loaders.Standalone.csproj',
        'src\Bannerlord.BLSE.Loaders.AppDomainManager\Bannerlord.BLSE.Loaders.AppDomainManager.csproj'
    )

    foreach ($p in $projects) {
        $name = (Split-Path $p -Leaf) -replace '\.csproj$', ''
        Write-Host ('  building ' + $name) -ForegroundColor Cyan
        $args = @(
            'build', $p,
            '--configuration', 'Release',
            '-p:GameFolder=' + $gameFolder,
            '-p:GenerateDocumentationFile=false',
            '-nowarn:CS1591',
            '--nologo',
            '-v', 'quiet'
        )
        $output = & dotnet @args 2>&1
        $exit = $LASTEXITCODE
        if ($exit -eq 0) {
            $output | Where-Object { $_ -match 'Build succeeded' } | Select-Object -First 1 | ForEach-Object { Write-Host ('    ' + $_) -ForegroundColor Green }
        } else {
            Write-Host ('    FAIL exit=' + $exit) -ForegroundColor Red
            $output | Where-Object { $_ -match 'error |Build FAILED' } | Select-Object -First 8 | ForEach-Object { Write-Host ('      ' + $_) -ForegroundColor Red }
        }
    }

    Write-Host ''
    Write-Host '==> Built artifacts (find all .exe and .dll under bin/Release):' -ForegroundColor Cyan
    Get-ChildItem -Recurse "$blseRoot\src" -Include '*.exe','*.dll' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like '*\bin\Release\*' -and $_.FullName -notlike '*\publish\*' } |
        Sort-Object FullName |
        ForEach-Object {
            $rel = $_.FullName.Replace($blseRoot, '').TrimStart('\')
            Write-Host ('    ' + $_.Length + 'B  ' + $rel)
        }

    Write-Host ''
    Write-Host '==> Published artifacts (under publish/):' -ForegroundColor Cyan
    Get-ChildItem -Recurse "$blseRoot\src" -Include '*.exe','*.dll','*.config','*.runtimeconfig.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like '*\publish\*' } |
        Sort-Object FullName |
        ForEach-Object {
            $rel = $_.FullName.Replace($blseRoot, '').TrimStart('\')
            Write-Host ('    ' + $_.Length + 'B  ' + $rel)
        }
} finally { Pop-Location }
