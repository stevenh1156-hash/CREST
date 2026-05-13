using HarmonyLib.BUTR.Extensions;

using System;
using System.Collections.Generic;
using System.Reflection;

using TaleWorlds.Core;
using TaleWorlds.Core.ViewModelCollection.ImageIdentifiers;
using TaleWorlds.DotNet;
using TaleWorlds.Engine;
using TaleWorlds.Engine.GauntletUI;
using TaleWorlds.InputSystem;
using TaleWorlds.Library;
using TaleWorlds.MountAndBlade;
using TaleWorlds.ScreenSystem;

namespace Bannerlord.Harmony;

/// <summary>
/// Phase Y.3 -- the UI half of CompanionHotswap. While the user holds the
/// configured hotkey (default LeftCtrl/RightCtrl) during a mission:
///   * Time slows to 15% via TimeSpeedRequest (id 98770, CREST-unique).
///   * A portrait roster Gauntlet layer (CrestCompanionSelect) shows all
///     swappable heroes.
///   * A screen-space markers Gauntlet layer (CrestCompanionMarkers) draws
///     a clickable badge above each companion in world.
/// Releasing the key removes both layers and restores time speed. Clicking
/// LMB on a marker calls SwapToAgent on the swap behavior.
///
/// All TaleWorlds.MountAndBlade.View types (MissionView, MissionScreen,
/// MBWindowManager) are accessed via reflection so this DLL doesn't carry
/// a cross-module assembly reference that BLSE would tag at startup.
/// TimeSpeedRequest is similarly reflected (lives in the global namespace
/// inside TaleWorlds.MountAndBlade.dll, not exposed by BUTR ref-assemblies).
/// </summary>
internal sealed class CrestCompanionSelectBehavior : MissionBehavior
{
    private const int TimeSlowId = 98770;
    private const float CanvasW = 1920f;
    private const float CanvasH = 1080f;
    private const float MarkerW = 62f;
    private const float MarkerH = 72f;
    private const float ClickRadiusSq = 0.0009f;

    private const string Source = nameof(CrestCompanionSelectBehavior);

    private CrestCompanionSwapBehavior? _swapBehavior;
    private bool _isMenuOpen;
    private int _menuOpenTicks;
    private GauntletLayer? _portraitLayer;
    private CrestCompanionRosterVM? _portraitVM;
    private GauntletLayer? _markerLayer;
    private CrestCompanionMarkersVM? _markerVM;

    private object? _timeSlow;
    private bool _timeSlowCreated;
    private object? _missionScreen;            // boxed MissionScreen

    // ---- Reflective handles for TaleWorlds.MountAndBlade.View types ----
    private static readonly Type? _missionViewType    = AccessTools2.TypeByName("TaleWorlds.MountAndBlade.View.MissionViews.MissionView");
    private static readonly Type? _missionScreenType  = AccessTools2.TypeByName("TaleWorlds.MountAndBlade.View.Screens.MissionScreen");
    private static readonly PropertyInfo? _missionScreenOnView =
        _missionViewType?.GetProperty("MissionScreen", BindingFlags.Public | BindingFlags.Instance);
    private static readonly PropertyInfo? _combatCameraProp =
        _missionScreenType?.GetProperty("CombatCamera", BindingFlags.Public | BindingFlags.Instance);
    private static readonly MethodInfo? _addLayerMethod =
        _missionScreenType?.BaseType?.GetMethod("AddLayer", BindingFlags.Public | BindingFlags.Instance, null, new[] { typeof(ScreenLayer) }, null)
        ?? _missionScreenType?.GetMethod("AddLayer", BindingFlags.Public | BindingFlags.Instance, null, new[] { typeof(ScreenLayer) }, null);
    private static readonly MethodInfo? _removeLayerMethod =
        _missionScreenType?.BaseType?.GetMethod("RemoveLayer", BindingFlags.Public | BindingFlags.Instance, null, new[] { typeof(ScreenLayer) }, null)
        ?? _missionScreenType?.GetMethod("RemoveLayer", BindingFlags.Public | BindingFlags.Instance, null, new[] { typeof(ScreenLayer) }, null);

