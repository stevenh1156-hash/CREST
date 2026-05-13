$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

# Step 1: hard-reset all 4 fork repos to HEAD (kills namespace revert + RootNamespace + LightInject + ExcludeAssets edits)
Write-Host "==> Step 1: hard-reset all 4 fork repos to HEAD" -ForegroundColor Cyan
$repos = @(
    'C:\dev\bannerlord\Bannerlord.Harmony',
    'C:\dev\bannerlord\Bannerlord.ButterLib',
    'C:\dev\bannerlord\Bannerlord.UIExtenderEx',
    'C:\dev\bannerlord\Bannerlord.MBOptionScreen'
)
foreach ($r in $repos) {
    Push-Location $r
    try {
        Write-Host "---- $r ----" -ForegroundColor DarkCyan
        $before = (git status --short | Where-Object { $_ } | Measure-Object).Count
        git reset --hard HEAD 2>&1 | Out-Null
        git clean -fd src src-ui tests 2>&1 | Out-Null
        $after = (git status --short | Where-Object { $_ } | Measure-Object).Count
        Write-Host "  uncommitted before: $before  after: $after"
    } finally { Pop-Location }
}

# Step 2: re-apply ValidateLoadOrder neutering in 3 SubModule.cs files
# (these were uncommitted edits that got wiped by the reset; restore them)
Write-Host ""
Write-Host "==> Step 2: re-apply ValidateLoadOrder neutering" -ForegroundColor Cyan

