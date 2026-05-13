$ErrorActionPreference = 'Continue'

# Replace the single ButterLib SubModule entry with the upstream two-entry pattern:
#   1. CREST ButterLib  -> Crest.ButterLib.ButterLibSubModule  (sets up DI)
#   2. CREST ButterLib Implementation Loader -> Crest.ButterLib.ImplementationLoaderSubModule  (loads impl)
# Both classes live in Crest.ButterLib.dll (the facade). The implementation DLL is
# loaded at runtime by ImplementationLoaderSubModule via reflection.

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
Set-Content -Path (Join-Path $crestDir 'SubModule.xml') -Value $xml -Encoding UTF8

# Also update staging copy
Set-Content -Path 'C:\dev\bannerlord\crest\dist\CREST\SubModule.xml' -Value $xml -Encoding UTF8

# Verify the classes referenced exist in the DLLs
$bin = Join-Path $crestDir 'bin\Win64_Shipping_Client'
Add-Type -Path (Join-Path $bin 'Mono.Cecil.dll')
$xmlObj = [xml](Get-Content (Join-Path $crestDir 'SubModule.xml') -Raw)
Write-Host "==> Verifying class refs:"
foreach ($s in $xmlObj.Module.SubModules.SubModule) {
    $name = $s.Name.value
    $dll = $s.DLLName.value
    $cls = $s.SubModuleClassType.value
    $found = $false
    try {
        $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $bin $dll))
        foreach ($mod in $asm.Modules) { foreach ($t in $mod.Types) { if ($t.FullName -eq $cls) { $found = $true } } }
        $asm.Dispose()
    } catch {}
    $color = if ($found) { 'Green' } else { 'Red' }
    Write-Host ("    [{0}] {1,-40} {2}::{3}" -f $(if ($found) {'OK '} else {'MISS'}), $name, $dll, $cls) -ForegroundColor $color
}

# Clear log + ready to test
$logFile = 'C:\dev\bannerlord\crest\runtime.log'
if (Test-Path $logFile) { Remove-Item $logFile -Force }

Write-Host ""
Write-Host "==> SubModule.xml updated with upstream's two-entry ButterLib pattern."
Write-Host "==> Try launching."
exit 0
