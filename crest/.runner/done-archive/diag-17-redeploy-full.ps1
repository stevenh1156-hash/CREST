$ErrorActionPreference = 'Stop'
Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Re-bundling (SkipBuild - all DLLs are already current)" -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild
if (-not $ok) { exit 1 }

Write-Host ""
Write-Host "==> Deploying to game folder" -ForegroundColor Cyan
$ok = Deploy-CrestToBannerlord
if (-not $ok) { exit 2 }

# Now keep the rename test active (Crest.MCM.UI.dll alongside CREST.v1.4.1.dll)
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$src = Join-Path $bin 'CREST.v1.4.1.dll'
$dst = Join-Path $bin 'Crest.MCM.UI.dll'
if (Test-Path $src) {
    Copy-Item $src $dst -Force
    Write-Host "==> Re-copied CREST.v1.4.1.dll -> Crest.MCM.UI.dll for the rename test"
}

# Write the 7-entry SubModule.xml (the same one we just used).
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

# Verify final state of bin
Write-Host ""
Write-Host "==> Final deployed state:" -ForegroundColor Cyan
Write-Host ("    Modules\CREST\: {0} files" -f (Get-ChildItem 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST' -Recurse -File | Measure-Object).Count)
Write-Host ("    bin folder:     {0} files" -f (Get-ChildItem $bin -File | Measure-Object).Count)
Write-Host ""
Write-Host ("    SubModule.xml: 8-entry full MCM, MCM UI pointing at Crest.MCM.UI.dll (renamed copy)") -ForegroundColor Green
Write-Host ""
Write-Host "==> READY - launch the game" -ForegroundColor Green