# ButterLib
$bl = 'C:\dev\bannerlord\Bannerlord.ButterLib\src\Crest.ButterLib\ButterLibSubModule.cs'
$content = [System.IO.File]::ReadAllText($bl)
$old = "    public ButterLibSubModule()`r`n    {`r`n        Instance = this;`r`n`r`n        ValidateLoadOrder();`r`n    }"
$new = "    public ButterLibSubModule()`r`n    {`r`n        Instance = this;`r`n`r`n        // CREST hardening: ValidateLoadOrder neutered - upstream module check fails when CREST bundles all of BUTR.`r`n        // ValidateLoadOrder();`r`n    }"
if ($content -match 'public ButterLibSubModule\(\)\s*\{\s*Instance = this;\s*ValidateLoadOrder\(\);') {
    $content = $content -replace 'public ButterLibSubModule\(\)\s*\{\s*Instance = this;\s*ValidateLoadOrder\(\);\s*\}', "public ButterLibSubModule()`n    {`n        Instance = this;`n`n        // CREST hardening: ValidateLoadOrder neutered`n        // ValidateLoadOrder();`n    }"
    [System.IO.File]::WriteAllText($bl, $content, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  patched ButterLibSubModule.cs"
} else {
    Write-Host "  ! ButterLibSubModule.cs ctor pattern not found (already patched?)" -ForegroundColor Yellow
}

# UIExtenderEx
$ux = 'C:\dev\bannerlord\Bannerlord.UIExtenderEx\src\Crest.UIExtenderEx\SubModule.cs'
$content = [System.IO.File]::ReadAllText($ux)
if ($content -match 'public SubModule\(\)\s*\{\s*ValidateLoadOrder\(\);') {
    $content = $content -replace 'public SubModule\(\)\s*\{\s*ValidateLoadOrder\(\);\s*\}', "public SubModule()`n    {`n        // CREST hardening: ValidateLoadOrder neutered`n        // ValidateLoadOrder();`n    }"
    [System.IO.File]::WriteAllText($ux, $content, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  patched UIExtenderEx SubModule.cs"
} else {
    Write-Host "  ! UIExtenderEx SubModule.cs ctor pattern not found" -ForegroundColor Yellow
}

# Step 3: build all 4 forks (clean slate)
Write-Host ""
Write-Host "==> Step 3: build all 4 forks" -ForegroundColor Cyan
$ok = Build-AllCrestRepos -Clean
if (-not $ok) { Write-Error "Build failed"; exit 1 }

# Step 4: write a SubModule.xml.template with the original Crest.X.* class FQNs (no shim references)
Write-Host ""
Write-Host "==> Step 4: restore SubModule.xml.template to Crest.X.* FQNs" -ForegroundColor Cyan
$template = @'
<?xml version="1.0" encoding="UTF-8"?>
<Module xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance'
        xsi:noNamespaceSchemaLocation="https://raw.githubusercontent.com/BUTR/Bannerlord.XmlSchemas/master/SubModule.xsd">
  <Id value="CREST" />
  <Name value="CREST" />
  <Version value="v$version$" />
  <DefaultModule value="false" />
  <ModuleCategory value="Singleplayer" />
  <ModuleType value="Community" />
  <Url value="https://github.com/trashpanda/CREST" />
  <DependedModules />
  <ModulesToLoadAfterThis>
    <Module Id="Native" />
    <Module Id="SandBoxCore" />
    <Module Id="Sandbox" />
    <Module Id="StoryMode" />
    <Module Id="CustomBattle" />
  </ModulesToLoadAfterThis>
  <DependedModuleMetadatas />
  <SubModules>
    <SubModule>
      <Name value="CREST Harmony" />
      <DLLName value="Crest.Harmony.dll" />
      <SubModuleClassType value="Crest.Harmony.SubModule" />
      <Assemblies>
        <Assembly value="0Harmony.dll" />
        <Assembly value="Mono.Cecil.dll" />
        <Assembly value="Mono.Cecil.Mdb.dll" />
        <Assembly value="Mono.Cecil.Pdb.dll" />
        <Assembly value="Mono.Cecil.Rocks.dll" />
        <Assembly value="MonoMod.Core.dll" />
        <Assembly value="MonoMod.Backports.dll" />
        <Assembly value="MonoMod.Iced.dll" />
        <Assembly value="MonoMod.ILHelpers.dll" />
        <Assembly value="MonoMod.Utils.dll" />
      </Assemblies>
      <Tags />
    </SubModule>
    <SubModule>
      <Name value="CREST ButterLib" />
      <DLLName value="Crest.ButterLib.dll" />
      <SubModuleClassType value="Crest.ButterLib.ButterLibSubModule" />
      <Assemblies>
        <Assembly value="Microsoft.Bcl.HashCode.dll" />
        <Assembly value="Serilog.dll" />
        <Assembly value="Serilog.Extensions.Logging.dll" />
        <Assembly value="Serilog.Sinks.File.dll" />
      </Assemblies>
      <Tags />
    </SubModule>
    <SubModule>
      <Name value="CREST ButterLib Implementation Loader" />
      <DLLName value="Crest.ButterLib.dll" />
      <SubModuleClassType value="Crest.ButterLib.ImplementationLoaderSubModule" />
      <Assemblies />
      <Tags />
    </SubModule>
    <SubModule>
      <Name value="CREST UIExtenderEx" />
      <DLLName value="Crest.UIExtenderEx.dll" />
      <SubModuleClassType value="Crest.UIExtenderEx.SubModule" />
      <Tags />
    </SubModule>
    <SubModule>
      <Name value="CREST MCM" />
      <DLLName value="Crest.MCM.dll" />
      <SubModuleClassType value="Crest.MCM.MCMSubModule" />
      <Assemblies />
      <Tags />
    </SubModule>
    <SubModule>
      <Name value="CREST MCM Basic Implementation" />
      <DLLName value="Crest.MCM.dll" />
      <SubModuleClassType value="Crest.MCM.Internal.MCMImplementationSubModule" />
      <Assemblies />
      <Tags />
    </SubModule>
  </SubModules>
</Module>
'@
$tmplPath = 'C:\dev\bannerlord\crest\Modules\CREST\SubModule.xml.template'
[System.IO.File]::WriteAllText($tmplPath, $template, [System.Text.UTF8Encoding]::new($false))
Write-Host "  wrote $tmplPath"

# Step 5: bundle + deploy (no shim layer needed - Phase H is deferred)
Write-Host ""
Write-Host "==> Step 5: bundle + deploy" -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild -Version '1.0.0'
if (-not $ok) { exit 2 }
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 3 }

Write-Host ""
Write-Host "==> v1.0 BASELINE RESTORED - launch the game" -ForegroundColor Green
