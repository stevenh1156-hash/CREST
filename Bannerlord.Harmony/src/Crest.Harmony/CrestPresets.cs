using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

using TaleWorlds.Library;

namespace Bannerlord.Harmony;

/// <summary>
/// CREST v0.9.1 Vanilla / Cinema / Default preset switcher.
///
/// Three named presets that bulk-rewrite <c>Modules/CREST/crest.json</c>:
///
///   Default  — everything CREST shipped with as the default-on baseline
///              (campaign tweaks, companion hotswap, battle size, tier unlocker,
///              brush-race finalizer; cinema features off).
///
///   Vanilla  — every CREST EnableXxx flag is set to false. Game runs with
///              just the bundled foundation libraries (Harmony, ButterLib,
///              UIExtenderEx, MCMv5, BetterExceptionWindow, BUTR.CrashReport)
///              providing the dependency stack, but no CREST-original behavior
///              modifications. For users who want CREST as a pure dependency-
///              consolidator and nothing else.
///
///   Cinema   — Default + FasterTime, CutThroughEveryone, PlayerInvincible
///              all turned ON. The internal-build experience that wasn't
///              public-default in v0.9.0 because the combination is jarring
///              for new users; opt in here for the cinematic playthrough.
///
/// Trigger from the main menu, world map, or in-mission via hotkey:
///   Ctrl+Alt+1  →  Default
///   Ctrl+Alt+2  →  Vanilla
///   Ctrl+Alt+3  →  Cinema
///
/// Hotkey dispatch lives in <see cref="SubModule.OnApplicationTick"/> next to
/// the existing Ctrl+Alt+H (debug UI) and Ctrl+Alt+P (patch snapshot) hooks.
///
/// Preset application is atomic — writes to <c>crest.json.tmp</c>, then
/// <see cref="File.Move"/> swaps it in. Same atomicity pattern that
/// Crest-Postmortem's digest write uses, for the same reason: if the rewrite
/// fails midway through, we don't leave the user with a corrupt config that
/// strips all their settings.
///
/// In-mission features that depend on a CrestConfig flag (CompanionHotswap,
/// PlayerInvincible, etc.) read the flag on each behavior tick or at mission
/// start, so the preset takes effect on the next mission load. The hotkey
/// also displays a message confirming the swap so the user knows which
/// preset they just selected.
/// </summary>
public static class CrestPresets
{
    public const string PresetDefault = "Default";
    public const string PresetVanilla = "Vanilla";
    public const string PresetCinema  = "Cinema";

    private static readonly object _lock = new();

    /// <summary>
    /// Apply the named preset to <c>crest.json</c>. Returns the path that was
    /// written, or null on failure (logged to runtime.log).
    /// </summary>
    public static string? Apply(string presetName)
    {
        if (string.IsNullOrWhiteSpace(presetName)) return null;

        try
        {
            lock (_lock)
            {
                var configPath = ResolveConfigPath();
                if (configPath == null)
                {
                    CrestDiag.Log("CrestPresets", "Apply: could not resolve crest.json path");
                    return null;
                }

                // Parse current state so we preserve unknown keys (numeric
                // sliders, string scopes, etc. that aren't in the preset
                // vocabulary).
                var existing = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                if (File.Exists(configPath))
                {
                    ParseAllKeys(File.ReadAllText(configPath), existing);
                }

                // Apply the preset's bool overrides on top of existing state.
                var overrides = BuildPresetOverrides(presetName);
                foreach (var kvp in overrides)
                {
                    existing[kvp.Key] = kvp.Value ? "true" : "false";
                }

                // Stamp the preset name itself so the next config-save
                // operation (and humans reading the file) knows which preset
                // is currently active.
                existing["Preset"] = "\"" + NormalizePresetName(presetName) + "\"";

                // Always include a refreshed _comment so users opening the
                // file see what the preset values mean.
                existing["_comment"] = "\"" + BuildComment(presetName) + "\"";

                WriteAtomic(configPath, existing);

                CrestDiag.Log("CrestPresets", $"Apply: preset='{NormalizePresetName(presetName)}' written to {configPath}");
                return configPath;
            }
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught("CrestPresets", "Apply", ex);
            return null;
        }
    }

