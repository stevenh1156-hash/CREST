$ErrorActionPreference = 'Stop'

# Same 4-entry XML, but with a parseable version string. Bannerlord's launcher
# parses Version with int.Parse on each dot-separated component, so any non-numeric
# suffix ("-bisect4") triggers FormatException at module-list load time.
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
  </SubModules>
</Module>
'@

Set-Content -Path $target -Value $xml -Encoding UTF8

Write-Host "==> 4-entry config redeployed with parseable version 'v1.0.0'"
Write-Host "    Length: $((Get-Item $target).Length) bytes"
$xmldoc = [xml](Get-Content $target -Raw)
Write-Host ("    Module Id: {0}" -f $xmldoc.Module.Id.value)
Write-Host ("    Version:   {0}" -f $xmldoc.Module.Version.value)
$subs = @($xmldoc.Module.SubModules.SubModule)
Write-Host ("    SubModule count: {0}" -f $subs.Count)
