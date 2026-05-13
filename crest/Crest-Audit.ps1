# =====================================================================
# Crest-Audit.ps1
# =====================================================================
# Scan the CREST source tree and emit a markdown index that maps every
# class / method / Y-phase marker to its file:line. Re-run on every commit;
# becomes the agent's go-to lookup for "where is X defined" without
# re-grepping the whole tree.
#
# Output: C:\dev\bannerlord\crest\CODE_INDEX.md
# =====================================================================

$ErrorActionPreference = 'Continue'

# Source roots to scan. Add more as the project grows.
$srcRoots = @(
    'C:\dev\bannerlord\Bannerlord.Harmony\src\Crest.Harmony'
    'C:\dev\bannerlord\Bannerlord.ButterLib\src\Crest.ButterLib'
    'C:\dev\bannerlord\Bannerlord.Harmony\sim\Crest.Harmony.Sim'
)

$indexPath = 'C:\dev\bannerlord\crest\CODE_INDEX.md'

# Collected data.
$types       = @()      # @{ Name, Kind, File, Line, EndLine }
$methods     = @()      # @{ Name, Container, File, Line, Sig }
$yMarkers    = @()      # @{ Phase, File, Line, Context }
$crossRefs   = @{}      # name -> [files that reference it]

Write-Host '== Crest-Audit ==' -ForegroundColor Cyan
Write-Host "  scanning: $($srcRoots -join ', ')"

# 1. Collect every .cs file.
$csFiles = @()
foreach ($root in $srcRoots) {
    if (Test-Path $root) {
        $csFiles += Get-ChildItem -Path $root -Filter '*.cs' -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notmatch '\\obj\\|\\bin\\' }
    }
}
Write-Host "  found $($csFiles.Count) C# files"

# 2. Per-file scan.
foreach ($f in $csFiles) {
    $rel = $f.FullName.Replace('C:\dev\bannerlord\', '')
    $lines = Get-Content $f.FullName
    $currentType = $null
    $currentTypeStart = 0
    $braceDepth = 0
    $inSummary = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $ln = $i + 1

        # Type declarations (class, struct, enum, record).
        if ($line -match '^\s*(public|private|internal|protected)?\s*(sealed|static|abstract|partial)?\s*(class|struct|enum|record)\s+(\w+)') {
            $kind = $Matches[3]
            $name = $Matches[4]
            if ($currentType) {
                # Close previous type.
                $types += [pscustomobject]@{
                    Name    = $currentType
                    Kind    = $currentTypeKind
                    File    = $rel
                    Line    = $currentTypeStart
                    EndLine = $ln - 1
                }
            }
            $currentType     = $name
            $currentTypeKind = $kind
            $currentTypeStart = $ln
        }

        # Method declarations.
        if ($currentType -and $line -match '^\s*(public|private|internal|protected)\s+(static\s+)?(async\s+)?(\w[\w<>?,\s\[\]]*)\s+(\w+)\s*\(') {
            $methodName = $Matches[5]
            # Skip property accessors (get/set).
            if ($methodName -ne 'get' -and $methodName -ne 'set') {
                $methods += [pscustomobject]@{
                    Name      = $methodName
                    Container = $currentType
                    File      = $rel
                    Line      = $ln
                    Sig       = $line.Trim()
                }
            }
        }

        # Y-phase markers in comments. Match "// Y.34" or "// Y.42c".
        if ($line -match '\bY\.(\d+)([a-z]?)\b') {
            $phase = "Y.$($Matches[1])$($Matches[2])"
            # Strip leading // and excessive whitespace from context.
            $context = ($line -replace '^\s*//\s*', '').Trim()
            if ($context.Length -gt 100) { $context = $context.Substring(0, 100) + '...' }
            $yMarkers += [pscustomobject]@{
                Phase   = $phase
                File    = $rel
                Line    = $ln
                Context = $context
            }
        }
    }
    # Close last type in file.
    if ($currentType) {
        $types += [pscustomobject]@{
            Name    = $currentType
            Kind    = $currentTypeKind
            File    = $rel
            Line    = $currentTypeStart
            EndLine = $lines.Count
        }
    }
}

