using System;
using System.Reflection;
using System.Threading;
using HarmonyLib;
using HarmonyLib.BUTR.Extensions;

namespace Bannerlord.Harmony;

internal static class CrestBrushRacePatch
{
	private const string Source = "CrestBrushRacePatch";

	private static bool _patched;

	private static long _swallowCount;

	private static DateTime _lastLog = DateTime.MinValue;

	public static void TryApply(HarmonyLib.Harmony harmony)
	{
		if (_patched)
		{
			return;
		}
		try
		{
			Type type = Type.GetType("TaleWorlds.GauntletUI.EventManager, TaleWorlds.GauntletUI", throwOnError: false);
			if (type == null)
			{
				CrestDiag.Log("CrestBrushRacePatch", "TaleWorlds.GauntletUI.EventManager type not found -- patch skipped");
				_patched = true;
				return;
			}
			MethodInfo methodInfo = AccessTools2.Method(type, "UpdateBrushesWidget", new Type[3]
			{
				typeof(int),
				typeof(int),
				typeof(float)
			});
			if (methodInfo == null)
			{
				CrestDiag.Log("CrestBrushRacePatch", "EventManager.UpdateBrushesWidget(int,int,float) not found -- patch skipped");
				_patched = true;
				return;
			}
			HarmonyMethod finalizer = new HarmonyMethod(typeof(CrestBrushRacePatch), "UpdateBrushesWidgetFinalizer");
			harmony.Patch(methodInfo, null, null, null, finalizer);
			_patched = true;
			CrestDiag.Log("CrestBrushRacePatch", "patched EventManager.UpdateBrushesWidget (swallow ArgumentOutOfRangeException for v1.4.3 brush race)");
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBrushRacePatch", "TryApply", ex);
			_patched = true;
		}
	}

	public static Exception? UpdateBrushesWidgetFinalizer(Exception __exception)
	{
		if (__exception == null)
		{
			return null;
		}
		if (!(__exception is ArgumentOutOfRangeException))
		{
			return __exception;
		}
		if (!CrestConfig.IsEnabled("EnableBrushRaceMitigation"))
		{
			return __exception;
		}
		long num = Interlocked.Increment(ref _swallowCount);
		DateTime utcNow = DateTime.UtcNow;
		if (num == 1 || (utcNow - _lastLog).TotalSeconds >= 10.0)
		{
			_lastLog = utcNow;
			try
			{
				CrestDiag.Log("CrestBrushRacePatch", $"swallowed v1.4.3 UpdateBrushesWidget AOORE (count={num})");
			}
			catch
			{
			}
		}
		return null;
	}
}
