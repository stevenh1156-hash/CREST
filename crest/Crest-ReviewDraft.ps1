# =====================================================================
# Crest-ReviewDraft.ps1
# =====================================================================
# Reads the latest mod draft from .runner\mod-drafts\, parses the user's
# free-form description against specs\mod-spec.schema.json, and emits
# a status JSON listing which fields are FILLED vs MISSING.
#
# The AI agent then reads the status JSON and asks the user only for
# the missing fields, one at a time, in chat. This avoids re-asking
# things the user already wrote in their description.
#
# Output: .runner\mod-drafts\<Name>-<stamp>-review.json
#
# Usage:
#   & C:\dev\bannerlord\crest\Crest-ReviewDraft.ps1                (latest draft)
#   & C:\dev\bannerlord\crest\Crest-ReviewDraft.ps1 -DraftPath ... (specific)
# =====================================================================

param(
    [string]$DraftPath = ''
)

$ErrorActionPreference = 'Continue'

$crestRoot = 'C:\dev\bannerlord\crest'
$schemaPath = Join-Path $crestRoot 'specs\mod-spec.schema.json'
$draftDir   = Join-Path $crestRoot '.runner\mod-drafts'

Write-Host '== Crest-ReviewDraft ==' -ForegroundColor Cyan

# 1. Load schema.
if (-not (Test-Path $schemaPath)) {
    Write-Host "  ERROR: schema not found: $schemaPath" -ForegroundColor Red
    exit 1
}
$schema = Get-Content $schemaPath -Raw | ConvertFrom-Json
Write-Host "  schema:  $($schema.schemaVersion)"

# 2. Find draft.
if (-not $DraftPath) {
    if (-not (Test-Path $draftDir)) {
        Write-Host "  ERROR: no draft dir at $draftDir" -ForegroundColor Red
        exit 1
    }
    $latest = Get-ChildItem $draftDir -Filter '*-draft.txt' -File -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First 1
    if (-not $latest) {
        Write-Host '  ERROR: no -draft.txt files found' -ForegroundColor Red
        exit 1
    }
    $DraftPath = $latest.FullName
}
if (-not (Test-Path $DraftPath)) {
    Write-Host "  ERROR: draft not found: $DraftPath" -ForegroundColor Red
    exit 1
}
Write-Host "  draft:   $DraftPath"

$draft = Get-Content $DraftPath -Raw

# 3. Extract mod name from draft header (# Mod: <Name>).
$modName = ''
if ($draft -match '(?m)^#\s*Mod:\s*(\S+)') { $modName = $Matches[1] }

# 4. Heuristic detection per field.
# Strategy: cheap regex/keyword scans. The AI agent will refine --
# this just hands the agent a hint of what to skip asking about.

function Test-ContainsAny($text, $needles) {
    foreach ($n in $needles) {
        if ($text -match "(?i)\b$([regex]::Escape($n))\b") { return $true }
    }
    return $false
}

$filled  = @{}   # id -> detected value (string) or $true (boolean signal)
$missing = @()   # ids
$notes   = @{}   # id -> short reasoning string

