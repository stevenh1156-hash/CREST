$ErrorActionPreference = 'Continue'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Step 1: clean MCM build (forces SDK to re-evaluate AssemblyName)" -ForegroundColor Cyan
$ok = Build-CrestRepo -Name 'MCM' -Clean
if (-not $ok) { Write-Error "MCM build failed"; exit 1 }

# Verify the built artifact name
$mcmUiOut = 'C:\dev\bannerlord\Bannerlord.MBOptionScreen\src-ui\Crest.MCM.UI\bin\Stable_Release\netstandard2.0'
Write-Host ""
Write-Host "==> MCM.UI build output (looking for Crest.MCM.UI.dll instead of CREST.v1.4.1.dll):" -ForegroundColor Cyan
Get-ChildItem $mcmUiOut -Filter '*.dll' | Sort-Object Name | ForEach-Object {
    Write-Host ("    {0,9:N0}B  {1}" -f $_.Length, $_.Name)
}

# Re-bundle. The bundle's allowlist accepts both naming patterns so it will pick
# up whatever name the build produces.
Write-Host ""
Write-Host "==> Step 2: re-bundle (SkipBuild)" -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild
if (-not $ok) { exit 2 }

Write-Host ""
Write-Host "==> Step 3: deploy" -ForegroundColor Cyan
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 3 }

# Write the 8-entry SubModule.xml referring to Crest.MCM.UI.dll (the new clean name).
$target = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'
$xml = @'
<?xml version="1.0" encoding="UTF-8"?>
<Module xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance'
        xsi:noNamespaceSchemaLocation="https://raw.githubusercontent.com/BUTR/Bannerlord.XmlSchemas/master/SubModule.xsd">
  <Id value="CREST" />
  <Name value="CREST" />
  <Version value="v1.0.0" />
  <DefaultModule value="false" />
  <ModuleCategory value="Singleplayer" />
  <ModuleType value="Community" />
  <DependedModules />
  <ModulesToLoadAfterThis>
    <Module Id="Native" />
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
    <SubModule>
      <Name value="CREST MCM UI Adapter MCMv5" />
      <DLLName value="Crest.MCM.UI.dll" />
      <SubModuleClassType value="Crest.MCM.UI.MCMUIAdapterSubModule" />
      <Assemblies>
        <Assembly value="Crest.MCM.UI.Adapter.MCMv5.dll" />
      </Assemblies>
      <Tags />
    </SubModule>
    <SubModule>
      <Name value="CREST MCM UI" />
      <DLLName value="Crest.MCM.UI.dll" />
      <SubModuleClassType value="Crest.MCM.UI.MCMUISubModule" />
      <Assemblies />
      <Tags />
    </SubModule>
  </SubModules>
</Module>
'@
Set-Content -Path $target -Value $xml -Encoding UTF8

Write-Host ""
Write-Host "==> Verify deployed bin folder:" -ForegroundColor Cyan
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$found = Get-ChildItem $bin -Filter 'Crest.MCM.UI*.dll'
$found | ForEach-Object { Write-Host ("    {0,9:N0}B  {1}" -f $_.Length, $_.Name) }
$crest141 = Join-Path $bin 'CREST.v1.4.1.dll'
if (Test-Path $crest141) {
    Write-Host ("    [stale]      CREST.v1.4.1.dll  - removing it") -ForegroundColor Yellow
    Remove-Item $crest141 -Force
}

# Verify defined-asm name in the new DLL
$dllPath = Join-Path $bin 'Crest.MCM.UI.dll'
if (Test-Path $dllPath) {
    Add-Type -AssemblyName System.Reflection
    try {
        $asm = [System.Reflection.AssemblyName]::GetAssemblyName($dllPath)
        Write-Host ""
        Write-Host ("==> Crest.MCM.UI.dll defined-asm name: {0} v{1}" -f $asm.Name, $asm.Version) -ForegroundColor Green
        if ($asm.Name -eq 'Crest.MCM.UI') {
            Write-Host "    SUCCESS - assembly is now named cleanly!" -ForegroundColor Green
        } else {
            Write-Host ("    WARNING - assembly name is still '{0}', SDK override may not have taken effect" -f $asm.Name) -ForegroundColor Yellow
        }
    } catch {
        Write-Host "    GetAssemblyName failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "==> READY - launch the game" -ForegroundColor Green
