Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

Write-Host "==> Rebuilding all repos with auto-deploy disabled..." -ForegroundColor Cyan
$ok = Build-AllCrestRepos -Clean
if (-not $ok) { Write-Host "==> Builds failed" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "==> Confirming auto-deploy did NOT touch Modules\CREST..." -ForegroundColor Cyan
$crestDir = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
$smPath = Join-Path $crestDir 'SubModule.xml'
if (Test-Path $smPath) {
    $sm = Get-Content $smPath -Raw
    if ($sm -match 'CREST\.dll') {
        Write-Host "    auto-deploy still ran, DisableModuleCopy didn't take" -ForegroundColor Red
    } else {
        Write-Host "    Modules\CREST not overwritten (DisableModuleCopy works)" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "==> Assembling unified bundle from fresh build outputs..." -ForegroundColor Cyan
$built = Build-CrestBundle -SkipBuild
if (-not $built) { exit 1 }

# Three-SubModule SubModule.xml (Harmony + ButterLib + UIExtenderEx, no MCM/BEW)
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
Set-Content -Path 'C:\dev\bannerlord\crest\dist\CREST\SubModule.xml' -Value $xml -Encoding UTF8

# Newtonsoft.Json v12 (BEW-compatible, also fine for ButterLib)
$bewNewton = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\BetterExceptionWindow\bin\Win64_Shipping_Client\Newtonsoft.Json.dll'
$stageBin = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'
if (Test-Path $bewNewton) { Copy-Item $bewNewton -Destination $stageBin -Force }

# Clear log + deploy
$logFile = 'C:\dev\bannerlord\crest\runtime.log'
if (Test-Path $logFile) { Remove-Item $logFile -Force }
Deploy-CrestToBannerlord | Out-Null

$deployedCount = (Get-ChildItem 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client' -Filter '*.dll' | Measure-Object).Count
Write-Host ""
Write-Host ("==> Deployed: $deployedCount DLLs in Modules\CREST\bin\Win64_Shipping_Client") -ForegroundColor Green
Write-Host "==> Try launching. The runtime.log will capture every first-chance exception."
exit 0