foreach ($section in $schema.sections) {
    foreach ($f in $section.fields) {
        $id = $f.id
        switch ($id) {
            'Name' {
                if ($modName) { $filled[$id] = $modName; $notes[$id] = 'parsed from draft header' }
                else          { $missing += $id;        $notes[$id] = 'no # Mod: header found' }
            }
            'DisplayName' {
                # If draft mentions a quoted display name like "Weather System", catch it.
                if ($draft -match '(?m)^DisplayName:\s*(.+)$') { $filled[$id] = $Matches[1].Trim(); $notes[$id] = 'explicit DisplayName line' }
                else { $missing += $id; $notes[$id] = 'no explicit DisplayName declared' }
            }
            'Author' {
                if ($draft -match '(?m)^Author:\s*(.+)$') { $filled[$id] = $Matches[1].Trim() }
                else { $missing += $id; $notes[$id] = 'will offer default Maxfield Management Group' }
            }
            'Version' {
                if ($draft -match '(?m)^Version:\s*(\d+\.\d+\.\d+)') { $filled[$id] = $Matches[1] }
                else { $missing += $id; $notes[$id] = 'will offer default 0.1.0' }
            }
            'OneLiner' {
                # First non-blank line of "## Description (raw user input)" section, capped at 200 chars.
                if ($draft -match '(?ms)##\s*Description.*?\n(.+?)(\r?\n\r?\n|\Z)') {
                    $first = ($Matches[1] -split '(\r?\n)')[0].Trim()
                    if ($first.Length -gt 0) { $filled[$id] = ($first.Substring(0, [Math]::Min(200, $first.Length))) }
                    else { $missing += $id; $notes[$id] = 'description block is empty' }
                } else { $missing += $id; $notes[$id] = 'no Description block found' }
            }
            'Category' {
                $hits = @()
                foreach ($cat in $f.options) { if (Test-ContainsAny $draft @($cat)) { $hits += $cat } }
                if ($hits.Count -eq 1) { $filled[$id] = $hits[0]; $notes[$id] = "single category match: $($hits[0])" }
                elseif ($hits.Count -gt 1) { $missing += $id; $notes[$id] = "ambiguous (matched: $($hits -join ', '))" }
                else { $missing += $id; $notes[$id] = 'no category keyword' }
            }
            'DependsOn' {
                $deps = @('Native','SandBox','SandBoxCore','CREST','Harmony','ButterLib','UIExtenderEx','MCM')
                $hits = @()
                foreach ($d in $deps) { if ($draft -match "(?i)\b$d\b") { $hits += $d } }
                if ($hits.Count -gt 0) { $filled[$id] = $hits; $notes[$id] = 'detected from text' }
                else { $missing += $id; $notes[$id] = 'will offer default Native,SandBox,CREST' }
            }
            'SinglePlayer' {
                if ($draft -match '(?i)\b(single ?player|campaign|sandbox)\b') { $filled[$id] = $true; $notes[$id] = 'campaign/sandbox keyword' }
                elseif ($draft -match '(?i)\bmultiplayer only\b')              { $filled[$id] = $false }
                else { $missing += $id; $notes[$id] = 'will assume singleplayer if user confirms' }
            }
            'MultiPlayer' {
                if ($draft -match '(?i)\bmultiplayer\b')          { $filled[$id] = $true }
                elseif ($draft -match '(?i)\bsingleplayer only\b'){ $filled[$id] = $false }
                else { $missing += $id; $notes[$id] = 'will offer default false' }
            }
            'HookType' {
                $kw = @{ harmony='harmony'; 'submodule-lifecycle'='subModule|OnSubModuleLoad'; 'campaign-behavior'='CampaignBehaviorBase|OnSessionLaunched'; 'mission-behavior'='MissionBehavior|OnMissionTick' }
                $hits = @()
                foreach ($k in $kw.Keys) { if ($draft -match "(?i)$($kw[$k])") { $hits += $k } }
                if ($hits.Count -eq 1) { $filled[$id] = $hits[0] }
                elseif ($hits.Count -gt 1) { $filled[$id] = 'mixed'; $notes[$id] = "multiple hook keywords: $($hits -join ', ')" }
                else { $missing += $id; $notes[$id] = 'no hook keywords' }
            }
            'TargetAssemblies' {
                $asms = @('TaleWorlds.MountAndBlade','TaleWorlds.CampaignSystem','TaleWorlds.Core','TaleWorlds.Engine','TaleWorlds.Library','TaleWorlds.PlatformService')
                $hits = @()
                foreach ($a in $asms) { if ($draft -match [regex]::Escape($a)) { $hits += $a } }
                if ($hits.Count -gt 0) { $filled[$id] = $hits }
                else { $missing += $id; $notes[$id] = 'will offer default TaleWorlds.MountAndBlade' }
            }
            'PatchTargets'   { $missing += $id; $notes[$id] = 'optional -- agent should ask if HookType=harmony' }
            'EntryPoints'    { $missing += $id; $notes[$id] = 'will offer default OnSubModuleLoad' }

            'WhatItDoes' {
                # If description block has > 30 words, treat as filled.
                if ($draft -match '(?ms)##\s*Description.*?\n(.+?)(##|\Z)') {
                    $body = $Matches[1].Trim()
                    $wc = ($body -split '\s+').Count
                    if ($wc -ge 30) { $filled[$id] = "(${wc}-word description)"; $notes[$id] = "$wc words" }
                    else { $missing += $id; $notes[$id] = "description is short ($wc words) -- ask for more detail" }
                } else { $missing += $id; $notes[$id] = 'no description block' }
            }
            'TriggerConditions' {
                if ($draft -match '(?i)\b(when|on|every|each|tick|trigger|fires?)\b') { $filled[$id] = '(detected trigger keywords)'; $notes[$id] = 'when/on/every/tick found' }
                else { $missing += $id; $notes[$id] = 'no trigger keyword' }
            }
            'AffectedSystems' {
                $sys = @('combat','economy','diplomacy','troops','towns','weather','AI','siege','battle','party','clan','kingdom','quest','dialog')
                $hits = @()
                foreach ($s in $sys) { if ($draft -match "(?i)\b$s\b") { $hits += $s } }
                if ($hits.Count -gt 0) { $filled[$id] = $hits }
                else { $missing += $id; $notes[$id] = 'no system keyword' }
            }
            'ConfigurableSettings' { $missing += $id; $notes[$id] = 'optional -- ask whether MCM exposure is wanted' }
            'DefaultValues'        { $missing += $id; $notes[$id] = 'optional -- only if ConfigurableSettings filled' }

            'GameVersion'           { if ($draft -match '\b(\d+\.\d+\.\d+)\b') { $filled[$id] = $Matches[1] } else { $missing += $id; $notes[$id] = 'will offer default 1.4.3' } }
            'CompatibilityNotes'    { $missing += $id; $notes[$id] = 'optional -- defaults to "none known"' }
            'SaveSafe' {
                if ($draft -match '(?i)\bsave\s*safe\b|\bsavegame safe\b')           { $filled[$id] = 'yes' }
                elseif ($draft -match '(?i)\brequires?\s+new\s+(campaign|game)\b')   { $filled[$id] = 'no' }
                else { $missing += $id; $notes[$id] = 'will offer "unknown"' }
            }

            'TestScenarios'        { $missing += $id; $notes[$id] = 'optional -- ask whether sim coverage is wanted' }
            'AcceptanceCriteria' {
                if ($draft -match '(?i)\b(success|works when|verify|confirm|expect)\b') { $filled[$id] = '(detected criteria keywords)' }
                else { $missing += $id; $notes[$id] = 'no acceptance keyword -- ask explicitly' }
            }
            'EdgeCases'            { $missing += $id; $notes[$id] = 'optional -- invite user to list known concerns' }
            'RolloutStrategy'      { $missing += $id; $notes[$id] = 'will offer default preset-toggle' }
        }
    }
}

