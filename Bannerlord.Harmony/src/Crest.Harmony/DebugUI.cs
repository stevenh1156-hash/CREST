using Bannerlord.BUTR.Shared.Extensions;
using Bannerlord.BUTR.Shared.Helpers;

using HarmonyLib;

using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.Linq;
using System.Reflection;

using TaleWorlds.Engine;

namespace Bannerlord.Harmony;

// Original idea taken from BannerlordCoop
// https://github.com/Bannerlord-Coop-Team/BannerlordCoop/blob/95606e899763b71f62ed5a0fcfcb2e2d8c1b7e92/source/Coop/Mod/DebugUtil/DebugUI.cs
public class DebugUI
{
    private record HarmonyPatches
    {
        public ICollection<Patch> Prefixes { get; } = new List<Patch>();
        public ICollection<Patch> Postfixes { get; } = new List<Patch>();
        public ICollection<Patch> Transpilers { get; } = new List<Patch>();
        public ICollection<Patch> Finalizers { get; } = new List<Patch>();
    }

    private static readonly string _windowTitle = "Harmony Debug UI";
    private static readonly string _displayModeChoises = "Patch List\0Patch List Grouped by Modules\0";

    public bool Visible { get; set; }

    private int _displayModeChoisesIndex;
    private float _timeCounter;
    private readonly Dictionary<string, Dictionary<MethodBase, HarmonyPatches>> _patchesByModule = new();

    public void Update(float dt)
    {
        if (Visible)
        {
            Begin();
            AddButtons();
            DisplayPatchedMethods();
            End();

            _timeCounter += dt;
            if (_timeCounter >= 3F)
            {
                _timeCounter = 0F;
                RebuildPatchesByModule();
            }
        }
    }

    /// <summary>
    /// Phase P.1 (M2): hoisted out of <see cref="Update"/> and de-duplicated.
    /// The previous implementation called <c>ModuleInfoHelper.GetModuleByType</c>
    /// once per Harmony patch (typically 4× per original method, since prefix /
    /// postfix / transpiler / finalizer all live on the same DeclaringType).
    /// Now we memoize the type → moduleId resolution within a single rebuild,
    /// and a single helper method handles all four patch lists. Same external
    /// behavior; far less reflection per 3-second tick.
    /// </summary>
    private void RebuildPatchesByModule()
    {
        _patchesByModule.Clear();
        var moduleIdByType = new Dictionary<System.Type, string>();
        string ResolveModuleId(System.Type declaringType)
        {
            if (moduleIdByType.TryGetValue(declaringType, out var cached)) return cached;
            var moduleInfo = ModuleInfoHelper.GetModuleByType(declaringType);
            var moduleId = moduleInfo is null ? "NOT WITHIN A MODULE" : moduleInfo.Id;
            moduleIdByType[declaringType] = moduleId;
            return moduleId;
        }

        void AddPatches(MethodBase originalMethod, IEnumerable<Patch> source, System.Action<HarmonyPatches, Patch> bucket)
        {
            foreach (var patch in source)
            {
                if (patch.PatchMethod.DeclaringType is null) continue;
                var moduleId = ResolveModuleId(patch.PatchMethod.DeclaringType);

                if (!_patchesByModule.TryGetValue(moduleId, out var list))
                {
                    list = new Dictionary<MethodBase, HarmonyPatches>();
                    _patchesByModule.Add(moduleId, list);
                }
                if (!list.TryGetValue(originalMethod, out var hPatches))
                {
                    hPatches = new HarmonyPatches();
                    list.Add(originalMethod, hPatches);
                }
                bucket(hPatches, patch);
            }
        }

        foreach (var originalMethod in HarmonyLib.Harmony.GetAllPatchedMethods())
        {
            var patches = HarmonyLib.Harmony.GetPatchInfo(originalMethod);
            if (originalMethod is null || patches is null) continue;

            AddPatches(originalMethod, patches.Prefixes,    (h, p) => h.Prefixes.Add(p));
            AddPatches(originalMethod, patches.Postfixes,   (h, p) => h.Postfixes.Add(p));
            AddPatches(originalMethod, patches.Transpilers, (h, p) => h.Transpilers.Add(p));
            AddPatches(originalMethod, patches.Finalizers,  (h, p) => h.Finalizers.Add(p));
        }
    }

