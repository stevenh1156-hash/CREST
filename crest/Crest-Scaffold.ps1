# =====================================================================
# Crest-Scaffold.ps1
# =====================================================================
# Reads a COMPLETE mod spec JSON (output of the agent's review pass)
# and generates a build-ready Bannerlord module skeleton at
# C:\dev\bannerlord\Bannerlord.<Name>\
#
# Files emitted:
#   src\Crest.<Name>\Crest.<Name>.csproj
#   src\Crest.<Name>\<Name>SubModule.cs
#   src\Crest.<Name>\Patches\<Name>Patch.cs       (if HookType matches harmony)
#   src\Crest.<Name>\Settings\<Name>Settings.cs   (if ConfigurableSettings non-empty)
#   ModuleBin\SubModule.xml
#   README.md
#
# Spec format: see specs\mod-spec.schema.json (output of Crest-ReviewDraft.ps1
# after the agent fills missing fields and writes -spec.json).
#
# Usage:
#   & C:\dev\bannerlord\crest\Crest-Scaffold.ps1 -SpecPath <path-to-spec.json>
# =====================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$SpecPath,

    # Override target root (default C:\dev\bannerlord).
    [string]$DevRoot = 'C:\dev\bannerlord',

    # If set, abort if the target dir already exists. Otherwise scaffold
    # only the missing files (idempotent overlay).
    [switch]$FailIfExists
)

$ErrorActionPreference = 'Continue'

Write-Host '== Crest-Scaffold ==' -ForegroundColor Cyan

if (-not (Test-Path $SpecPath)) {
    Write-Host "  ERROR: spec not found: $SpecPath" -ForegroundColor Red
    exit 1
}
$spec = Get-Content $SpecPath -Raw | ConvertFrom-Json

# Resolve required fields with friendly errors.
function Need($obj, $field) {
    $v = $obj.$field
    if ($null -eq $v -or "$v" -eq '') {
        Write-Host "  ERROR: spec is missing required field: $field" -ForegroundColor Red
        exit 1
    }
    return $v
}
$name        = Need $spec 'Name'
$displayName = if ($spec.DisplayName) { $spec.DisplayName } else { $name }
$author      = if ($spec.Author)      { $spec.Author }      else { 'Maxfield Management Group' }
$version     = if ($spec.Version)     { $spec.Version }     else { '0.1.0' }
$gameVersion = if ($spec.GameVersion) { $spec.GameVersion } else { '1.4.3' }
$hookType    = if ($spec.HookType)    { $spec.HookType }    else { 'submodule-lifecycle' }
$dependsOn   = if ($spec.DependsOn)   { @($spec.DependsOn) } else { @('Native','SandBox','CREST') }
$entryPoints = if ($spec.EntryPoints) { @($spec.EntryPoints) } else { @('OnSubModuleLoad') }
$singlePlayer= [bool]$spec.SinglePlayer
$multiPlayer = [bool]$spec.MultiPlayer
$mcmSettings = if ($spec.ConfigurableSettings) { @($spec.ConfigurableSettings) } else { @() }
$saveSafe    = if ($spec.SaveSafe) { $spec.SaveSafe } else { 'unknown' }

# Target paths.
$modRoot = Join-Path $DevRoot ("Bannerlord." + $name)
$srcDir  = Join-Path $modRoot ("src\Crest." + $name)
$binDir  = Join-Path $modRoot 'ModuleBin'
$readme  = Join-Path $modRoot 'README.md'

if ((Test-Path $modRoot) -and $FailIfExists) {
    Write-Host "  ERROR: target already exists: $modRoot (FailIfExists set)" -ForegroundColor Red
    exit 1
}

Write-Host "  spec:        $SpecPath"
Write-Host "  mod name:    $name"
Write-Host "  target root: $modRoot"
Write-Host "  hook type:   $hookType"
Write-Host ''

# --- Create directories ---
foreach ($d in @($modRoot, $srcDir, (Join-Path $srcDir 'Patches'), (Join-Path $srcDir 'Settings'), $binDir)) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Write-Host "  +dir $d" -ForegroundColor DarkGray
    }
}

