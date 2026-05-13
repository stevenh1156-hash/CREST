$ErrorActionPreference = 'Continue'

# Three-SubModule test: Harmony + UIExtenderEx + ButterLib only.
# Drops MCM and BEW from SubModule.xml. Bin folder keeps all DLLs (extras don't load).

$crestDir = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'

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
      <DLLName value="Crest.ButterLib.Implementation.dll" />
      <SubModuleClassType value="Crest.ButterLib.Implementation.SubModule" />
      <Assemblies>
        <Assembly value="Crest.ButterLib.dll" />
        <Assembly value="Newtonsoft.Json.dll" />
      </Assemblies>
      <Tags />
    </SubModule>
    <SubModule>
      <Name value="CREST UIExtenderEx" />
      <DLLName value="Crest.UIExtenderEx.dll" />
      <SubModuleClassType value="Crest.UIExtenderEx.SubModule" />
      <Tags />
    </SubModule>
  </SubModules>
</Module>
'@
Set-Content -Path (Join-Path $crestDir 'SubModule.xml') -Value $xml -Encoding UTF8

Write-Host "==> SubModule.xml updated to 3 entries (Harmony + ButterLib + UIExtenderEx)."
Write-Host "    bin folder DLLs unchanged (extras present but unused)."
Write-Host ""
Write-Host "==> Try launching. If THIS crashes, ButterLib is definitely the trigger."
Write-Host "    If it works, MCM or BEW is the trigger and we'll add those one at a time."
exit 0
