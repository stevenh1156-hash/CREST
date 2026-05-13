using System;
using System.IO;

using TaleWorlds.MountAndBlade;

namespace Bannerlord.Harmony;

/// <summary>
/// Y.70 Phase A -- drops a sentinel file in the deployed CREST module
/// folder when a Mission ends. The watcher (crest-dev.ps1) polls for
/// this sentinel and, when it appears, queues a postmortem run
/// automatically -- no need for the user to type "done".
///
/// Design note (2026-05-09): the original implementation used a
/// Harmony patch on <c>Mission.EndMission</c>, but that method does not
/// fire on Bannerlord v1.4.3 normal battle-end paths (battle ends are
/// driven by MissionLogic.OnEndMission callbacks, not by an explicit
/// Mission.EndMission() call). The reliable hook is to invoke
/// <see cref="DropSentinel"/> from
/// <see cref="CrestBattleConvergenceLogic.OnEndMission"/>, which runs
/// every time a mission ends. The patch entry point is gone; this is
/// a plain helper class now.
///
/// Pairs with the agent-side auto-detect rule (START.md section 0.2).
/// End-to-end: play battle → DropSentinel → watcher queues
/// auto-postmortem → result lands → next chat message gets the report.
/// </summary>
public static class CrestBattleEndSignal
{
    private const string Source = "CrestBattleEndSignal";

    // Debounce -- OnEndMission can fire twice during teardown (Victory
    // screen + actual exit). Skip a second drop within 5 seconds.
    private static DateTime _lastDrop = DateTime.MinValue;
    private const int DebounceSec = 5;

    /// <summary>
    /// Called from <c>CrestBattleConvergenceLogic.OnEndMission</c>.
    /// Writes <c>Modules\CREST\battle-ended.txt</c> with battle stats
    /// when a recording is active for the just-ended mission.
    /// </summary>
    public static void DropSentinel(Mission mission)
    {
        try
        {
            if (mission == null) { return; }

            // Debounce double-fire.
            var sinceLast = DateTime.Now - _lastDrop;
            if (sinceLast.TotalSeconds < DebounceSec)
            {
                CrestDiag.Log(Source, "skip: debounced (last drop " + sinceLast.TotalSeconds.ToString("F1") + "s ago)");
                return;
            }

            var path = ResolveSentinelPath();
            if (path == null) return;

            // Only fire if a recording file exists in the CREST folder --
            // that's set up by Crest-Ready.ps1 before a battle, so it's a
            // strong signal "this was a battle we cared about".
            var crestRoot = Path.GetDirectoryName(path);
            if (crestRoot == null) return;
            var anyRecording = false;
            try
            {
                anyRecording = Directory.GetFiles(crestRoot, "record-*.jsonl").Length > 0;
            }
            catch { }
            if (!anyRecording)
            {
                CrestDiag.Log(Source, "skip: no record-*.jsonl in module folder (no recording active)");
                return;
            }

            // Compact stats. Wrap each access in try because TaleWorlds
            // objects can throw during teardown.
            float missionTime = 0f;
            try { missionTime = mission.CurrentTime; } catch { }

            int allyCount = 0, enemyCount = 0;
            try
            {
                if (mission.Teams != null)
                {
                    foreach (var team in mission.Teams)
                    {
                        if (team == null) continue;
                        bool isPlayer = false;
                        try { isPlayer = team.IsPlayerAlly || object.ReferenceEquals(team, mission.PlayerTeam); } catch { }
                        int n = 0;
                        try
                        {
                            if (team.ActiveAgents != null)
                            {
                                foreach (var a in team.ActiveAgents)
                                {
                                    if (a != null) n++;
                                }
                            }
                        }
                        catch { }
                        if (isPlayer) allyCount += n; else enemyCount += n;
                    }
                }
            }
            catch { }

            var content =
                "endedAt="     + DateTime.Now.ToString("o") + "\n" +
                "missionTime=" + missionTime.ToString("F2")  + "\n" +
                "allyAgents="  + allyCount  + "\n" +
                "enemyAgents=" + enemyCount + "\n";
            File.WriteAllText(path, content);
            _lastDrop = DateTime.Now;

            CrestDiag.Log(Source,
                "battle-ended sentinel dropped (allies=" + allyCount +
                " enemies=" + enemyCount +
                " t=" + missionTime.ToString("F1") + ")");
        }
        catch (Exception ex)
        {
            try { CrestDiag.LogCaught(Source, "DropSentinel", ex); } catch { }
        }
    }

    private static string? ResolveSentinelPath()
    {
        try
        {
            var asmLoc = typeof(CrestBattleEndSignal).Assembly.Location;
            if (string.IsNullOrEmpty(asmLoc)) return null;
            // Crest.Harmony.dll lives at Modules\CREST\bin\Win64_Shipping_Client\.
            // Two parents up = Modules\CREST. Sentinel lives at the module root.
            var binDir = Path.GetDirectoryName(asmLoc);
            if (binDir == null) return null;
            var binParent = Directory.GetParent(binDir);
            if (binParent == null) return null;
            var crestRoot = binParent.Parent;
            if (crestRoot == null) return null;
            return Path.Combine(crestRoot.FullName, "battle-ended.txt");
        }
        catch
        {
            return null;
        }
    }
}
