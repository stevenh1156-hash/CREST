using System;

using TaleWorlds.MountAndBlade;

namespace Bannerlord.Harmony;

/// <summary>
/// Phase Y.3 -- CompanionHotswap absorption.
///
/// Original mod: hold Ctrl during a mission to bring up a companion-portrait
/// roster + screen-space markers; click a portrait or marker to instantly
/// take control of that hero. Time slows to 15% while the menu is open.
///
/// Entry point: SubModule.OnMissionBehaviorInitialize calls
/// <see cref="AddMissionBehaviors"/>, which gates on the
/// <c>EnableCompanionHotswap</c> master toggle (default OFF, RequireRestart
/// false, MCM-driven, CrestConfig mtime-cached).
///
/// Two MissionBehaviors are added per mission when the toggle is on:
///   * <see cref="CrestCompanionSwapBehavior"/> -- the actual swap logic
///   * <see cref="CrestCompanionSelectBehavior"/> -- the UI overlay (input,
///     portrait roster Gauntlet layer, screen-space marker layer)
///
/// Two GUI prefabs ship with CREST:
///   * Modules\CREST\GUI\Prefabs\CrestCompanionSelect.xml
///   * Modules\CREST\GUI\Prefabs\CrestCompanionMarkers.xml
/// (Renamed from the upstream mod to avoid clash if both are installed.)
/// </summary>
internal static class CrestCompanionHotswap
{
    private const string Source = nameof(CrestCompanionHotswap);

    public static void AddMissionBehaviors(Mission mission)
    {
        if (mission == null) return;

        // Master gate -- read fresh from crest.json on every mission start.
        // CrestConfig is mtime-cached so this is one dict lookup.
        // Phase Y.3-persist: defaults to false now that CrestSettings.cs
        // registers EnableCompanionHotswap so MCM preserves the key.
        if (!CrestConfig.IsEnabled("EnableCompanionHotswap", defaultValue: false)) return;

        try
        {
            mission.AddMissionBehavior(new CrestCompanionSwapBehavior());
            mission.AddMissionBehavior(new CrestCompanionSelectBehavior());
            CrestDiag.Log(Source, "added swap + select behaviors to mission");
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "AddMissionBehaviors", ex);
        }
    }
}
