using HarmonyLib.BUTR.Extensions;

using System;
using System.Reflection;

namespace Bannerlord.Harmony;

/// <summary>
/// Phase Y.1 -- FasterTime mod absorption. Replicates Faster Time's
/// behavior under the Phase W absorption template: master toggle in MCM,
/// RequireRestart=false, defaults OFF, lock-free per-tick path.
///
/// Mechanism (verified by IL inspection of FasterTime.dll v1.1.0):
///   1) <c>Campaign.Current.SetTimeSpeed(2)</c> selects the FastForward
///      time-control mode (the same one a vanilla "fastest" key press uses).
///   2) <c>Campaign.Current.SpeedUpMultiplier = N</c> overrides the actual
///      multiplier -- game default is 4f, we set 5/16/whatever.
///   3) When the user presses 1/2/3 (vanilla speed keys) we restore the
///      multiplier to 4f so they get unmodified behavior again.
///
/// All TaleWorlds API access is done via reflection because
/// TaleWorlds.CampaignSystem isn't loaded when Crest.Harmony.SubModule's
/// OnSubModuleLoad fires. Static <c>PropertyInfo</c>s are resolved once
/// on first tick and cached.
/// </summary>
internal static class CrestFasterTime
{
    private const string Source = nameof(CrestFasterTime);
    private const float DefaultSpeedMultiplier = 4f;
    private const int FastForwardTimeSpeed = 2;

    // v1.4.2 InputKey enum mapping (verified by runtime dump in phase-y4):
    //   D0=11  D1=2  D2=3  D3=4  D4=5  D5=6  D6=7  D7=8  D8=9  D9=10
    // Note D0 is at the END of the contiguous run (11), not the start.
    // Users see hotkey labels as "4" and "5" in the MCM hotkey config; the
    // raw enum int is what we store in crest.json and pass to IsKeyPressed.
    private const int DefaultSuperFastKey = 5;   // InputKey.D4
    private const int DefaultUltraFastKey = 6;   // InputKey.D5
    private const float DefaultSuperFastSpeed = 5f;
    private const float DefaultUltraFastSpeed = 16f;

    // Reset-to-default trigger keys (vanilla number row 1, 2, 3 = D1/D2/D3)
    private const int VanillaSpeed1Key = 2;   // InputKey.D1
    private const int VanillaSpeed2Key = 3;   // InputKey.D2
    private const int VanillaSpeed3Key = 4;   // InputKey.D3

    private static bool _staticResolved;
    private static PropertyInfo? _campaignCurrentProp;
    private static PropertyInfo? _missionCurrentProp;
    private static PropertyInfo? _timeControlModeLockProp;
    private static PropertyInfo? _speedUpMultiplierProp;
    private static MethodInfo? _setTimeSpeedMethod;

    // Input.IsKeyPressed lookup. TaleWorlds.InputSystem might be loaded by
    // the time we tick (it's a Native dep of every Bannerlord build), but
    // we still resolve via reflection so a missing assembly degrades to
    // "no input detected" rather than throwing.
    private static MethodInfo? _isKeyPressedMethod;
    private static Type? _inputKeyEnumType;     // for int->InputKey conversion at Invoke time

    public static void Apply()
    {
        // No Harmony patches needed; the tick path is invoked directly
        // from Crest.Harmony.SubModule.OnApplicationTick.
        CrestDiag.Log(Source, "registered (master toggle gates per-tick work)");
    }

