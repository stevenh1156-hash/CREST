Import-Module C:\dev\bannerlord\crest\tools\Crest.Dev.psm1 -Force

# 1. Restore the bundle staging from disk (Build-CrestBundle without rebuild)
Write-Host "==> Reassembling staging from existing builds..." -ForegroundColor Cyan
$ok = Build-CrestBundle -SkipBuild
if (-not $ok) { exit 1 }

# 2. Rewrite the master SubModule.xml to the 3-SubModule test config
#    (Harmony + ButterLib + UIExtenderEx, no MCM, no BEW)
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

# 3. Use BEW's Newtonsoft.Json v12 (replace the v13 in staging)
$bewNewton = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\BetterExceptionWindow\bin\Win64_Shipping_Client\Newtonsoft.Json.dll'
$stageBin = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'
if (Test-Path $bewNewton) {
    Copy-Item $bewNewton -Destination $stageBin -Force
}

# 4. Verify the diagnostic-instrumented Harmony DLL is what's in staging
$harmonyDll = Join-Path $stageBin 'Crest.Harmony.dll'
if (Test-Path $harmonyDll) {
    $age = ((Get-Date) - (Get-Item $harmonyDll).LastWriteTime).TotalMinutes
    Write-Host ("==> Crest.Harmony.dll in staging is {0:N0}m old" -f $age)
}

# 5. Clear any old log
$logFile = 'C:\dev\bannerlord\crest\runtime.log'
if (Test-Path $logFile) { Remove-Item $logFile -Force }

# 6. Deploy
Deploy-CrestToBannerlord | Out-Null

# 7. Final verification
$deployedSm = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\SubModule.xml'
$smContent = Get-Content $deployedSm -Raw
$dllRefs = ([regex]::Matches($smContent, '<DLLName value="([^"]+)"')) | ForEach-Object { $_.Groups[1].Value }
Write-Host ""
Write-Host "==> Deployed SubModule.xml DLL references:" -ForegroundColor Cyan
$dllRefs | ForEach-Object { Write-Host "    $_" }

$deployedBin = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST\bin\Win64_Shipping_Client'
Write-Host ""
Write-Host ("==> Deployed bin\: {0} DLLs" -f (Get-ChildItem $deployedBin -Filter '*.dll' | Measure-Object).Count) -ForegroundColor Cyan

Write-Host ""
Write-Host "==> Try launching. If it crashes, the diagnostic log will write to" -ForegroundColor Green
Write-Host "    C:\dev\bannerlord\crest\runtime.log"
exit 0