    /// <summary>
    /// Show the user a confirmation message in the active screen, in the
    /// CREST orange color. Called from the SubModule hotkey path after a
    /// successful apply.
    /// </summary>
    public static void NotifyApplied(string presetName)
    {
        try
        {
            var n = NormalizePresetName(presetName);
            InformationManager.DisplayMessage(
                new InformationMessage(
                    $"CREST preset applied: {n}. Restart the mission for in-mission features to update.",
                    Color.FromUint(0xFFB8893F)));  // CREST gold
        }
        catch { /* never let the toast crash anything */ }
    }

    private static string NormalizePresetName(string name)
    {
        if (string.Equals(name, PresetVanilla, StringComparison.OrdinalIgnoreCase)) return PresetVanilla;
        if (string.Equals(name, PresetCinema, StringComparison.OrdinalIgnoreCase))  return PresetCinema;
        return PresetDefault;
    }

    private static string BuildComment(string presetName)
    {
        var n = NormalizePresetName(presetName);
        return n switch
        {
            PresetVanilla => "CREST 'Vanilla' preset: every CREST feature toggle is OFF. The game runs with the foundation stack (Harmony/ButterLib/UIExtenderEx/MCMv5) but no CREST-original behavior changes.",
            PresetCinema  => "CREST 'Cinema' preset: shipping defaults plus FasterTime, CutThroughEveryone, and PlayerInvincible all enabled. Switch back via Ctrl+Alt+1.",
            _             => "CREST 'Default' preset: shipping defaults. Switch presets with Ctrl+Alt+1 (Default), Ctrl+Alt+2 (Vanilla), Ctrl+Alt+3 (Cinema)."
        };
    }

    /// <summary>
    /// Returns the bool overrides that the named preset should apply on top
    /// of whatever the user currently has. Numeric slider values and string
    /// settings (scopes, multipliers) are NOT touched; only the EnableXxx
    /// surface that the user toggles in MCM.
    /// </summary>
    private static Dictionary<string, bool> BuildPresetOverrides(string presetName)
    {
        var n = NormalizePresetName(presetName);

        // Master list of every Enable* flag CREST recognizes. Kept here as
        // the canonical preset surface; if a new feature flag lands in
        // Phase Z, add it here AND its Default preset value.
        // Source of truth: CrestConfig.WriteDefault default JSON dict, plus
        // the v0.9.0 release crest.json.
        var d = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);

