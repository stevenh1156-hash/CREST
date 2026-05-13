$ErrorActionPreference = 'Stop'
$bin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
$target = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'

$src = Join-Path $bin 'CREST.v1.4.1.dll'
$dst = Join-Path $bin 'Crest.MCM.UI.dll'

if (-not (Test-Path $src)) {
    Write-Error "Source DLL missing: $src"
    exit 1
}

# Keep the original file too (so .NET resolution works either way), but ALSO copy
# under the clean name. The internal AssemblyName is still 'CREST.v1.4.1' - this
# only tests whether Bannerlord's pre-load path-parsing chokes on the version-suffix
# in the filename.
Copy-Item $src $dst -Force
Write-Host ("==> Copied {0} -> {1}" -f (Split-Path $src -Leaf), (Split-Path $dst -Leaf))

# Write 7-entry SubModule.xml pointing at the renamed file
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
Write-Host "==> SubModule.xml now points MCMUI at Crest.MCM.UI.dll (was CREST.v1.4.1.dll)"
$xmldoc = [xml](Get-Content $target -Raw)
$subs = @($xmldoc.Module.SubModules.SubModule)
foreach ($s in $subs) { Write-Host ("    - {0}  ({1})" -f $s.Name.value, $s.DLLName.value) }
Write-Host ""
Write-Host "==> Bin folder now has both DLLs:"
Get-ChildItem $bin | Where-Object { $_.Name -in 'CREST.v1.4.1.dll', 'Crest.MCM.UI.dll' } | ForEach-Object {
    Write-Host ("    {0,9:N1}KB  {1}" -f ($_.Length/1KB), $_.Name)
}