    private void DisplayPatchedMethods()
    {
        switch (_displayModeChoisesIndex)
        {
            case 0:
                if (!Imgui.TreeNode("Patch List")) return;
                DisplayPatchList();
                Imgui.TreePop();
                break;
            case 1:
                if (!Imgui.TreeNode("Patch List Grouped by Modules")) return;
                DisplayPatchListGroupedByModules();
                Imgui.TreePop();
                break;
        }
    }

    private void DisplayPatchList()
    {
        foreach (var (originalMethod, patches) in _patchesByModule.SelectMany(x => x.Value))
        {
            DisplayOriginalWithPatches(originalMethod, patches);
        }
    }

    private void DisplayPatchListGroupedByModules()
    {
        foreach (var (moduleId, patchesDictionary) in _patchesByModule)
        {
            if (!Imgui.TreeNode(moduleId)) continue;

            foreach (var (originalMethod, patches) in patchesDictionary)
            {
                DisplayOriginalWithPatches(originalMethod, patches);
            }
            Imgui.TreePop();
        }
    }

    [SuppressMessage("ReSharper", "PossibleMultipleEnumeration")]
    private static void DisplayOriginalWithPatches(MethodBase originalMethod, HarmonyPatches patches)
    {
        var allPatches = patches.Prefixes.Concat(patches.Postfixes).Concat(patches.Transpilers).Concat(patches.Finalizers);

        if (!allPatches.Any() || !Imgui.TreeNode(originalMethod.FullDescription())) return;

        Imgui.Columns(7);
        Imgui.Text("Type");
        foreach (var _ in patches.Prefixes) Imgui.Text("Prefix");
        foreach (var _ in patches.Postfixes) Imgui.Text("Postfix");
        foreach (var _ in patches.Transpilers) Imgui.Text("Transpiler");
        foreach (var _ in patches.Finalizers) Imgui.Text("Finalizer");

        Imgui.NextColumn();
        Imgui.Text("Owner");
        foreach (var patch in allPatches) Imgui.Text(patch.owner);

        Imgui.NextColumn();
        Imgui.Text("Method");
        foreach (var patch in allPatches) Imgui.Text($"{patch.PatchMethod.DeclaringType!.FullName}.{patch.PatchMethod.Name}");

        Imgui.NextColumn();
        Imgui.Text("Index");
        foreach (var patch in allPatches) Imgui.Text($"{patch.index}");

        Imgui.NextColumn();
        Imgui.Text("Priority");
        foreach (var patch in allPatches) Imgui.Text($"{patch.priority}");

        Imgui.NextColumn();
        Imgui.Text("Before");
        foreach (var patch in allPatches) Imgui.Text($"{string.Join(",", patch.before)}");

        Imgui.NextColumn();
        Imgui.Text("After");
        Imgui.Separator();
        foreach (var patch in allPatches) Imgui.Text($"{string.Join(",", patch.after)}");

        Imgui.Columns();

        Imgui.TreePop();
    }

    private void Begin()
    {
        Imgui.BeginMainThreadScope();
        Imgui.Begin(_windowTitle);
    }

    private void AddButtons()
    {
        Imgui.NewLine();
        Imgui.SameLine(20);
        if (Imgui.SmallButton("Close DebugUI"))
        {
            Visible = false;
        }

        // Phase R.2: capture a full patch snapshot to a timestamped file in
        // Modules\CREST\. Same action as the Ctrl+Alt+P hotkey, surfaced here
        // so users who already have the imgui panel open can grab a report
        // without closing the panel and Alt+Tabbing back to the game viewport.
        Imgui.SameLine(160);
        if (Imgui.SmallButton("Export Snapshot"))
        {
            var path = CrestPatchSnapshot.Capture();
            _lastSnapshotResult = string.IsNullOrEmpty(path)
                ? "snapshot failed (see runtime.log)"
                : "saved: " + System.IO.Path.GetFileName(path);
        }
        if (!string.IsNullOrEmpty(_lastSnapshotResult))
        {
            Imgui.SameLine(310);
            Imgui.Text(_lastSnapshotResult);
        }

        Imgui.NewLine();
        Imgui.SameLine(20);
        Imgui.Combo("Display Mode", ref _displayModeChoisesIndex, _displayModeChoises);

        Imgui.NewLine();
    }

    private string? _lastSnapshotResult;

    private void End()
    {
        Imgui.End();
        Imgui.EndMainThreadScope();
    }
}