        // ── DEFAULT preset (= v0.9.0 shipping crest.json) ────────────────
        var def = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase)
        {
            { "EnableBattleConvergence",     false },
            { "EnableBrushRaceMitigation",   true  },
            { "EnableCampaignTweaks",        true  },
            { "EnableCompanionHotswap",      true  },
            { "EnableBattleSize",            true  },
            { "EnableTierUnlocker",          true  },
            { "EnableFasterTime",            false },
            { "EnableCutThroughEveryone",    false },
            { "EnablePlayerInvincible",      false },
            { "EnableCinemaPreset",          false },
            { "EnableCrashMirror",           true  },
            { "EnableLogFiltering",          true  },
            { "EnablePlayerHealthRegen",     false },
            { "EnableReinforcements",        false },
            { "EnableAchievementsWithMods",  true  },
            { "EnableFasterShips",           true  },
        };

        switch (n)
        {
            case PresetVanilla:
                // Every Enable* flag the preset surface knows about → false.
                // CrashMirror also goes off because the user picking Vanilla
                // is opting out of all CREST behavior.
                foreach (var k in def.Keys) d[k] = false;
                break;

            case PresetCinema:
                // Default + the three cinema features.
                foreach (var kvp in def) d[kvp.Key] = kvp.Value;
                d["EnableFasterTime"]         = true;
                d["EnableCutThroughEveryone"] = true;
                d["EnablePlayerInvincible"]   = true;
                d["EnableCinemaPreset"]       = true;
                break;

            default:  // Default
                foreach (var kvp in def) d[kvp.Key] = kvp.Value;
                break;
        }

        return d;
    }

    /// <summary>
    /// Walk up from this assembly's location to find Modules\CREST\crest.json.
    /// Mirrors the path-resolution logic in CrestConfig.ResolveConfigPath.
    /// </summary>
    private static string? ResolveConfigPath()
    {
        try
        {
            var asmLoc = typeof(CrestPresets).Assembly.Location;
            if (string.IsNullOrEmpty(asmLoc)) return null;
            var binDir = Path.GetDirectoryName(asmLoc);
            if (binDir == null) return null;
            var binParent = Directory.GetParent(binDir);
            if (binParent == null) return null;
            var crestRoot = binParent.Parent;
            if (crestRoot == null) return null;
            return Path.Combine(crestRoot.FullName, "crest.json");
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Parse every top-level key:value pair from crest.json into raw-string
    /// values (with quotes preserved for strings, with the literal "true"/
    /// "false" or number text for primitives). The result round-trips back
    /// through WriteAtomic without transformation, so unknown sliders /
    /// scopes the preset doesn't touch survive the rewrite intact.
    /// </summary>
    private static void ParseAllKeys(string json, Dictionary<string, string> dest)
    {
        // bool first
        foreach (Match m in Regex.Matches(json, "\"([A-Za-z_][A-Za-z0-9_]*)\"\\s*:\\s*(true|false)",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant))
        {
            dest[m.Groups[1].Value] = m.Groups[2].Value.ToLowerInvariant();
        }
        // numbers
        foreach (Match m in Regex.Matches(json, "\"([A-Za-z_][A-Za-z0-9_]*)\"\\s*:\\s*(-?\\d+(?:\\.\\d+)?)",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant))
        {
            if (!dest.ContainsKey(m.Groups[1].Value))
                dest[m.Groups[1].Value] = m.Groups[2].Value;
        }
        // strings (capture quotes too so write path is uniform)
        foreach (Match m in Regex.Matches(json, "\"([A-Za-z_][A-Za-z0-9_]*)\"\\s*:\\s*\"([^\"]*)\"",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant))
        {
            // string keys override only if not already captured as bool
            if (!dest.ContainsKey(m.Groups[1].Value))
                dest[m.Groups[1].Value] = "\"" + m.Groups[2].Value + "\"";
        }
    }

    /// <summary>
    /// Atomic write: serialize to .tmp then File.Move replace into the final
    /// path. Keys are written in a stable, human-readable order: _comment,
    /// _release, Preset first, then everything else alphabetized.
    /// </summary>
    private static void WriteAtomic(string path, Dictionary<string, string> kvp)
    {
        var sb = new StringBuilder();
        sb.Append("{\n");

        // Header keys first (in this order), then the rest alphabetized.
        var headerOrder = new[] { "_comment", "_release", "Preset" };
        var written = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var first = true;

        foreach (var k in headerOrder)
        {
            if (!kvp.ContainsKey(k)) continue;
            AppendKv(sb, k, kvp[k], ref first);
            written.Add(k);
        }

        var rest = new List<string>();
        foreach (var k in kvp.Keys) if (!written.Contains(k)) rest.Add(k);
        rest.Sort(StringComparer.OrdinalIgnoreCase);
        foreach (var k in rest) AppendKv(sb, k, kvp[k], ref first);

        sb.Append("\n}\n");

        var tmp = path + ".tmp";
        File.WriteAllText(tmp, sb.ToString());
        if (File.Exists(path))
        {
            try { File.Delete(path); } catch { /* will retry via Move */ }
        }
        File.Move(tmp, path);
    }

    private static void AppendKv(StringBuilder sb, string key, string rawValue, ref bool first)
    {
        if (!first) sb.Append(",\n");
        sb.Append("  \"").Append(key).Append("\": ").Append(rawValue);
        first = false;
    }
}
