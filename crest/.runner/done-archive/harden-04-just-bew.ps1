$ErrorActionPreference = 'Continue'

# Two-SubModule test: Crest.Harmony + BEW only.
# BEW.dll has no Bannerlord.ButterLib dep at runtime - only 0Harmony, DotNetZip,
# Newtonsoft.Json, TaleWorlds, and framework refs. Should be a small isolated test.
# We are NOT including BetterExceptionWindowConfigUI.dll because it requires MCMv5.dll
# which we no longer have (we renamed to Crest.MCM).

$crestDir = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
$bin = Join-Path $crestDir 'bin\Win64_Shipping_Client'

# Wipe the deployed bin and recopy ONLY what minimal-Harmony+BEW needs
if (Test-Path $crestDir) { Remove-Item -Recurse -Force $crestDir }
New-Item -ItemType Directory -Path $bin -Force | Out-Null

$source = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'
$keep = @(
    # Harmony (proven working)
    'Crest.Harmony.dll',
    '0Harmony.dll',
    'Mono.Cecil.dll',
    'Mono.Cecil.Mdb.dll',
    'Mono.Cecil.Pdb.dll',
    'Mono.Cecil.Rocks.dll',
    'MonoMod.Core.dll',
    'MonoMod.Backports.dll',
    'MonoMod.Iced.dll',
    'MonoMod.ILHelpers.dll',
    'MonoMod.Utils.dll',
    # BEW (new)
    'BetterExceptionWindow.dll',
    'DotNetZip.dll',
    'Newtonsoft.Json.dll'
    # NOT BetterExceptionWindowConfigUI.dll (requires MCMv5 - skip for now)
)
foreach ($n in $keep) {
    $src = Join-Path $source $n
    if (Test-Path $src) { Copy-Item $src -Destination $bin -Force; Write-Host "    copied $n" }
    else { Write-Host "    MISSING source: $n" -ForegroundColor Red }
}

# BEW root assets (errorui.htm, config.json, solutions.json) and ModuleData\Languages
$bewSrc = "$($script:GameFolder)\Modules\BetterExceptionWindow"
if (-not $bewSrc -or -not (Test-Path 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\BetterExceptionWindow')) {
    $bewSrc = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\BetterExceptionWindow'
}
if (Test-Path $bewSrc) {
    foreach ($asset in 'errorui.htm','config.json','solutions.json') {
        $src = Join-Path $bewSrc $asset
        if (Test-Path $src) { Copy-Item $src -Destination $crestDir -Force }
    }
    $bewModData = Join-Path $bewSrc 'ModuleData'
    if (Test-Path $bewModData) {
        $destModData = Join-Path $crestDir 'ModuleData'
        New-Item -ItemType Directory -Path $destModData -Force | Out-Null
        Copy-Item -Recurse -Path (Join-Path $bewModData '*') -Destination $destModData -Force
    }
    Write-Host "    copied BEW assets"
}

# SubModule.xml: Harmony + BEW only
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
      <Name value="CREST BetterExceptionWindow" />
      <DLLName value="BetterExceptionWindow.dll" />
      <SubModuleClassType value="BetterExceptionWindow.Main" />
      <Assemblies>
        <Assembly value="DotNetZip.dll" />
      </Assemblies>
      <Tags>
        <Tag key="DedicatedServerType" value="none" />
        <Tag key="IsNoRenderModeElement" value="false" />
      </Tags>
    </SubModule>
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
  </SubModules>
</Module>
'@
Set-Content -Path (Join-Path $crestDir 'SubModule.xml') -Value $xml -Encoding UTF8

Write-Host ""
Write-Host "==> Minimal BEW-first deployment:"
Write-Host "  Root files:"
Get-ChildItem $crestDir -File | ForEach-Object { Write-Host "    $($_.Name)" }
Write-Host "  bin DLLs:"
Get-ChildItem $bin -Filter '*.dll' | Sort-Object Name | ForEach-Object { Write-Host "    $($_.Name)" }
Write-Host ""
Write-Host "==> Try launching."
Write-Host ""
Write-Host "Three possible outcomes:"
Write-Host "  (A) Game launches: BEW + Harmony coexist. We can add other components knowing"
Write-Host "      crashes will be caught. Move on to ButterLib next."
Write-Host "  (B) Game crashes silently again: BEW itself triggers the crash. Likely a"
Write-Host "      Newtonsoft.Json version mismatch (we ship 13.x, BEW expects 12.x)."
Write-Host "      Next test: ship Newtonsoft.Json v12 alongside, or use binding redirect."
Write-Host "  (C) Game launches AND BEW exception window appears showing the exception:"
Write-Host "      Even better - we now know exactly what's broken. Paste the message back."
exit 0
