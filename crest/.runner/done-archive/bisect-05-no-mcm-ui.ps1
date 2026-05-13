$ErrorActionPreference = 'Stop'
$target = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'

# 4 working entries + MCM abstraction + MCM basic impl. UI Adapter and UI dropped.
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
  </SubModules>
</Module>
'@

Set-Content -Path $target -Value $xml -Encoding UTF8
Write-Host "==> 6-entry config: 4 working + MCM abstraction + MCM impl (no UI)"
$xmldoc = [xml](Get-Content $target -Raw)
$subs = @($xmldoc.Module.SubModules.SubModule)
foreach ($s in $subs) { Write-Host ("    - {0}" -f $s.Name.value) }