# 5. Emit review JSON next to draft.
$reviewPath = $DraftPath -replace '-draft\.txt$', '-review.json'
$totalFields = ($schema.sections | ForEach-Object { $_.fields.Count } | Measure-Object -Sum).Sum
$status = if ($missing.Count -eq 0) { 'COMPLETE' } else { 'GAPS' }

$report = [pscustomobject]@{
    schemaVersion = $schema.schemaVersion
    draftPath     = $DraftPath
    modName       = $modName
    status        = $status
    totalFields   = $totalFields
    filledCount   = $filled.Count
    missingCount  = $missing.Count
    filled        = $filled
    missing       = $missing
    notes         = $notes
    generatedAt   = (Get-Date).ToString('o')
}
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $reviewPath -Encoding utf8

# 6. Console summary.
Write-Host ''
Write-Host "  status:  $status  ($($filled.Count)/$totalFields fields filled, $($missing.Count) gaps)" -ForegroundColor $(if ($status -eq 'COMPLETE') { 'Green' } else { 'Yellow' })
Write-Host ''
Write-Host '  Filled (agent can SKIP these):' -ForegroundColor Green
foreach ($k in ($filled.Keys | Sort-Object)) {
    $v = $filled[$k]
    if ($v -is [array]) { $v = $v -join ',' }
    if ($v -is [bool])  { $v = if ($v) { 'true' } else { 'false' } }
    if ("$v".Length -gt 60) { $v = "$v".Substring(0,60) + '...' }
    Write-Host "    $k = $v" -ForegroundColor DarkGray
}
Write-Host ''
Write-Host '  Missing (agent SHOULD ASK):' -ForegroundColor Yellow
foreach ($id in $missing) {
    $hint = $notes[$id]
    Write-Host "    $id  -- $hint" -ForegroundColor DarkYellow
}
Write-Host ''
Write-Host "  review JSON: $reviewPath" -ForegroundColor Green
Write-Host ''
Write-Host '  AGENT INSTRUCTIONS:'
Write-Host '    1. Read the review JSON.' -ForegroundColor Gray
Write-Host '    2. For each id in `missing`, ask the user the matching `prompt`' -ForegroundColor Gray
Write-Host '       from specs\mod-spec.schema.json (one question at a time).'   -ForegroundColor Gray
Write-Host '    3. Once all missing are answered, write a -spec.json next to the' -ForegroundColor Gray
Write-Host '       draft and run Crest-Scaffold.ps1 -SpecPath <that file>.'      -ForegroundColor Gray
Write-Host ''
exit 0
