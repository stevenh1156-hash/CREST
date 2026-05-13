$ErrorActionPreference = 'Continue'

$crestDir = 'C:\Program Files (x86)\Steam\steamapps\common\Mount & Blade II Bannerlord\Modules\CREST'
$bin = Join-Path $crestDir 'bin\Win64_Shipping_Client'
$source = 'C:\dev\bannerlord\crest\dist\CREST\bin\Win64_Shipping_Client'

Write-Host "==> Adding ButterLib + all its third-party dependencies..."

$add = @(
    'Crest.ButterLib.dll',
    'Crest.ButterLib.Implementation.dll',
    'Newtonsoft.Json.dll',
    'Microsoft.Bcl.HashCode.dll',
    'Microsoft.Extensions.DependencyInjection.Abstractions.dll',
    'Microsoft.Extensions.DependencyInjection.dll',
    'Microsoft.Extensions.Logging.Abstractions.dll',
    'Microsoft.Extensions.Logging.dll',
    'Microsoft.Extensions.Options.dll',
    'Microsoft.Extensions.Primitives.dll',
    'Serilog.dll',
    'Serilog.Extensions.Logging.dll',
    'Serilog.Sinks.File.dll',
    'System.Buffers.dll',
    'System.Collections.Immutable.dll',
    'System.Memory.dll',
    'System.Numerics.Vectors.dll',
    'System.Runtime.CompilerServices.Unsafe.dll',
    'System.Reflection.Metadata.dll',
    'System.ValueTuple.dll',
    'BUTR.CrashReport.dll',
    'BUTR.CrashReport.Models.dll',
    'BUTR.CrashReport.Renderer.Html.dll',
    'BUTR.CrashReport.Renderer.WinForms.dll',
    'BUTR.CrashReport.Renderer.Zip.dll',
    'BUTR.CrashReport.Renderer.ImGui.dll',
    'cimgui.dll',
    'glfw3.dll'
)

$copied = 0
foreach ($n in $add) {
    $src = Join-Path $source $n
    if (Test-Path $src) {
        Copy-Item $src -Destination $bin -Force
        $copied++
    } else {
        Write-Host "    MISSING source: $n" -ForegroundColor Red
    }
}
Write-Host "    copied $copied of $($add.Count) DLLs"

# SubModule.xml: Harmony + UIExtenderEx + ButterLib
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

Write-Host ""
Write-Host "==> bin DLLs ($((Get-ChildItem $bin -Filter '*.dll' | Measure-Object).Count)):"
Get-ChildItem $bin -Filter '*.dll' | Sort-Object Name | ForEach-Object { Write-Host "      $($_.Name)" }

Write-Host ""
Write-Host "==> Try launching. CREST + Native ticked only."
exit 0
