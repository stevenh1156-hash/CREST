using System;
using System.Reflection;
using HarmonyLib;
using HarmonyLib.BUTR.Extensions;
using TaleWorlds.MountAndBlade;

namespace Bannerlord.Harmony;

internal static class CrestTacticPatch
{
	private const string Source = "CrestTacticPatch";

	private static bool _patched;

	public static void TryApply(HarmonyLib.Harmony harmony)
	{
		if (_patched)
		{
			return;
		}
		try
		{
			MethodInfo methodInfo = AccessTools2.Method(typeof(TacticComponent), "SetDefaultBehaviorWeights", new Type[1] { typeof(Formation) });
			if (methodInfo == null)
			{
				CrestDiag.Log("CrestTacticPatch", "TacticComponent.SetDefaultBehaviorWeights not found");
				_patched = true;
				return;
			}
			HarmonyMethod prefix = new HarmonyMethod(typeof(CrestTacticPatch), "SetDefaultBehaviorWeightsPrefix");
			harmony.Patch(methodInfo, prefix);
			_patched = true;
			CrestDiag.Log("CrestTacticPatch", "patched TacticComponent.SetDefaultBehaviorWeights (skip for slot >= 10)");
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestTacticPatch", "TryApply", ex);
			_patched = true;
		}
	}

	public static bool SetDefaultBehaviorWeightsPrefix(Formation f)
	{
		try
		{
			if (f == null)
			{
				return true;
			}
			if (CrestConfig.IsEnabled("EnableTacticSkipForCustomFormations") && f.Index >= 10)
			{
				return false;
			}
		}
		catch
		{
		}
		return true;
	}
}
