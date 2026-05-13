using System;
using TaleWorlds.MountAndBlade;

namespace Bannerlord.Harmony;

internal static class CrestBattleConvergence
{
	private const string Source = "CrestBattleConvergence";

	// CREST v0.9.3 hotfix: Battle Convergence is HARD-DISABLED in this release.
	// The feature has a documented regression (CTD at battle start when
	// enabled) that is held for v1.0.0. The MCM-side toggle still appears in
	// the in-game Options panel (we couldn't rebuild Crest.MCM.UI tonight due
	// to a NuGet .pp content-file preprocessing bug for LightInject.Source),
	// but flipping it has no effect: this method returns immediately regardless
	// of the EnableBattleConvergence config flag, so the broken
	// CrestBattleConvergenceLogic mission behavior is never added. Removing
	// the MCM-side toggle visibility is a v0.9.4 task once the build issue
	// is resolved.
	public static void AddMissionBehaviors(Mission mission)
	{
		// Permanently no-op. Earlier this method honored the
		// EnableBattleConvergence config flag and called CrestBetaBridge.
		// AddConvergenceMissionBehavior to install CrestBattleConvergenceLogic.
		// That code path is preserved in git history and will be restored once
		// the v1.0.0 rework lands. Until then, keep the unused parameter to
		// preserve the public API signature and log a single line so future
		// diagnostics can confirm the disable is active.
		if (mission == null) return;
		CrestDiag.Log("CrestBattleConvergence", "AddMissionBehaviors: feature is HARD-DISABLED in v0.9.3 -- no behavior added (EnableBattleConvergence flag is ignored)");
	}
}