# 3. Cross-references: for each known type name, find files that mention it.
$typeNames = $types | ForEach-Object { $_.Name } | Sort-Object -Unique
foreach ($f in $csFiles) {
    $rel = $f.FullName.Replace('C:\dev\bannerlord\', '')
    $content = Get-Content $f.FullName -Raw
    foreach ($n in $typeNames) {
        # Word-boundary match. Skip self-defining file (where type is declared).
        $declFile = ($types | Where-Object { $_.Name -eq $n } | Select-Object -First 1).File
        if ($rel -eq $declFile) { continue }
        if ($content -match "\b$n\b") {
            if (-not $crossRefs.ContainsKey($n)) { $crossRefs[$n] = @() }
            if (-not ($crossRefs[$n] -contains $rel)) { $crossRefs[$n] += $rel }
        }
    }
}

# 4. Emit markdown.
$out = [System.Text.StringBuilder]::new()
[void]$out.AppendLine('# CREST Code Index')
[void]$out.AppendLine('')
[void]$out.AppendLine('Auto-generated by `Crest-Audit.ps1`. Re-run on every commit.')
[void]$out.AppendLine("Generated: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))")
[void]$out.AppendLine('')
[void]$out.AppendLine("**Stats:** $($csFiles.Count) source files, $($types.Count) types, $($methods.Count) methods, $($yMarkers.Count) Y-phase markers.")
[void]$out.AppendLine('')

# Types section.
[void]$out.AppendLine('## Types')
[void]$out.AppendLine('')
foreach ($t in ($types | Sort-Object Name)) {
    [void]$out.AppendLine("- **$($t.Name)** *(${($t.Kind)})* -- $($t.File):$($t.Line)-$($t.EndLine)")
}
[void]$out.AppendLine('')

# Methods grouped by container.
[void]$out.AppendLine('## Methods (by container)')
[void]$out.AppendLine('')
$methodsByContainer = $methods | Group-Object -Property Container | Sort-Object Name
foreach ($grp in $methodsByContainer) {
    [void]$out.AppendLine("### $($grp.Name)")
    foreach ($m in ($grp.Group | Sort-Object Line)) {
        [void]$out.AppendLine("- ``$($m.Name)`` -- $($m.File):$($m.Line)")
    }
    [void]$out.AppendLine('')
}

# Y-phase markers chronologically (by phase number).
[void]$out.AppendLine('## Y-phase markers (chronological)')
[void]$out.AppendLine('')
$markersByPhase = $yMarkers | Sort-Object @{Expression={ [int]($_.Phase -replace '^Y\.','' -replace '[a-z]$','') }}, Phase, File, Line
$prevPhase = ''
foreach ($m in $markersByPhase) {
    if ($m.Phase -ne $prevPhase) {
        [void]$out.AppendLine("### $($m.Phase)")
        $prevPhase = $m.Phase
    }
    [void]$out.AppendLine("- $($m.File):$($m.Line) -- $($m.Context)")
}
[void]$out.AppendLine('')

# Cross-references.
[void]$out.AppendLine('## Cross-references')
[void]$out.AppendLine('')
foreach ($k in ($crossRefs.Keys | Sort-Object)) {
    $refs = $crossRefs[$k] | Sort-Object
    if ($refs.Count -eq 0) { continue }
    [void]$out.AppendLine("- **$k** used by:")
    foreach ($r in $refs) { [void]$out.AppendLine("  - $r") }
}

# Write the index.
Set-Content -Path $indexPath -Value $out.ToString() -Encoding utf8
$size = (Get-Item $indexPath).Length
Write-Host ''
Write-Host "  wrote $indexPath ($size bytes)" -ForegroundColor Green
Write-Host ''
Write-Host '  Summary:'
Write-Host "    types:    $($types.Count)"
Write-Host "    methods:  $($methods.Count)"
Write-Host "    Y-phases: $($yMarkers.Count)"
Write-Host "    xref:     $($crossRefs.Keys.Count) symbols"
exit 0