    private static readonly Type? _windowManagerType = AccessTools2.TypeByName("TaleWorlds.MountAndBlade.View.MBWindowManager");
    private static readonly MethodInfo? _worldToScreenMethod =
        _windowManagerType?.GetMethod("WorldToScreen", BindingFlags.Public | BindingFlags.Static);

    // ---- Reflective handles for TimeSpeedRequest ----
    private static readonly Type? _timeSpeedRequestType = AccessTools2.TypeByName("TimeSpeedRequest");
    private static readonly ConstructorInfo? _timeSpeedRequestCtor =
        _timeSpeedRequestType?.GetConstructor(new[] { typeof(float), typeof(int) });
    private static readonly MethodInfo? _addTimeSpeedRequestMethod =
        _timeSpeedRequestType != null
            ? typeof(Mission).GetMethod("AddTimeSpeedRequest", new[] { _timeSpeedRequestType })
            : null;
    private static readonly MethodInfo? _removeTimeSpeedRequestMethod =
        typeof(Mission).GetMethod("RemoveTimeSpeedRequest", new[] { typeof(int) });

    public override MissionBehaviorType BehaviorType => (MissionBehaviorType)1;

    public override void OnMissionTick(float dt)
    {
        try
        {
            if (Mission.Current == null) return;

            if (_swapBehavior == null)
                _swapBehavior = Mission.Current.GetMissionBehavior<CrestCompanionSwapBehavior>();
            if (_swapBehavior == null) return;

            // Y.12d-fix22: default key Z (InputKey.Z = 44). The previous default
            // NumpadMultiply (*) collided with RTSCamera's slow-down-time binding.
            // Z is right under A on a QWERTY layout, easy left-hand reach, and
            // not bound to anything in vanilla Bannerlord 1.4.2.
            // CrestConfig keys kept as CompanionHotswapHotkeyLeft/Right for back-compat;
            // we'll add a TacticalHotkey alias when BetterTroopHUD absorption lands.
            var keyL = (InputKey) CrestConfig.GetInt("CompanionHotswapHotkeyLeft",  (int) InputKey.Z);
            var keyR = (InputKey) CrestConfig.GetInt("CompanionHotswapHotkeyRight", (int) InputKey.Z);

            // Phase Y.3-fix: single-press toggle. IsKeyPressed fires on the
            // press edge only (not while held), so each press flips state.
            bool toggle = Input.IsKeyPressed(keyL) || Input.IsKeyPressed(keyR);
            if (toggle)
            {
                if (_isMenuOpen) CloseMenu();
                else OpenMenu();
            }

            // Escape also closes
            if (_isMenuOpen && Input.IsKeyPressed(InputKey.Escape)) CloseMenu();

            if (!_isMenuOpen || _markerVM == null) return;

            _menuOpenTicks++;
            if (_menuOpenTicks > 1)
            {
                UpdateMarkers();
                if (Input.IsKeyPressed(InputKey.LeftMouseButton))
                    HandleMarkerClick();
            }
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "OnMissionTick", ex);
        }
    }

    public override void OnRemoveBehavior()
    {
        if (_isMenuOpen) CloseMenu();
        base.OnRemoveBehavior();
    }

    private object? GetMissionScreen()
    {
        if (_missionScreen != null) return _missionScreen;
        if (Mission.Current == null) return null;
        if (_missionViewType == null || _missionScreenOnView == null) return null;

        foreach (var mb in Mission.Current.MissionBehaviors)
        {
            if (mb == null || !_missionViewType.IsInstanceOfType(mb)) continue;
            try
            {
                var ms = _missionScreenOnView.GetValue(mb);
                if (ms != null) { _missionScreen = ms; return _missionScreen; }
            }
            catch (Exception ex) { CrestDiag.LogCaught(Source, "GetMissionScreen", ex); }
        }
        return null;
    }

    private object? GetCombatCamera(object? missionScreen)
    {
        if (missionScreen == null || _combatCameraProp == null) return null;
        try { return _combatCameraProp.GetValue(missionScreen); }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "GetCombatCamera", ex); return null; }
    }

    private void AddLayer(object missionScreen, ScreenLayer layer)
    {
        try { _addLayerMethod?.Invoke(missionScreen, new object[] { layer }); }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "AddLayer", ex); }
    }

    private void RemoveLayer(object missionScreen, ScreenLayer layer)
    {
        try { _removeLayerMethod?.Invoke(missionScreen, new object[] { layer }); }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "RemoveLayer", ex); }
    }

    // Phase Z.1 perf: reused arg buffer so WorldToScreen doesn't allocate a
    // fresh object[] on every marker every tick (8 markers x ~60 fps = 480
    // allocs/sec while menu is open).
    private readonly object[] _w2sArgs = new object[5];
    private bool WorldToScreen(object camera, Vec3 pos, ref float x, ref float y, ref float w)
    {
        if (_worldToScreenMethod == null) return false;
        try
        {
            _w2sArgs[0] = camera;
            _w2sArgs[1] = pos;
            _w2sArgs[2] = x;
            _w2sArgs[3] = y;
            _w2sArgs[4] = w;
            _worldToScreenMethod.Invoke(null, _w2sArgs);
            x = (float) _w2sArgs[2];
            y = (float) _w2sArgs[3];
            w = (float) _w2sArgs[4];
            return true;
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "WorldToScreen", ex);
            return false;
        }
    }

    private void OpenMenu()
    {
        var missionScreen = GetMissionScreen();
        if (missionScreen == null) return;
        if (Mission.Current?.PlayerTeam == null || _swapBehavior == null) return;

        _isMenuOpen = true;
        _menuOpenTicks = 0;

        var slowFactor = CrestConfig.GetFloat("CompanionHotswapTimeSlowFactor", 0.15f);
        if (!_timeSlowCreated && _timeSpeedRequestCtor != null)
        {
            try
            {
                _timeSlow = _timeSpeedRequestCtor.Invoke(new object[] { slowFactor, TimeSlowId });
                _timeSlowCreated = true;
            }
            catch (Exception ex) { CrestDiag.LogCaught(Source, "TimeSpeedRequest ctor", ex); }
        }
        if (_timeSlow != null && _addTimeSpeedRequestMethod != null)
        {
            try { _addTimeSpeedRequestMethod.Invoke(Mission.Current, new[] { _timeSlow }); }
            catch (Exception ex) { CrestDiag.LogCaught(Source, "AddTimeSpeedRequest", ex); }
        }

        _portraitVM = new CrestCompanionRosterVM();
        _portraitVM.Refresh(
            _swapBehavior.GetCompanionAgents(),
            Mission.Current.MainAgent,
            agent => { _swapBehavior.SwapToAgent(agent); CloseMenu(); }); // Phase Y.3-fix: close after pick

        _portraitLayer = new GauntletLayer("GauntletLayer", 200, false);
        _portraitLayer.InputRestrictions.SetInputRestrictions(true, InputUsageMask.All);
        _portraitLayer.LoadMovie("CrestCompanionSelect", _portraitVM);
        AddLayer(missionScreen, _portraitLayer);

        _markerVM = new CrestCompanionMarkersVM();
        var companions = _swapBehavior.GetCompanionAgents();
        int n = Math.Min(companions.Count, 8);
        for (int i = 0; i < n; i++)
        {
            var a = companions[i];
            if (a?.Character == null) continue;
            try
            {
                _markerVM.SetPortrait(i, new CharacterImageIdentifierVM(CharacterCode.CreateFrom(a.Character)));
            }
            catch (Exception ex) { CrestDiag.LogCaught(Source, "SetPortrait", ex); }
        }

        _markerLayer = new GauntletLayer("GauntletLayer", 201, false);
        _markerLayer.LoadMovie("CrestCompanionMarkers", _markerVM);
        AddLayer(missionScreen, _markerLayer);
    }

    private void CloseMenu()
    {
        if (!_isMenuOpen) return;
        _isMenuOpen = false;
        _menuOpenTicks = 0;

        if (Mission.Current != null && _removeTimeSpeedRequestMethod != null)
        {
            try { _removeTimeSpeedRequestMethod.Invoke(Mission.Current, new object[] { TimeSlowId }); }
            catch (Exception ex) { CrestDiag.LogCaught(Source, "RemoveTimeSpeedRequest", ex); }
        }

        var missionScreen = GetMissionScreen();
        if (_portraitLayer != null)
        {
            _portraitLayer.InputRestrictions.ResetInputRestrictions();
            if (missionScreen != null) RemoveLayer(missionScreen, _portraitLayer);
            _portraitLayer = null;
        }
        _portraitVM = null;

        if (_markerLayer != null)
        {
            if (missionScreen != null) RemoveLayer(missionScreen, _markerLayer);
            _markerLayer = null;
        }
        _markerVM = null;
    }

    private void UpdateMarkers()
    {
        if (Mission.Current == null || _swapBehavior == null || _markerVM == null) return;

        var companions = _swapBehavior.GetCompanionAgents();
        if (companions.Count == 0) { _markerVM.ClearSlots(); return; }

        var missionScreen = GetMissionScreen();
        var cam = GetCombatCamera(missionScreen);
        if (cam == null) return;

        var mainAgent = Mission.Current.MainAgent;
        float screenW = Screen.RealScreenResolutionWidth;
        float screenH = Screen.RealScreenResolutionHeight;
        float scaleX = screenW > 1f ? CanvasW / screenW : 1f;
        float scaleY = screenH > 1f ? CanvasH / screenH : 1f;

        int n = Math.Min(companions.Count, 8);
        int visibleMask = 0;
        for (int i = 0; i < n; i++)
        {
            var a = companions[i];
            if (!a.IsActive()) continue;

            var pos = a.GetEyeGlobalPosition();
            pos.z += 0.35f;
            float sx = 0f, sy = 0f, sw = 0f;
            if (!WorldToScreen(cam, pos, ref sx, ref sy, ref sw)) continue;
            if (sw <= 0f) continue;

            int x = (int)(sx * scaleX - MarkerW / 2f);
            int y = (int)(sy * scaleY - MarkerH);
            x = Math.Max(0, Math.Min((int)(CanvasW - MarkerW), x));
            y = Math.Max(0, Math.Min((int)(CanvasH - MarkerH), y));

            _markerVM.SetSlot(i, x, y, a == mainAgent);
            visibleMask |= 1 << i;
        }
        for (int i = 0; i < 8; i++)
        {
            if ((visibleMask & (1 << i)) == 0)
                _markerVM.HideSlot(i);
        }
    }

    private void HandleMarkerClick()
    {
        if (Mission.Current == null || _swapBehavior == null) return;

        var companions = _swapBehavior.GetCompanionAgents();
        if (companions.Count == 0) return;

        var missionScreen = GetMissionScreen();
        var cam = GetCombatCamera(missionScreen);
        if (cam == null) return;

        var mp = Input.MousePositionRanged;
        float mx = mp.X, my = mp.Y;
        float screenW = Screen.RealScreenResolutionWidth;
        float screenH = Screen.RealScreenResolutionHeight;

        int n = Math.Min(companions.Count, 8);
        for (int i = 0; i < n; i++)
        {
            var a = companions[i];
            if (!a.IsActive()) continue;

            var pos = a.GetEyeGlobalPosition();
            pos.z += 0.35f;
            float sx = 0f, sy = 0f, sw = 0f;
            if (!WorldToScreen(cam, pos, ref sx, ref sy, ref sw)) continue;
            if (sw <= 0f) continue;

            float nx = screenW > 1f ? sx / screenW : sx;
            float ny = screenH > 1f ? sy / screenH : sy;
            float dx = mx - nx, dy = my - ny;
            if (dx * dx + dy * dy < ClickRadiusSq)
            {
                _swapBehavior.SwapToAgent(a);
                CloseMenu(); // Phase Y.3-fix: close menu after picking via marker
                break;
            }
        }
    }
}