# --- 1. csproj ---
$csprojPath = Join-Path $srcDir ("Crest.$name.csproj")
$csproj = @"
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net472</TargetFramework>
    <RootNamespace>Crest.$name</RootNamespace>
    <AssemblyName>Crest.$name</AssemblyName>
    <LangVersion>9.0</LangVersion>
    <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
    <Configurations>Debug;Release</Configurations>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Bannerlord.BuildResources" Version="1.1.0.129" />
    <PackageReference Include="Bannerlord.ReferenceAssemblies.Core" Version="1.4.3.0" PrivateAssets="all" />
  </ItemGroup>

  <ItemGroup Condition="'$hookType'=='harmony' or '$hookType'=='mixed'">
    <PackageReference Include="Lib.Harmony" Version="2.2.2" />
  </ItemGroup>

</Project>
"@
Set-Content -Path $csprojPath -Value $csproj -Encoding utf8
Write-Host "  + $csprojPath" -ForegroundColor Green

# --- 2. SubModule.cs ---
$subPath = Join-Path $srcDir ("$name" + 'SubModule.cs')
$harmonyId = "com.maxfieldmanagementgroup.crest.$($name.ToLower())"

# Build the override block from EntryPoints.
$overrides = New-Object System.Text.StringBuilder
foreach ($ep in $entryPoints) {
    switch ($ep) {
        'OnSubModuleLoad' {
            [void]$overrides.AppendLine('        protected override void OnSubModuleLoad()')
            [void]$overrides.AppendLine('        {')
            [void]$overrides.AppendLine('            base.OnSubModuleLoad();')
            if ($hookType -eq 'harmony' -or $hookType -eq 'mixed') {
                [void]$overrides.AppendLine("            var harmony = new HarmonyLib.Harmony(`"$harmonyId`");")
                [void]$overrides.AppendLine('            harmony.PatchAll();')
            }
            [void]$overrides.AppendLine("            InformationManager.DisplayMessage(new InformationMessage(`"$displayName loaded.`"));")
            [void]$overrides.AppendLine('        }')
            [void]$overrides.AppendLine()
        }
        'OnGameStart' {
            [void]$overrides.AppendLine('        public override void OnGameStart(Game game, IGameStarter gameStarter)')
            [void]$overrides.AppendLine('        {')
            [void]$overrides.AppendLine('            base.OnGameStart(game, gameStarter);')
            [void]$overrides.AppendLine('            // TODO: register CampaignBehaviorBase / MissionBehavior instances on gameStarter.')
            [void]$overrides.AppendLine('        }')
            [void]$overrides.AppendLine()
        }
        'OnMissionTick' {
            [void]$overrides.AppendLine('        public override void OnMissionBehaviorInitialize(Mission mission)')
            [void]$overrides.AppendLine('        {')
            [void]$overrides.AppendLine('            base.OnMissionBehaviorInitialize(mission);')
            [void]$overrides.AppendLine('            // TODO: mission.AddMissionBehavior(new YourBehavior());')
            [void]$overrides.AppendLine('        }')
            [void]$overrides.AppendLine()
        }
        'OnApplicationTick' {
            [void]$overrides.AppendLine('        protected override void OnApplicationTick(float dt)')
            [void]$overrides.AppendLine('        {')
            [void]$overrides.AppendLine('            base.OnApplicationTick(dt);')
            [void]$overrides.AppendLine('            // TODO: per-frame logic.')
            [void]$overrides.AppendLine('        }')
            [void]$overrides.AppendLine()
        }
    }
}

$sub = @"
// =====================================================================
// $name`SubModule.cs
// =====================================================================
// $displayName -- $($spec.OneLiner)
// Auto-scaffolded by Crest-Scaffold.ps1. Hand-edit freely below.
// Regenerating the spec will NOT overwrite this file unless you delete it.
// =====================================================================

using TaleWorlds.Core;
using TaleWorlds.Library;
using TaleWorlds.MountAndBlade;