    /// <summary>Called from <c>Crest.Harmony.SubModule.OnApplicationTick</c>.</summary>
    public static void OnTick(float dt)
    {
        // Master gate: bail before any reflection work if the user hasn't
        // opted in. CrestConfig is mtime-cached so this is one dict lookup.
        if (!CrestConfig.IsEnabled("EnableFasterTime", defaultValue: false)) return;

        ResolveStatics();

        try
        {
            var campaign = _campaignCurrentProp?.GetValue(null);
            if (campaign == null) return;
            if (_missionCurrentProp?.GetValue(null) != null) return;
            var locked = _timeControlModeLockProp?.GetValue(campaign) as bool? ?? false;
            if (locked) return;

            var ultraKey = CrestConfig.GetInt("FasterTimeUltraFastHotkey", DefaultUltraFastKey);
            var superKey = CrestConfig.GetInt("FasterTimeSuperFastHotkey", DefaultSuperFastKey);
            var ultraSpeed = CrestConfig.GetFloat("FasterTimeUltraFastSpeed", DefaultUltraFastSpeed);
            var superSpeed = CrestConfig.GetFloat("FasterTimeSuperFastSpeed", DefaultSuperFastSpeed);

            // Reset multiplier to 4 (game default) when user presses a vanilla
            // speed key. Without this, after using ultra-fast, the next "1"
            // press would still leave the multiplier at 16x.
            if (IsKeyPressed(VanillaSpeed1Key) || IsKeyPressed(VanillaSpeed2Key) || IsKeyPressed(VanillaSpeed3Key))
            {
                var current = _speedUpMultiplierProp?.GetValue(campaign) as float? ?? DefaultSpeedMultiplier;
                if (Math.Abs(current - DefaultSpeedMultiplier) > 0.01f)
                    _speedUpMultiplierProp?.SetValue(campaign, DefaultSpeedMultiplier);
            }

            if (IsKeyPressed(superKey)) SetSpeed(campaign, superSpeed);
            if (IsKeyPressed(ultraKey)) SetSpeed(campaign, ultraSpeed);
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "OnTick", ex);
        }
    }

    private static void SetSpeed(object campaign, float speed)
    {
        try
        {
            _speedUpMultiplierProp?.SetValue(campaign, speed);
            _setTimeSpeedMethod?.Invoke(campaign, new object[] { FastForwardTimeSpeed });
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "SetSpeed", ex);
        }
    }

    private static bool IsKeyPressed(int keyCode)
    {
        if (_isKeyPressedMethod == null || _inputKeyEnumType == null) return false;
        try
        {
            // Reflection.Invoke requires the exact parameter type. InputKey
            // is an enum (underlying int) but a boxed int is NOT assignable
            // to a boxed InputKey -- need Enum.ToObject to get the right
            // boxed value type. Without this every call silently throws.
            var enumValue = Enum.ToObject(_inputKeyEnumType, keyCode);
            return (bool) _isKeyPressedMethod.Invoke(null, new object[] { enumValue })!;
        }
        catch (Exception ex)
        {
            // Log the first failure so we know what went wrong if hotkeys
            // mysteriously stop working. Subsequent failures stay silent.
            DiagOnceFail("IsKeyPressed", ex);
            return false;
        }
    }

    private static volatile bool _isKeyPressedFailLogged;
    private static void DiagOnceFail(string what, Exception ex)
    {
        if (_isKeyPressedFailLogged) return;
        _isKeyPressedFailLogged = true;
        try { CrestDiag.LogCaught(Source, what, ex); } catch { }
    }

    private static void ResolveStatics()
    {
        if (_staticResolved) return;
        _staticResolved = true;
        try
        {
            var campaignType = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.Campaign");
            var missionType = AccessTools2.TypeByName("TaleWorlds.MountAndBlade.Mission");
            var inputType = AccessTools2.TypeByName("TaleWorlds.InputSystem.Input");
            var inputKeyType = AccessTools2.TypeByName("TaleWorlds.InputSystem.InputKey");

            _campaignCurrentProp     = campaignType?.GetProperty("Current",             BindingFlags.Public | BindingFlags.Static);
            _missionCurrentProp      = missionType?.GetProperty("Current",              BindingFlags.Public | BindingFlags.Static);
            _timeControlModeLockProp = campaignType?.GetProperty("TimeControlModeLock", BindingFlags.Public | BindingFlags.Instance);
            _speedUpMultiplierProp   = campaignType?.GetProperty("SpeedUpMultiplier",   BindingFlags.Public | BindingFlags.Instance);

            if (campaignType != null)
            {
                foreach (var m in campaignType.GetMethods(BindingFlags.Public | BindingFlags.Instance))
                {
                    if (m.Name != "SetTimeSpeed") continue;
                    var ps = m.GetParameters();
                    if (ps.Length == 1 && ps[0].ParameterType == typeof(int)) { _setTimeSpeedMethod = m; break; }
                }
            }

            if (inputType != null && inputKeyType != null)
            {
                _inputKeyEnumType = inputKeyType;
                foreach (var m in inputType.GetMethods(BindingFlags.Public | BindingFlags.Static))
                {
                    if (m.Name != "IsKeyPressed") continue;
                    var ps = m.GetParameters();
                    if (ps.Length == 1 && ps[0].ParameterType == inputKeyType) { _isKeyPressedMethod = m; break; }
                }
            }

            CrestDiag.Log(Source,
                "API resolved: Campaign.SpeedUpMultiplier=" + (_speedUpMultiplierProp != null ? "ok" : "MISSING") +
                ", SetTimeSpeed(int)=" + (_setTimeSpeedMethod != null ? "ok" : "MISSING") +
                ", Input.IsKeyPressed=" + (_isKeyPressedMethod != null ? "ok" : "MISSING"));
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "ResolveStatics", ex);
        }
    }
}
