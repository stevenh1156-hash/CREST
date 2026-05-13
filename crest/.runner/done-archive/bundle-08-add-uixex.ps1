$ErrorActionPreference = 'Continue'

# Step 2 of binary search: minimal CREST + UIExtenderEx.
# Crest.Harmony confirmed working alone. Adding UIExtenderEx to see if it loads.

$crestDir = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
$bin = Join-Path $crestDir 'bin\Win64_Shipping_Client'
$source = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'

Write-Host "==> Adding Crest.UIExtenderEx.dll..."
Copy-Item (Join-Path $source 'Crest.UIExtenderEx.dll') -Destination $bin -Force
Write-Host "    copied"

# Update SubModule.xml to add UIExtenderEx after Harmony
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
      <Name value="CREST UIExtenderEx" />
      <DLLName value="Crest.UIExtenderEx.dll" />
      <SubModuleClassType value="Crest.UIExtenderEx.SubModule" />
      <Tags />
    </SubModule>
  </SubModules>
</Module>
'@
Set-Content -Path (Join-Path $crestDir 'SubModule.xml') -Value $xml -Encoding UTF8

Write-Host ""
Write-Host "==> CREST + Harmony + UIExtenderEx deployed."
Write-Host "    bin DLLs:"
Get-ChildItem $bin -Filter '*.dll' | ForEach-Object { Write-Host "      $($_.Name)" }
Write-Host ""
Write-Host "==> Try launching. Same launcher state as before (CREST + Native only)."
exit 0