namespace Crest.$name
{
    public class $name`SubModule : MBSubModuleBase
    {
$($overrides.ToString())
    }
}
"@
if (-not (Test-Path $subPath)) {
    Set-Content -Path $subPath -Value $sub -Encoding utf8
    Write-Host "  + $subPath" -ForegroundColor Green
} else {
    Write-Host "  = $subPath (kept existing)" -ForegroundColor DarkGray
}

# --- 3. Optional Harmony patch stub ---
if ($hookType -eq 'harmony' -or $hookType -eq 'mixed') {
    $patchPath = Join-Path $srcDir "Patches\$name`Patch.cs"
    if (-not (Test-Path $patchPath)) {
        $patch = @"
// Auto-scaffolded. Replace with actual target type/method.
using HarmonyLib;

namespace Crest.$name.Patches
{
    // [HarmonyPatch(typeof(SomeTalewordsType), nameof(SomeTalewordsType.SomeMethod))]
    public static class $name`Patch
    {
        // public static void Postfix() { /* TODO */ }
    }
}
"@
        Set-Content -Path $patchPath -Value $patch -Encoding utf8
        Write-Host "  + $patchPath" -ForegroundColor Green
    }
}

# --- 4. Optional MCM settings ---
if ($mcmSettings.Count -gt 0) {
    $setPath = Join-Path $srcDir "Settings\$name`Settings.cs"
    if (-not (Test-Path $setPath)) {
        $props = New-Object System.Text.StringBuilder
        foreach ($s in $mcmSettings) {
            $propName = ($s -replace '[^A-Za-z0-9]','')
            if (-not $propName) { continue }
            [void]$props.AppendLine("        public bool $propName { get; set; } = true;  // TODO: type + default")
        }
        $set = @"
// Auto-scaffolded MCM settings stub. Wire up to MCM v5 or use plain props.
namespace Crest.$name.Settings
{
    public class $name`Settings
    {
$($props.ToString())
    }
}
"@
        Set-Content -Path $setPath -Value $set -Encoding utf8
        Write-Host "  + $setPath" -ForegroundColor Green
    }
}

# --- 5. SubModule.xml ---
$xmlPath = Join-Path $binDir 'SubModule.xml'
$depXml = ($dependsOn | ForEach-Object { "    <DependedModule Id=`"$_`" />" }) -join "`r`n"
$xml = @"
<?xml version="1.0" encoding="utf-8"?>
<Module>
  <Name value="$displayName" />
  <Id value="Crest.$name" />
  <Version value="v$version" />
  <Official value="false" />
  <SingleplayerModule value="$($singlePlayer.ToString().ToLower())" />
  <MultiplayerModule value="$($multiPlayer.ToString().ToLower())" />
  <DependedModules>
$depXml
  </DependedModules>
  <SubModules>
    <SubModule>
      <Name value="$displayName" />
      <DLLName value="Crest.$name.dll" />
      <SubModuleClassType value="Crest.$name.$name`SubModule" />
      <Tags>
        <Tag key="DedicatedServerType" value="none" />
        <Tag key="IsNoRenderModeElement" value="false" />
      </Tags>
    </SubModule>
  </SubModules>
</Module>
"@
Set-Content -Path $xmlPath -Value $xml -Encoding utf8
Write-Host "  + $xmlPath" -ForegroundColor Green

# --- 6. README.md ---
if (-not (Test-Path $readme)) {
    $rm = @"
# $displayName

$($spec.OneLiner)

**Author:** $author
**Version:** v$version
**Game:** Bannerlord $gameVersion
**Save-safe:** $saveSafe
**Hook style:** $hookType

## What it does

$($spec.WhatItDoes)

## Triggers

$($spec.TriggerConditions)

## Acceptance criteria

$($spec.AcceptanceCriteria)

---

Auto-scaffolded by ``Crest-Scaffold.ps1``. Build with:

``````powershell
dotnet build src\Crest.$name\Crest.$name.csproj -c Release
``````
"@
    Set-Content -Path $readme -Value $rm -Encoding utf8
    Write-Host "  + $readme" -ForegroundColor Green
}

Write-Host ''
Write-Host "  scaffold complete: $modRoot" -ForegroundColor Green
Write-Host '  next steps:' -ForegroundColor Yellow
Write-Host "    1. dotnet build $csprojPath -c Release"
Write-Host "    2. copy bin\* + ModuleBin\* into Modules\Crest.$name\"
Write-Host '    3. boot Bannerlord with the new module enabled in BLSE'
Write-Host ''
exit 0
