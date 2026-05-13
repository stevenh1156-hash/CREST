using System;
using System.Reflection;
using TaleWorlds.MountAndBlade;

namespace Bannerlord.Harmony;

internal static class CrestBattleHornCue
{
	private const string Source = "CrestBattleHornCue";

	private static int _hornEventId = -2;

	private static MethodInfo? _playSoundMethod;

	private static Type? _vec3Type;

	private static object? _vec3Zero;

	private static float _lastHornAt;

	private const float HornCooldownSec = 3f;

	private static bool _diagLoggedReady;

	private static bool _diagLoggedFail;

	public static void TryPlayJoinHorn()
	{
		try
		{
			if (!CrestConfig.IsEnabled("EnableJoinWarHorn"))
			{
				return;
			}
			Mission current = Mission.Current;
			if (current == null)
			{
				return;
			}
			float currentTime = current.CurrentTime;
			if (!(currentTime > 0f) || !(_lastHornAt > 0f) || !(currentTime - _lastHornAt < 3f))
			{
				if (_hornEventId == -2)
				{
					ResolveSoundApi();
				}
				if (_hornEventId >= 0 && !(_playSoundMethod == null) && _vec3Zero != null)
				{
					_playSoundMethod.Invoke(null, new object[2] { _hornEventId, _vec3Zero });
					_lastHornAt = currentTime;
				}
			}
		}
		catch (Exception ex)
		{
			if (!_diagLoggedFail)
			{
				_diagLoggedFail = true;
				CrestDiag.LogCaught("CrestBattleHornCue", "TryPlayJoinHorn", ex);
			}
		}
	}

	private static void ResolveSoundApi()
	{
		try
		{
			Type type = Type.GetType("TaleWorlds.MountAndBlade.MBSoundEvent, TaleWorlds.MountAndBlade", throwOnError: false) ?? Type.GetType("TaleWorlds.Engine.SoundEvent, TaleWorlds.Engine", throwOnError: false);
			if (type == null)
			{
				_hornEventId = -1;
				if (!_diagLoggedFail)
				{
					_diagLoggedFail = true;
					CrestDiag.Log("CrestBattleHornCue", "MBSoundEvent type not found -- horn cue disabled");
				}
				return;
			}
			MethodInfo method = type.GetMethod("GetEventIdFromString", BindingFlags.Static | BindingFlags.Public);
			if (method == null)
			{
				_hornEventId = -1;
				if (!_diagLoggedFail)
				{
					_diagLoggedFail = true;
					CrestDiag.Log("CrestBattleHornCue", "GetEventIdFromString not found -- horn cue disabled");
				}
				return;
			}
			string value = null;
			int num = -1;
			string[] array = new string[5] { "event:/mission/combat/horn/charge", "event:/mission/combat/horn/move_forward", "event:/mission/combat/horn", "event:/mission/horn/charge", "event:/mission/horn" };
			foreach (string text in array)
			{
				try
				{
					if (method.Invoke(null, new object[1] { text }) is int num2 && num2 >= 0)
					{
						num = num2;
						value = text;
						break;
					}
				}
				catch
				{
				}
			}
			if (num < 0)
			{
				_hornEventId = -1;
				if (!_diagLoggedFail)
				{
					_diagLoggedFail = true;
					CrestDiag.Log("CrestBattleHornCue", "no known horn event id resolved -- cue disabled (engine sound bank may have moved)");
				}
				return;
			}
			MethodInfo methodInfo = null;
			MethodInfo[] methods = type.GetMethods(BindingFlags.Static | BindingFlags.Public);
			foreach (MethodInfo methodInfo2 in methods)
			{
				if (!(methodInfo2.Name != "PlaySound"))
				{
					ParameterInfo[] parameters = methodInfo2.GetParameters();
					if (parameters.Length == 2 && parameters[0].ParameterType == typeof(int))
					{
						methodInfo = methodInfo2;
						_vec3Type = parameters[1].ParameterType;
						break;
					}
				}
			}
			if (methodInfo == null || _vec3Type == null)
			{
				_hornEventId = -1;
				if (!_diagLoggedFail)
				{
					_diagLoggedFail = true;
					CrestDiag.Log("CrestBattleHornCue", "PlaySound(int, Vec3) not found -- horn cue disabled");
				}
				return;
			}
			_vec3Zero = Activator.CreateInstance(_vec3Type);
			_playSoundMethod = methodInfo;
			_hornEventId = num;
			if (!_diagLoggedReady)
			{
				_diagLoggedReady = true;
				CrestDiag.Log("CrestBattleHornCue", $"horn cue ready (path={value} eventId={num})");
			}
		}
		catch (Exception ex)
		{
			_hornEventId = -1;
			if (!_diagLoggedFail)
			{
				_diagLoggedFail = true;
				CrestDiag.LogCaught("CrestBattleHornCue", "ResolveSoundApi", ex);
			}
		}
	}
}
