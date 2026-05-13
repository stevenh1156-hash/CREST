$ErrorActionPreference = 'Stop'
$target = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'

# 6 working + MCM UI Adapter MCMv5 only (NOT MCMUISubModule). If this crashes,
# MCMUIAdapterSubModule is the killer (it Harmony-patches Module.SetInitialModuleScreenAsRootScreen
# in OnSubModuleLoad). If it works, the killer is MCMUISubModule.
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
      <DLLName value="CREST.v1.4.1.dll" />
      <SubModuleClassType value="Crest.MCM.UI.MCMUIAdapterSubModule" />
      <Assemblies>
        <Assembly value="Crest.MCM.UI.Adapter.MCMv5.dll" />
      </Assemblies>
      <Tags />
    </SubModule>
  </SubModules>
</Module>
'@

Set-Content -Path $target -Value $xml -Encoding UTF8
Write-Host "==> 7-entry config: 6 working + MCM UI Adapter (no MCMUISubModule)"
$xmldoc = [xml](Get-Content $target -Raw)
$subs = @($xmldoc.Module.SubModules.SubModule)
foreach ($s in $subs) { Write-Host ("    - {0}" -f $s.Name.value) }
