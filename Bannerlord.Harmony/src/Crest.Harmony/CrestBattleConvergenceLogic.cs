using System;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text;
using HarmonyLib.BUTR.Extensions;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.AgentOrigins;
using TaleWorlds.CampaignSystem.CharacterDevelopment;
using TaleWorlds.CampaignSystem.Encounters;
using TaleWorlds.CampaignSystem.MapEvents;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Roster;
using TaleWorlds.Core;
using TaleWorlds.DotNet;
using TaleWorlds.Engine;
using TaleWorlds.Library;
using TaleWorlds.Localization;
using TaleWorlds.MountAndBlade;

namespace Bannerlord.Harmony;

#if BANNERLORD_API_1_4_PLUS
// Battle Convergence depends on TaleWorlds API surface that exists only in
// the 1.4 line: GetFormationSpawnFrame's 6-arg overload, and the order of
// constructor arguments at the spawn-agent call site. The Public (1.3.x)
// build excludes this entire class. The CrestBattleConvergence wrapper
// degrades to a no-op when the symbol is missing (see CrestBattleConvergence.cs),
// and the EnableBattleConvergence config flag is default false anyway, so
// no Public-build user can hit a runtime path that needs this class.

internal sealed class CrestBattleConvergenceLogic : MissionLogic
{
	private sealed class CrestPool
	{
		public Formation? Infantry;

		public Formation? Archers;

		public Formation? Cavalry;

		public int LordCount;

		public int LeadTactics = -1;

		public PartyBase? LeadParty;

		public float SpawnTime = -1f;

		public bool InfCavAdvanceApplied;

		public bool ArchAdvanceApplied;

		public float LastParityCheck = -1f;

		public int LastParityDelta = int.MinValue;

		public bool ShieldWallActive;

		public float ShieldWallStopAt = -1f;

		public bool CircleActive;

		public float LastReassertAt = -1f;

		public MovementOrder IntendedInfMovement = MovementOrder.MovementOrderStop;

		public MovementOrder IntendedArchMovement = MovementOrder.MovementOrderStop;

		public MovementOrder IntendedCavMovement = MovementOrder.MovementOrderStop;

		public ArrangementOrder IntendedInfArrangement = ArrangementOrder.ArrangementOrderLine;

		public ArrangementOrder IntendedArchArrangement = ArrangementOrder.ArrangementOrderLoose;

		public ArrangementOrder IntendedCavArrangement = ArrangementOrder.ArrangementOrderSkein;

		public bool IsEnemyPool;
	}

	private sealed class RS_CandidateParty
	{
		public MobileParty mobileParty;

		public short teamnumber;

		public float deadlineMissionTime;

		public bool isarrived;

		public bool isdone;

		public float distAtDiscovery;

		public RS_CandidateParty(MobileParty mp, short team, float delay, float currentMissionTime, float dist)
		{
			mobileParty = mp;
			teamnumber = team;
			deadlineMissionTime = currentMissionTime + delay;
			distAtDiscovery = dist;
		}

		public bool IsArrived()
		{
			try
			{
				return Mission.Current != null && Mission.Current.CurrentTime >= deadlineMissionTime;
			}
			catch
			{
				return false;
			}
		}
	}

	private const string Source = "CrestBattleConvergenceLogic";

	private bool reinforceswitch;

	private bool spawnswitch;

	private bool enemiesalwayscharge;

	private bool debugmode;

	private bool missionend;

	private bool firstdefend;

	private bool firstattack;

	private BattleSideEnum currentplayerside;

	private bool isplayerdefender;

	private object? missionAgentSpawnLogic;

	private int timerset = 1000;

	private int radioussetting = 15;

	private short howmanydef = 3;

	private short howmanyatt = 3;

	private MissionTimer? addspawntimer;

	private readonly List<RS_CandidateParty> candidateParties = new List<RS_CandidateParty>();

	private readonly List<MobileParty> PlayerReinforceParties = new List<MobileParty>();

	private readonly HashSet<MobileParty> _playerSideRescueParties = new HashSet<MobileParty>();

	private readonly List<Vec3> DefenderSpawnPosition = new List<Vec3>();

	private readonly List<Vec3> AttackerSpawnPosition = new List<Vec3>();

	private readonly List<Vec3> _allDefenderFleePositions = new List<Vec3>();

	private readonly List<Vec3> _allAttackerFleePositions = new List<Vec3>();

	private Vec3 _battleCenter;

	private readonly Dictionary<PartyBase, Vec3> _partySpawnPositions = new Dictionary<PartyBase, Vec3>();

	private readonly Dictionary<Formation, Vec3> _formationSpawnPositions = new Dictionary<Formation, Vec3>();

	private readonly Dictionary<Formation, string> _formationAttachedBehavior = new Dictionary<Formation, string>();

	private readonly Dictionary<Formation, MovementOrder> _y56MovementOverride = new Dictionary<Formation, MovementOrder>();

	private readonly Dictionary<Formation, ArrangementOrder> _y56ArrangementOverride = new Dictionary<Formation, ArrangementOrder>();

	private List<CrestSpot> _allySpots = new List<CrestSpot>();

	private List<CrestSpot> _enemySpots = new List<CrestSpot>();

	private float _lastTacticsDiagAt = -1f;

	private const float TacticsDiagIntervalSec = 5f;

	private ConcurrentQueue<MobileParty> Defender_Collect = new ConcurrentQueue<MobileParty>();

	private ConcurrentQueue<MobileParty> Attacker_Collect = new ConcurrentQueue<MobileParty>();

	private ConcurrentQueue<IAgentOriginBase> reserved_Defender_Queue = new ConcurrentQueue<IAgentOriginBase>();

	private ConcurrentQueue<IAgentOriginBase> reserved_Attacker_Queue = new ConcurrentQueue<IAgentOriginBase>();

	private readonly HashSet<Agent> NewAgentsDefend = new HashSet<Agent>();

	private readonly HashSet<Agent> NewAgentsAttack = new HashSet<Agent>();

	private readonly HashSet<Formation> _configuredFormations = new HashSet<Formation>();

	private bool _capGuardLogged;

	private readonly List<CrestPool> _allyPools = new List<CrestPool>();

	private readonly Dictionary<PartyBase, int> _lordPoolIndex = new Dictionary<PartyBase, int>();

	private const int LORDS_PER_POOL = 3;

	private readonly List<CrestPool> _enemyPools = new List<CrestPool>();

	private readonly Dictionary<PartyBase, int> _enemyLordPoolIndex = new Dictionary<PartyBase, int>();

	private readonly HashSet<Formation> _customEnemyFormations = new HashSet<Formation>();

	private const int ENEMY_POOL_BASE_SLOT = 10;

	private readonly Dictionary<PartyBase, Formation> _partyCustomFormation = new Dictionary<PartyBase, Formation>();

	private readonly List<Formation> _customAllyFormations = new List<Formation>();

	private readonly Dictionary<Formation, int> _formationLeaderTactics = new Dictionary<Formation, int>();

	private int _allyFormationSlotCounter;

	private int _activeDefenderJoiners;

	private int _activeAttackerJoiners;

	private readonly Queue<(MobileParty party, short teamnumber, float dist)> _waitingDefenderQueue = new Queue<(MobileParty, short, float)>();

	private readonly Queue<(MobileParty party, short teamnumber, float dist)> _waitingAttackerQueue = new Queue<(MobileParty, short, float)>();

	private readonly Dictionary<PartyBase, int> _partyLiveAgentCount = new Dictionary<PartyBase, int>();

	private readonly Dictionary<Agent, PartyBase> _agentParty = new Dictionary<Agent, PartyBase>();

	private int _defenderSpawnIdx;

	private int _attackerSpawnIdx;

	private bool _stage1Done;

	private float _diagTickAccum;

	private bool _firstTickLogged;

	private int _lastPendingCount = -1;

	private static MethodInfo? _addNearbyToMapEventMethod;

	private static bool _addNearbyResolved;

	private readonly List<MobileParty> _joinerPartiesAddedToMapEvent = new List<MobileParty>();

	private static MethodInfo? _removeNearbyToMapEventMethod;

	private static bool _removeNearbyResolved;

	private static PropertyInfo? _qsPositionProp;

	private static bool _qsDiscoveryLogged;

	private static bool _formationMoveDiscoveryLogged;

	private static bool _teamTacticDiscoveryLogged;

	private static bool _behaviorDiscoveryLogged;

	private static bool _losDiscoveryLogged;

	public override MissionBehaviorType BehaviorType => (MissionBehaviorType)1;

	private short GetLowestTroopSideTeamNumber()
	{
		//IL_004f: Unknown result type (might be due to invalid IL or missing references)
		//IL_0055: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			Mission current = Mission.Current;
			if (((current != null) ? current.Teams : null) == null)
			{
				return 0;
			}
			int num = 0;
			int num2 = 0;
			foreach (Team item in (List<Team>)(object)current.Teams)
			{
				if (item != null)
				{
					int num3 = ((List<Agent>)(object)item.ActiveAgents)?.Count ?? 0;
					if (item.Side == currentplayerside)
					{
						num += num3;
					}
					else
					{
						num2 += num3;
					}
				}
			}
			return (num > num2) ? ((short)1) : ((short)0);
		}
		catch
		{
			return 0;
		}
	}

	private short? DetermineTeamNumber(MobileParty candidate, IFaction? attackerFaction, IFaction? defenderFaction)
	{
		//IL_0038: Unknown result type (might be due to invalid IL or missing references)
		//IL_003e: Invalid comparison between Unknown and I4
		//IL_0057: Unknown result type (might be due to invalid IL or missing references)
		//IL_005d: Invalid comparison between Unknown and I4
		//IL_0091: Unknown result type (might be due to invalid IL or missing references)
		//IL_0097: Invalid comparison between Unknown and I4
		//IL_00ae: Unknown result type (might be due to invalid IL or missing references)
		//IL_00b4: Invalid comparison between Unknown and I4
		try
		{
			IFaction mapFaction = candidate.MapFaction;
			if (mapFaction == null)
			{
				return null;
			}
			bool flag = attackerFaction != null && mapFaction == attackerFaction;
			bool flag2 = defenderFaction != null && mapFaction == defenderFaction;
			if (flag && !flag2)
			{
				return ((int)currentplayerside != 1) ? ((short)1) : ((short)0);
			}
			if (flag2 && !flag)
			{
				return ((int)currentplayerside > 0) ? ((short)1) : ((short)0);
			}
			bool flag3 = attackerFaction != null && mapFaction.IsAtWarWith(attackerFaction);
			bool flag4 = defenderFaction != null && mapFaction.IsAtWarWith(defenderFaction);
			if (flag3 && !flag4)
			{
				return ((int)currentplayerside > 0) ? ((short)1) : ((short)0);
			}
			if (flag4 && !flag3)
			{
				return ((int)currentplayerside != 1) ? ((short)1) : ((short)0);
			}
			if (CrestConfig.IsEnabled("BattleConvergenceDisableFilters", defaultValue: false))
			{
				return 0;
			}
			try
			{
				if (!CrestConfig.IsEnabled("BattleConvergenceRelationOverride"))
				{
					return null;
				}
				Hero leaderHero = candidate.LeaderHero;
				Hero mainHero = Hero.MainHero;
				if (leaderHero == null || mainHero == null)
				{
					return null;
				}
				int relation = leaderHero.GetRelation(mainHero);
				int num = CrestConfig.GetInt("BattleConvergenceRelationThreshold", 50);
				if (relation < num)
				{
					return null;
				}
				if (CrestConfig.IsEnabled("BattleConvergenceRequireHonor"))
				{
					int num2 = 0;
					try
					{
						num2 = leaderHero.GetTraitLevel(DefaultTraits.Honor);
					}
					catch
					{
						num2 = 0;
					}
					if (num2 < 0)
					{
						return null;
					}
				}
				CrestDiag.Log("CrestBattleConvergenceLogic", $"  relation-override: {candidate.Name} (relation={relation}, honor-bound) joins player's side");
				return 0;
			}
			catch (Exception ex)
			{
				CrestDiag.LogCaught("CrestBattleConvergenceLogic", "DetermineTeamNumber.relation-override", ex);
			}
			if (CrestConfig.IsEnabled("BattleConvergenceAcceptNeutrals"))
			{
				short lowestTroopSideTeamNumber = GetLowestTroopSideTeamNumber();
				CrestDiag.Log("CrestBattleConvergenceLogic", $"  auto-balance: {candidate.Name} ({mapFaction.Name}) joins {((lowestTroopSideTeamNumber == 0) ? "player" : "enemy")} side (lowest troop count)");
				return lowestTroopSideTeamNumber;
			}
			return null;
		}
		catch (Exception ex2)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "DetermineTeamNumber", ex2);
			return null;
		}
	}

	public override void AfterStart()
	{
		//IL_02dc: Unknown result type (might be due to invalid IL or missing references)
		//IL_01a9: Unknown result type (might be due to invalid IL or missing references)
		//IL_01ae: Unknown result type (might be due to invalid IL or missing references)
		//IL_01b5: Unknown result type (might be due to invalid IL or missing references)
		//IL_01bb: Invalid comparison between Unknown and I4
		try
		{
			((MissionBehavior)this).AfterStart();
			reinforceswitch = CrestConfig.IsEnabled("EnableBattleConvergence", defaultValue: false);
			spawnswitch = reinforceswitch;
			enemiesalwayscharge = CrestConfig.IsEnabled("BattleConvergenceForceEnemyCharge", defaultValue: false);
			debugmode = CrestConfig.IsEnabled("BattleConvergenceDebug", defaultValue: false);
			timerset = CrestConfig.GetInt("BattleConvergenceArrivalDelay", 1000);
			if (CrestConfig.IsEnabled("BattleConvergenceClanTierScaling"))
			{
				int num = 0;
				try
				{
					Clan playerClan = Clan.PlayerClan;
					num = ((playerClan != null) ? playerClan.Tier : 0);
				}
				catch
				{
					num = 0;
				}
				int num2 = CrestConfig.GetInt("BattleConvergenceClanTierMultiplier", 1);
				if (num2 < 1)
				{
					num2 = 1;
				}
				if (num2 > 3)
				{
					num2 = 3;
				}
				radioussetting = Math.Max(25, num * 25) * num2;
				CrestDiag.Log("CrestBattleConvergenceLogic", $"clan-tier-radius (progressive mode): tier={num} basePerTier={25} boost=x{num2} -> radius={radioussetting}");
			}
			else
			{
				radioussetting = Math.Max(1, CrestConfig.GetInt("BattleConvergenceRadius", 15));
				CrestDiag.Log("CrestBattleConvergenceLogic", $"flat radius (slider mode): {radioussetting}");
			}
			howmanydef = (short)Math.Max(1, Math.Min(50, CrestConfig.GetInt("BattleConvergenceMaxJoinersPerSide", 3)));
			howmanyatt = howmanydef;
			try
			{
				MapEvent encounteredBattle = PlayerEncounter.EncounteredBattle;
				if (encounteredBattle != null)
				{
					currentplayerside = encounteredBattle.PlayerSide;
					isplayerdefender = (int)currentplayerside == 0;
				}
				else
				{
					reinforceswitch = false;
					spawnswitch = false;
					CrestDiag.Log("CrestBattleConvergenceLogic", "AfterStart: PlayerEncounter.EncounteredBattle is null  --  disabled for this mission");
				}
			}
			catch (Exception ex)
			{
				CrestDiag.LogCaught("CrestBattleConvergenceLogic", "AfterStart capture player side", ex);
				reinforceswitch = false;
				spawnswitch = false;
			}
			try
			{
				missionAgentSpawnLogic = ResolveMissionAgentSpawnLogic();
			}
			catch (Exception ex2)
			{
				CrestDiag.LogCaught("CrestBattleConvergenceLogic", "AfterStart resolve MissionAgentSpawnLogic", ex2);
			}
			CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.12d AfterStart: reinforce={reinforceswitch} debug={debugmode} radius={radioussetting} maxPerSide={howmanydef} timerset={timerset} playerSide={currentplayerside} isPlayerDefender={isplayerdefender} missionAgentSpawnLogic={((missionAgentSpawnLogic != null) ? "ok" : "null")}");
		}
		catch (Exception ex3)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "AfterStart", ex3);
		}
	}

	private static object? ResolveMissionAgentSpawnLogic()
	{
		if (Mission.Current == null)
		{
			return null;
		}
		Type type = AccessTools2.TypeByName("TaleWorlds.MountAndBlade.MissionAgentSpawnLogic");
		if (type == null)
		{
			return null;
		}
		MethodInfo method = typeof(Mission).GetMethod("GetMissionBehavior", BindingFlags.Instance | BindingFlags.Public);
		if (method == null)
		{
			return null;
		}
		MethodInfo methodInfo = method.MakeGenericMethod(type);
		return methodInfo.Invoke(Mission.Current, null);
	}

	public override void OnTeamDeployed(Team team)
	{
		try
		{
			((MissionBehavior)this).OnTeamDeployed(team);
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "OnTeamDeployed", ex);
		}
	}

	public override void OnMissionModeChange(MissionMode oldMissionMode, bool atStart)
	{
		//IL_0001: Unknown result type (might be due to invalid IL or missing references)
		//IL_002a: Unknown result type (might be due to invalid IL or missing references)
		//IL_0030: Invalid comparison between Unknown and I4
		try
		{
			((MissionBehavior)this).OnMissionModeChange(oldMissionMode, atStart);
			if (!_stage1Done && reinforceswitch && Mission.Current != null && (int)Mission.Current.Mode == 2)
			{
				_stage1Done = true;
				RS_Stage1_Initialize();
			}
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "OnMissionModeChange", ex);
		}
	}

	public override void OnMissionTick(float dt)
	{
		//IL_0401: Unknown result type (might be due to invalid IL or missing references)
		//IL_0407: Invalid comparison between Unknown and I4
		//IL_00a9: Unknown result type (might be due to invalid IL or missing references)
		//IL_00ae: Unknown result type (might be due to invalid IL or missing references)
		//IL_00b5: Unknown result type (might be due to invalid IL or missing references)
		//IL_00ba: Unknown result type (might be due to invalid IL or missing references)
		//IL_00c6: Unknown result type (might be due to invalid IL or missing references)
		//IL_00d7: Unknown result type (might be due to invalid IL or missing references)
		//IL_00fd: Unknown result type (might be due to invalid IL or missing references)
		//IL_0102: Unknown result type (might be due to invalid IL or missing references)
		//IL_010e: Unknown result type (might be due to invalid IL or missing references)
		//IL_0148: Unknown result type (might be due to invalid IL or missing references)
		//IL_0159: Unknown result type (might be due to invalid IL or missing references)
		//IL_01ab: Unknown result type (might be due to invalid IL or missing references)
		//IL_01bc: Unknown result type (might be due to invalid IL or missing references)
		//IL_01f6: Unknown result type (might be due to invalid IL or missing references)
		//IL_0207: Unknown result type (might be due to invalid IL or missing references)
		//IL_01d9: Unknown result type (might be due to invalid IL or missing references)
		//IL_0241: Unknown result type (might be due to invalid IL or missing references)
		//IL_0252: Unknown result type (might be due to invalid IL or missing references)
		//IL_0224: Unknown result type (might be due to invalid IL or missing references)
		//IL_026f: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			Mission current = Mission.Current;
			if (current != null && (_allyPools.Count > 0 || _enemyPools.Count > 0))
			{
				float currentTime = current.CurrentTime;
				List<CrestPool>[] array = new List<CrestPool>[2] { _allyPools, _enemyPools };
				List<CrestPool>[] array2 = array;
				foreach (List<CrestPool> list in array2)
				{
					foreach (CrestPool item in list)
					{
						if (item == null || item.SpawnTime < 0f)
						{
							continue;
						}
						float num = currentTime - item.SpawnTime;
						if (!item.InfCavAdvanceApplied && num >= 5f)
						{
							item.IntendedInfMovement = MovementOrder.MovementOrderAdvance;
							item.IntendedCavMovement = MovementOrder.MovementOrderAdvance;
							SetMovement(item.Infantry, MovementOrder.MovementOrderAdvance);
							SetMovement(item.Cavalry, MovementOrder.MovementOrderAdvance);
							item.InfCavAdvanceApplied = true;
						}
						if (!item.ArchAdvanceApplied && num >= 8f)
						{
							item.IntendedArchMovement = MovementOrder.MovementOrderAdvance;
							SetMovement(item.Archers, MovementOrder.MovementOrderAdvance);
							item.ArchAdvanceApplied = true;
						}
						if (item.ShieldWallActive && item.ShieldWallStopAt > 0f && currentTime >= item.ShieldWallStopAt)
						{
							SetMovement(item.Infantry, MovementOrder.MovementOrderStop);
							SetMovement(item.Cavalry, MovementOrder.MovementOrderStop);
							item.ShieldWallStopAt = -1f;
						}
						if (item.LastReassertAt < 0f || currentTime - item.LastReassertAt >= 3f)
						{
							item.LastReassertAt = currentTime;
							try
							{
								if (item.Infantry != null)
								{
									ApplyArrangementOverrideOrPool(item.Infantry, item.IntendedInfArrangement);
									item.Infantry.SetFacingOrder(FacingOrder.FacingOrderLookAtEnemy);
									if (item.InfCavAdvanceApplied)
									{
										ApplyMovementOverrideOrPool(item.Infantry, item.IntendedInfMovement);
									}
								}
								if (item.Cavalry != null)
								{
									ApplyArrangementOverrideOrPool(item.Cavalry, item.IntendedCavArrangement);
									item.Cavalry.SetFacingOrder(FacingOrder.FacingOrderLookAtEnemy);
									if (item.InfCavAdvanceApplied)
									{
										ApplyMovementOverrideOrPool(item.Cavalry, item.IntendedCavMovement);
									}
								}
								if (item.Archers != null)
								{
									ApplyArrangementOverrideOrPool(item.Archers, item.IntendedArchArrangement);
									item.Archers.SetFacingOrder(FacingOrder.FacingOrderLookAtEnemy);
									if (item.ArchAdvanceApplied)
									{
										ApplyMovementOverrideOrPool(item.Archers, item.IntendedArchMovement);
									}
								}
							}
							catch (Exception ex)
							{
								CrestDiag.LogCaught("CrestBattleConvergenceLogic", "OnMissionTick.reassert", ex);
							}
						}
						if (item.LastParityCheck < 0f || currentTime - item.LastParityCheck >= 15f)
						{
							int num2 = CheckPoolParity(current);
							if (item.IsEnemyPool)
							{
								num2 = -num2;
							}
							bool flag = false;
							int num3 = ParityZone(item.LastParityDelta);
							int num4 = ParityZone(num2);
							if (num3 != num4)
							{
								flag = true;
							}
							item.LastParityCheck = currentTime;
							item.LastParityDelta = num2;
							if (flag && item.LeadTactics >= 100)
							{
								ApplyPoolTierOrders(item);
							}
						}
					}
				}
			}
		}
		catch (Exception ex2)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "OnMissionTick.poolScheduler", ex2);
		}
		try
		{
			Mission current3 = Mission.Current;
			if (current3 != null && CrestConfig.IsEnabled("BattleConvergenceTacticDiag"))
			{
				float currentTime2 = current3.CurrentTime;
				if (_lastTacticsDiagAt < 0f || currentTime2 - _lastTacticsDiagAt >= 5f)
				{
					_lastTacticsDiagAt = currentTime2;
					TickPoolDiagnostics(current3, currentTime2);
					TickSpotDiagnostics(current3, currentTime2);
				}
			}
		}
		catch (Exception ex3)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "OnMissionTick.tacticsDiag", ex3);
		}
		try
		{
			((MissionBehavior)this).OnMissionTick(dt);
			if (missionend || !reinforceswitch || !_stage1Done)
			{
				return;
			}
			Mission current4 = Mission.Current;
			if (current4 == null || (int)current4.Mode != 2)
			{
				return;
			}
			if (!_firstTickLogged)
			{
				_firstTickLogged = true;
				CrestDiag.Log("CrestBattleConvergenceLogic", $"OnMissionTick first call after Stage1: candidates={candidateParties.Count}");
			}
			_diagTickAccum += dt;
			if (_diagTickAccum >= 5f)
			{
				_diagTickAccum = 0f;
				int count = candidateParties.Count;
				int num5 = 0;
				float num6 = float.MaxValue;
				Mission current5 = Mission.Current;
				float num7 = ((current5 != null) ? current5.CurrentTime : 0f);
				foreach (RS_CandidateParty candidateParty in candidateParties)
				{
					try
					{
						float num8 = candidateParty.deadlineMissionTime - num7;
						if (num8 <= 0f)
						{
							num5++;
						}
						else if (num8 < num6)
						{
							num6 = num8;
						}
					}
					catch
					{
					}
				}
				string value = ((count > 0 && num6 != float.MaxValue) ? $"{num6:F1}s" : "n/a");
				CrestDiag.Log("CrestBattleConvergenceLogic", $"tick-status: now={num7:F1} pending={count} elapsed={num5} closestRemaining={value} collectDef={Defender_Collect.Count} collectAtt={Attacker_Collect.Count} reservedDef={reserved_Defender_Queue.Count} reservedAtt={reserved_Attacker_Queue.Count}");
			}
			for (int num9 = candidateParties.Count - 1; num9 >= 0; num9--)
			{
				RS_CandidateParty rS_CandidateParty = candidateParties[num9];
				if (rS_CandidateParty.isdone)
				{
					candidateParties.RemoveAt(num9);
				}
				else if (rS_CandidateParty.IsArrived())
				{
					rS_CandidateParty.isdone = true;
					RS_Stage2_Filter(rS_CandidateParty.mobileParty, rS_CandidateParty.teamnumber, rS_CandidateParty.distAtDiscovery);
					candidateParties.RemoveAt(num9);
				}
			}
			if (!spawnswitch || addspawntimer == null || !addspawntimer.Check(true))
			{
				return;
			}
			int num10 = 0;
			MobileParty result;
			while (num10 < howmanydef && Defender_Collect.TryDequeue(out result))
			{
				if (RS_Calculate_Join(isdefender: true) && RS_Morale_Check(isdefender: true))
				{
					RS_Register_Party(result, (BattleSideEnum)0);
					num10++;
				}
			}
			int num11 = 0;
			MobileParty result2;
			while (num11 < howmanyatt && Attacker_Collect.TryDequeue(out result2))
			{
				if (RS_Calculate_Join(isdefender: false) && RS_Morale_Check(isdefender: false))
				{
					RS_Register_Party(result2, (BattleSideEnum)1);
					num11++;
				}
			}
			if (!reserved_Defender_Queue.IsEmpty)
			{
				RS_Stage4_Spawn(isdefender: true, isplayerdefender, hasformation: true);
			}
			if (!reserved_Attacker_Queue.IsEmpty)
			{
				RS_Stage4_Spawn(isdefender: false, !isplayerdefender, hasformation: true);
			}
			if (candidateParties.Count == 0 && Defender_Collect.IsEmpty && Attacker_Collect.IsEmpty && reserved_Defender_Queue.IsEmpty && reserved_Attacker_Queue.IsEmpty)
			{
				reinforceswitch = false;
				if (debugmode)
				{
					CrestDiag.Log("CrestBattleConvergenceLogic", "all queues drained, reinforcement system disabled");
				}
			}
		}
		catch (Exception ex4)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "OnMissionTick", ex4);
		}
	}

	public override void OnAgentRemoved(Agent affectedAgent, Agent affectorAgent, AgentState agentState, KillingBlow blow)
	{
		//IL_0003: Unknown result type (might be due to invalid IL or missing references)
		//IL_0004: Unknown result type (might be due to invalid IL or missing references)
		//IL_00a6: Unknown result type (might be due to invalid IL or missing references)
		//IL_0171: Unknown result type (might be due to invalid IL or missing references)
		//IL_008b: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			((MissionBehavior)this).OnAgentRemoved(affectedAgent, affectorAgent, agentState, blow);
			if (affectedAgent == null)
			{
				return;
			}
			NewAgentsDefend.Remove(affectedAgent);
			NewAgentsAttack.Remove(affectedAgent);
			if (!_agentParty.TryGetValue(affectedAgent, out PartyBase value))
			{
				return;
			}
			_agentParty.Remove(affectedAgent);
			if (!_partyLiveAgentCount.TryGetValue(value, out var value2))
			{
				return;
			}
			value2--;
			if (value2 <= 0)
			{
				_partyLiveAgentCount.Remove(value);
				BattleSideEnum? val = null;
				try
				{
					MapEventSide mapEventSide = value.MapEventSide;
					if (mapEventSide != null)
					{
						val = mapEventSide.MissionSide;
					}
				}
				catch
				{
				}
				if (val.HasValue)
				{
					if ((int)val.Value == 0)
					{
						_activeDefenderJoiners = Math.Max(0, _activeDefenderJoiners - 1);
					}
					else
					{
						_activeAttackerJoiners = Math.Max(0, _activeAttackerJoiners - 1);
					}
				}
				DefaultInterpolatedStringHandler defaultInterpolatedStringHandler = new DefaultInterpolatedStringHandler(44, 4);
				defaultInterpolatedStringHandler.AppendLiteral("party eliminated: ");
				defaultInterpolatedStringHandler.AppendFormatted<TextObject>(value.Name);
				defaultInterpolatedStringHandler.AppendLiteral(" (");
				IFaction mapFaction = value.MapFaction;
				defaultInterpolatedStringHandler.AppendFormatted<TextObject>((mapFaction != null) ? mapFaction.Name : null);
				defaultInterpolatedStringHandler.AppendLiteral("); ");
				defaultInterpolatedStringHandler.AppendLiteral("defActive=");
				defaultInterpolatedStringHandler.AppendFormatted(_activeDefenderJoiners);
				defaultInterpolatedStringHandler.AppendLiteral(" attActive=");
				defaultInterpolatedStringHandler.AppendFormatted(_activeAttackerJoiners);
				CrestDiag.Log("CrestBattleConvergenceLogic", defaultInterpolatedStringHandler.ToStringAndClear());
				TryPromoteWaitingParty(val.GetValueOrDefault());
			}
			else
			{
				_partyLiveAgentCount[value] = value2;
			}
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "OnAgentRemoved", ex);
		}
	}

	private void TryPromoteWaitingParty(BattleSideEnum side)
	{
		//IL_0000: Unknown result type (might be due to invalid IL or missing references)
		//IL_008b: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			Queue<(MobileParty, short, float)> queue = (((int)side == 0) ? _waitingDefenderQueue : _waitingAttackerQueue);
			while (queue.Count > 0)
			{
				var (val, teamnumber, distAtDiscovery) = queue.Dequeue();
				if (val != null && val.MapEvent == null && val.IsActive && val.CurrentSettlement == null)
				{
					CrestDiag.Log("CrestBattleConvergenceLogic", $"promoting waiting party {val.Name} on {side} (queue remaining {queue.Count})");
					RS_Stage2_Filter(val, teamnumber, distAtDiscovery);
					break;
				}
			}
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "TryPromoteWaitingParty", ex);
		}
	}

	public override void OnEarlyAgentRemoved(Agent affectedAgent, Agent affectorAgent, AgentState agentState, KillingBlow blow)
	{
		//IL_0003: Unknown result type (might be due to invalid IL or missing references)
		//IL_0004: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			((MissionBehavior)this).OnEarlyAgentRemoved(affectedAgent, affectorAgent, agentState, blow);
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "OnEarlyAgentRemoved", ex);
		}
	}

	public override void OnAgentPanicked(Agent affectedAgent)
	{
		try
		{
			((MissionBehavior)this).OnAgentPanicked(affectedAgent);
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "OnAgentPanicked", ex);
		}
	}

	public override void OnMissionResultReady(MissionResult missionResult)
	{
		try
		{
			((MissionLogic)this).OnMissionResultReady(missionResult);
			missionend = true;
			try
			{
				if (missionResult == null || !missionResult.PlayerVictory || _playerSideRescueParties.Count <= 0)
				{
					return;
				}
				CrestBattleConvergenceDialogueBehavior crestBattleConvergenceDialogueBehavior = CrestBattleConvergenceDialogueBehavior.Get();
				if (crestBattleConvergenceDialogueBehavior == null)
				{
					return;
				}
				int num = 0;
				foreach (MobileParty playerSideRescueParty in _playerSideRescueParties)
				{
					if (playerSideRescueParty != null)
					{
						Hero leaderHero = playerSideRescueParty.LeaderHero;
						if (leaderHero != null && leaderHero.IsAlive && leaderHero != Hero.MainHero)
						{
							crestBattleConvergenceDialogueBehavior.RegisterRescuingHero(leaderHero);
							num++;
						}
					}
				}
				CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.12d-feature#128: registered {num} rescue-thanks heroes (of {_playerSideRescueParties.Count} player-side rescuers)");
			}
			catch (Exception ex)
			{
				CrestDiag.LogCaught("CrestBattleConvergenceLogic", "OnMissionResultReady.RescueDialogue", ex);
			}
		}
		catch (Exception ex2)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "OnMissionResultReady", ex2);
		}
	}

	protected override void OnEndMission()
	{
		try
		{
			base.OnEndMission();
			candidateParties.Clear();
			PlayerReinforceParties.Clear();
			_playerSideRescueParties.Clear();
			MobileParty result;
			while (Defender_Collect.TryDequeue(out result))
			{
			}
			while (Attacker_Collect.TryDequeue(out result))
			{
			}
			IAgentOriginBase result2;
			while (reserved_Defender_Queue.TryDequeue(out result2))
			{
			}
			while (reserved_Attacker_Queue.TryDequeue(out result2))
			{
			}
			NewAgentsDefend.Clear();
			NewAgentsAttack.Clear();
			_configuredFormations.Clear();
			_capGuardLogged = false;
			_partyCustomFormation.Clear();
			_formationLeaderTactics.Clear();
			_customAllyFormations.Clear();
			_allyFormationSlotCounter = 0;
			_allyPools.Clear();
			_lordPoolIndex.Clear();
			_enemyPools.Clear();
			_enemyLordPoolIndex.Clear();
			_customEnemyFormations.Clear();
			_partySpawnPositions.Clear();
			_formationSpawnPositions.Clear();
			_formationAttachedBehavior.Clear();
			_y56MovementOverride.Clear();
			_y56ArrangementOverride.Clear();
			_allySpots.Clear();
			_enemySpots.Clear();
			_lastTacticsDiagAt = -1f;
			_allDefenderFleePositions.Clear();
			_allAttackerFleePositions.Clear();
			_activeDefenderJoiners = 0;
			_activeAttackerJoiners = 0;
			_waitingDefenderQueue.Clear();
			_waitingAttackerQueue.Clear();
			_partyLiveAgentCount.Clear();
			_agentParty.Clear();
			int num = 0;
			int num2 = 0;
			try
			{
				MethodInfo removeNearbyMethod = GetRemoveNearbyMethod();
				MapEvent encounteredBattle = PlayerEncounter.EncounteredBattle;
				foreach (MobileParty item in _joinerPartiesAddedToMapEvent)
				{
					if (item == null)
					{
						continue;
					}
					bool flag = false;
					if (removeNearbyMethod != null && encounteredBattle != null)
					{
						try
						{
							MapEventSide defenderSide = encounteredBattle.DefenderSide;
							MapEventSide attackerSide = encounteredBattle.AttackerSide;
							if (defenderSide != null)
							{
								try
								{
									removeNearbyMethod.Invoke(defenderSide, new object[1] { item });
									flag = true;
								}
								catch
								{
								}
							}
							if (!flag && attackerSide != null)
							{
								try
								{
									removeNearbyMethod.Invoke(attackerSide, new object[1] { item });
									flag = true;
								}
								catch
								{
								}
							}
						}
						catch
						{
						}
					}
					if (!flag)
					{
						try
						{
							FieldInfo field = typeof(MobileParty).GetField("_mapEvent", BindingFlags.Instance | BindingFlags.NonPublic);
							if (field != null)
							{
								field.SetValue(item, null);
								flag = true;
							}
						}
						catch
						{
						}
					}
					if (flag)
					{
						num++;
					}
					else
					{
						num2++;
					}
				}
			}
			catch (Exception ex)
			{
				CrestDiag.LogCaught("CrestBattleConvergenceLogic", "OnEndMission.detachJoiners", ex);
			}
			_joinerPartiesAddedToMapEvent.Clear();
			CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.29: detached {num} joiner parties from mapEvent ({num2} failed)");
			CrestDiag.Log("CrestBattleConvergenceLogic", "Y.12d: OnEndMission cleanup done");
			try
			{
				CrestBattleEndSignal.DropSentinel(((MissionBehavior)this).Mission);
			}
			catch (Exception ex2)
			{
				CrestDiag.LogCaught("CrestBattleConvergenceLogic", "DropSentinel", ex2);
			}
		}
		catch (Exception ex3)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "OnEndMission", ex3);
		}
	}

	private void RS_Stage1_Initialize()
	{
		//IL_0254: Unknown result type (might be due to invalid IL or missing references)
		//IL_025e: Expected O, but got Unknown
		//IL_0108: Unknown result type (might be due to invalid IL or missing references)
		//IL_0110: Unknown result type (might be due to invalid IL or missing references)
		//IL_01d9: Unknown result type (might be due to invalid IL or missing references)
		//IL_012e: Unknown result type (might be due to invalid IL or missing references)
		//IL_0133: Unknown result type (might be due to invalid IL or missing references)
		//IL_0150: Unknown result type (might be due to invalid IL or missing references)
		//IL_0155: Unknown result type (might be due to invalid IL or missing references)
		//IL_01f1: Unknown result type (might be due to invalid IL or missing references)
		//IL_0163: Unknown result type (might be due to invalid IL or missing references)
		//IL_016a: Unknown result type (might be due to invalid IL or missing references)
		//IL_0178: Unknown result type (might be due to invalid IL or missing references)
		//IL_017f: Unknown result type (might be due to invalid IL or missing references)
		//IL_018d: Unknown result type (might be due to invalid IL or missing references)
		//IL_0194: Unknown result type (might be due to invalid IL or missing references)
		//IL_01a7: Unknown result type (might be due to invalid IL or missing references)
		//IL_01ac: Unknown result type (might be due to invalid IL or missing references)
		//IL_020a: Unknown result type (might be due to invalid IL or missing references)
		//IL_01cb: Unknown result type (might be due to invalid IL or missing references)
		//IL_01c7: Unknown result type (might be due to invalid IL or missing references)
		//IL_01cd: Unknown result type (might be due to invalid IL or missing references)
		//IL_03ba: Unknown result type (might be due to invalid IL or missing references)
		//IL_03bf: Unknown result type (might be due to invalid IL or missing references)
		//IL_03c8: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			Mission current = Mission.Current;
			if (current == null)
			{
				return;
			}
			Defender_Collect = new ConcurrentQueue<MobileParty>();
			Attacker_Collect = new ConcurrentQueue<MobileParty>();
			reserved_Defender_Queue = new ConcurrentQueue<IAgentOriginBase>();
			reserved_Attacker_Queue = new ConcurrentQueue<IAgentOriginBase>();
			NewAgentsDefend.Clear();
			NewAgentsAttack.Clear();
			DefenderSpawnPosition.Clear();
			AttackerSpawnPosition.Clear();
			candidateParties.Clear();
			PlayerReinforceParties.Clear();
			_allDefenderFleePositions.Clear();
			_allAttackerFleePositions.Clear();
			_partySpawnPositions.Clear();
			_formationSpawnPositions.Clear();
			_formationAttachedBehavior.Clear();
			_y56MovementOverride.Clear();
			_y56ArrangementOverride.Clear();
			_allySpots.Clear();
			_enemySpots.Clear();
			_lastTacticsDiagAt = -1f;
			CollectSpawnPositions(current, (BattleSideEnum)0, DefenderSpawnPosition);
			CollectSpawnPositions(current, (BattleSideEnum)1, AttackerSpawnPosition);
			try
			{
				Vec3 val = default(Vec3);
				Vec3 val2 = default(Vec3);
				int num = 0;
				if (DefenderSpawnPosition.Count > 0)
				{
					val = DefenderSpawnPosition[0];
					num++;
				}
				if (AttackerSpawnPosition.Count > 0)
				{
					val2 = AttackerSpawnPosition[0];
					num++;
				}
				switch (num)
				{
				case 2:
					_battleCenter = new Vec3((val.x + val2.x) * 0.5f, (val.y + val2.y) * 0.5f, (val.z + val2.z) * 0.5f, -1f);
					break;
				case 1:
					_battleCenter = ((DefenderSpawnPosition.Count > 0) ? val : val2);
					break;
				}
			}
			catch
			{
			}
			try
			{
				IList<Vec3> allyFleeZones = (((int)currentplayerside == 0) ? _allDefenderFleePositions : _allAttackerFleePositions);
				IList<Vec3> enemyFleeZones = (((int)currentplayerside == 0) ? _allAttackerFleePositions : _allDefenderFleePositions);
				(List<CrestSpot> ally, List<CrestSpot> enemy) tuple = CrestTerrainScan.ScanAndPickSpots(current, _battleCenter, allyFleeZones, enemyFleeZones);
				List<CrestSpot> item = tuple.ally;
				List<CrestSpot> item2 = tuple.enemy;
				_allySpots = item;
				_enemySpots = item2;
			}
			catch (Exception ex)
			{
				CrestDiag.LogCaught("CrestBattleConvergenceLogic", "Y.59 terrain scan", ex);
			}
			addspawntimer = new MissionTimer(3f);
			howmanydef = (short)Math.Max(1, Math.Min(50, CrestConfig.GetInt("BattleConvergenceMaxJoinersPerSide", 3)));
			howmanyatt = howmanydef;
			EnsureCustomAllyFormations(current, howmanydef);
			EnsureCustomEnemyFormations(current, howmanyatt);
			try
			{
				EnsureSpotFormations(current);
			}
			catch (Exception ex2)
			{
				CrestDiag.LogCaught("CrestBattleConvergenceLogic", "Y.60a EnsureSpotFormations", ex2);
			}
			int num2 = 0;
			int num3 = 0;
			int num4 = 0;
			try
			{
				MapEvent encounteredBattle = PlayerEncounter.EncounteredBattle;
				PartyBase val3 = ((encounteredBattle != null) ? encounteredBattle.GetLeaderParty((BattleSideEnum)1) : null);
				PartyBase val4 = ((encounteredBattle != null) ? encounteredBattle.GetLeaderParty((BattleSideEnum)0) : null);
				IFaction attackerFaction = ((val3 != null) ? val3.MapFaction : null);
				IFaction defenderFaction = ((val4 != null) ? val4.MapFaction : null);
				bool flag = !CrestConfig.IsEnabled("BattleConvergenceDisableFilters", defaultValue: false);
				float num5 = CrestConfig.GetFloat("BattleConvergenceAllyRadiusMultiplier", 3f);
				if (num5 < 1f)
				{
					num5 = 1f;
				}
				if (num5 > 10f)
				{
					num5 = 10f;
				}
				int num6 = 0;
				foreach (MobileParty item3 in (List<MobileParty>)(object)MobileParty.All)
				{
					if (item3 == null)
					{
						continue;
					}
					num2++;
					if (!RS_FindParties(item3).eligible)
					{
						continue;
					}
					short? num7 = DetermineTeamNumber(item3, attackerFaction, defenderFaction);
					if (!num7.HasValue)
					{
						num4++;
						continue;
					}
					short value = num7.Value;
					float num8;
					try
					{
						Vec2 getPosition2D = item3.GetPosition2D;
						num8 = getPosition2D.Distance(MobileParty.MainParty.GetPosition2D);
					}
					catch
					{
						num8 = -1f;
					}
					if (flag && num8 > 0f)
					{
						float num9 = (float)radioussetting * num5;
						if (num8 > num9)
						{
							num6++;
							continue;
						}
					}
					float currentTime = current.CurrentTime;
					candidateParties.Add(new RS_CandidateParty(item3, value, 0f, currentTime, num8));
					num3++;
				}
				CrestDiag.Log("CrestBattleConvergenceLogic", $"Cinema-fix-C symmetric radius: bothSidesRadius={(float)radioussetting * num5:F0} (mult x{num5:F1})  --  distance-filtered {num6}");
				int num10 = CrestConfig.GetInt("BattleConvergenceInitialDelaySec", 45);
				int num11 = CrestConfig.GetInt("BattleConvergenceCadenceSec", 5);
				if (num10 < 1)
				{
					num10 = 1;
				}
				if (num10 > 600)
				{
					num10 = 600;
				}
				if (num11 < 1)
				{
					num11 = 1;
				}
				if (num11 > 60)
				{
					num11 = 60;
				}
				candidateParties.Sort((RS_CandidateParty a, RS_CandidateParty b) => a.distAtDiscovery.CompareTo(b.distAtDiscovery));
				float currentTime2 = current.CurrentTime;
				for (int num12 = 0; num12 < candidateParties.Count; num12++)
				{
					candidateParties[num12].deadlineMissionTime = currentTime2 + (float)num10 + (float)(num12 * num11);
				}
				CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.12d-fix23 stagger: initial={num10}s cadence={num11}s -> first lord at +{num10}s, last (idx {candidateParties.Count - 1}) at +{num10 + Math.Max(0, candidateParties.Count - 1) * num11}s");
			}
			catch (Exception ex3)
			{
				CrestDiag.LogCaught("CrestBattleConvergenceLogic", "RS_Stage1_Initialize party scan", ex3);
			}
			CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.12d Stage1: defenderSpawnPositions={DefenderSpawnPosition.Count} attackerSpawnPositions={AttackerSpawnPosition.Count} partiesSeen={num2} eligibleCandidates={num3} neutralRej={num4}");
		}
		catch (Exception ex4)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "RS_Stage1_Initialize", ex4);
		}
	}

	private void CollectSpawnPositions(Mission mission, BattleSideEnum side, List<Vec3> dest)
	{
		//IL_0001: Unknown result type (might be due to invalid IL or missing references)
		//IL_0010: Unknown result type (might be due to invalid IL or missing references)
		//IL_0015: Unknown result type (might be due to invalid IL or missing references)
		//IL_004d: Unknown result type (might be due to invalid IL or missing references)
		//IL_0016: Unknown result type (might be due to invalid IL or missing references)
		//IL_007f: Unknown result type (might be due to invalid IL or missing references)
		//IL_0080: Unknown result type (might be due to invalid IL or missing references)
		//IL_0085: Unknown result type (might be due to invalid IL or missing references)
		//IL_0042: Unknown result type (might be due to invalid IL or missing references)
		//IL_0047: Unknown result type (might be due to invalid IL or missing references)
		//IL_008c: Unknown result type (might be due to invalid IL or missing references)
		//IL_0093: Unknown result type (might be due to invalid IL or missing references)
		//IL_009c: Unknown result type (might be due to invalid IL or missing references)
		//IL_00a3: Unknown result type (might be due to invalid IL or missing references)
		//IL_00c3: Unknown result type (might be due to invalid IL or missing references)
		//IL_00d0: Unknown result type (might be due to invalid IL or missing references)
		//IL_0152: Unknown result type (might be due to invalid IL or missing references)
		//IL_0126: Unknown result type (might be due to invalid IL or missing references)
		//IL_017f: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			MBReadOnlyList<FleePosition> fleePositionsForSide = mission.GetFleePositionsForSide(side);
			if (fleePositionsForSide == null)
			{
				return;
			}
			Vec2 val = Vec2.Zero;
			Vec2 val4 = default(Vec2);
			try
			{
				Team val2 = (((int)side == 0) ? mission.DefenderTeam : mission.AttackerTeam);
				if (val2 != null)
				{
					WorldPosition val3 = default(WorldPosition);
					Mission.Current.GetFormationSpawnFrame(val2, (FormationClass)0, false, out val3, out val4, true);
					val = val3.AsVec2;
				}
			}
			catch
			{
			}
			List<Vec3> list = (((int)side == 0) ? _allDefenderFleePositions : _allAttackerFleePositions);
			List<(float, Vec3)> list2 = new List<(float, Vec3)>();
			foreach (FleePosition item2 in (List<FleePosition>)(object)fleePositionsForSide)
			{
				if (item2 != null)
				{
					Vec3 closestPointToEscape;
					try
					{
						closestPointToEscape = item2.GetClosestPointToEscape(val);
					}
					catch
					{
						continue;
					}
					float num = closestPointToEscape.x - val.x;
					float num2 = closestPointToEscape.y - val.y;
					float item = (float)Math.Sqrt(num * num + num2 * num2);
					list2.Add((item, closestPointToEscape));
					list.Add(closestPointToEscape);
				}
			}
			list2.Sort(((float dist, Vec3 vec) a, (float dist, Vec3 vec) b) => a.dist.CompareTo(b.dist));
			int num3 = 3;
			for (int num4 = 0; num4 < list2.Count; num4++)
			{
				if (dest.Count >= num3)
				{
					break;
				}
				dest.Add(list2[num4].Item2);
			}
			if (dest.Count != 0)
			{
				return;
			}
			try
			{
				Team val5 = (((int)side == 0) ? mission.DefenderTeam : mission.AttackerTeam);
				if (val5 != null)
				{
					WorldPosition val6 = default(WorldPosition);
					Mission.Current.GetFormationSpawnFrame(val5, (FormationClass)0, true, out val6, out val4, true);
					dest.Add(val6.GetGroundVec3());
				}
			}
			catch
			{
			}
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "CollectSpawnPositions(" + ((object)(side)/*cast due to constrained. prefix*/).ToString() + ")", ex);
		}
	}

	private (bool eligible, float delaySec) RS_FindParties(MobileParty party)
	{
		//IL_014b: Unknown result type (might be due to invalid IL or missing references)
		//IL_0150: Unknown result type (might be due to invalid IL or missing references)
		//IL_0155: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			MobileParty mainParty = MobileParty.MainParty;
			if (mainParty == null)
			{
				return (eligible: false, delaySec: -1f);
			}
			if (party == mainParty)
			{
				return (eligible: false, delaySec: -1f);
			}
			if (party.MapEvent != null)
			{
				return (eligible: false, delaySec: -1f);
			}
			if (party.BesiegerCamp != null)
			{
				return (eligible: false, delaySec: -1f);
			}
			if (party.CurrentSettlement != null)
			{
				return (eligible: false, delaySec: -1f);
			}
			if (!party.IsActive)
			{
				return (eligible: false, delaySec: -1f);
			}
			if (!party.IsLordParty)
			{
				return (eligible: false, delaySec: -1f);
			}
			if (party.IsCustomParty)
			{
				return (eligible: false, delaySec: -1f);
			}
			if (party.IsCurrentlyUsedByAQuest)
			{
				return (eligible: false, delaySec: -1f);
			}
			bool flag = !CrestConfig.IsEnabled("BattleConvergenceDisableFilters", defaultValue: false);
			if (flag)
			{
				if (party.IsBandit)
				{
					return (eligible: false, delaySec: -1f);
				}
				IFaction mapFaction = party.MapFaction;
				if (!(mapFaction is Kingdom) && !(mapFaction is Clan))
				{
					return (eligible: false, delaySec: -1f);
				}
			}
			float num;
			try
			{
				Vec2 getPosition2D = party.GetPosition2D;
				num = getPosition2D.Distance(mainParty.GetPosition2D);
			}
			catch
			{
				return (eligible: false, delaySec: -1f);
			}
			if (flag && num > (float)radioussetting * 5f)
			{
				return (eligible: false, delaySec: -1f);
			}
			IFaction mapFaction2 = party.MapFaction;
			IFaction mapFaction3 = mainParty.MapFaction;
			if (mapFaction2 == null || mapFaction3 == null)
			{
				return (eligible: false, delaySec: -1f);
			}
			float speed = Math.Max(party.Speed, 1f);
			float bonusFactor = 1f;
			try
			{
				if (party.IsBandit)
				{
					bonusFactor = 1.1f;
				}
				else if (party.Army != null && party.Army.LeaderParty == party)
				{
					bonusFactor = 0.9f;
				}
			}
			catch
			{
			}
			float num2 = CalculateArrivalDelay(num, speed, timerset, bonusFactor);
			if (num2 <= 0f)
			{
				return (eligible: false, delaySec: -1f);
			}
			if (num2 > 180f)
			{
				num2 = 180f;
			}
			return (eligible: true, delaySec: num2);
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "RS_FindParties", ex);
			return (eligible: false, delaySec: -1f);
		}
	}

	private static MethodInfo? GetRemoveNearbyMethod()
	{
		if (_removeNearbyResolved)
		{
			return _removeNearbyToMapEventMethod;
		}
		_removeNearbyResolved = true;
		string[] array = new string[8] { "RemoveNearbyPartyToPlayerMapEvent", "RemovePartyFromBattle", "RemoveNearbyParty", "RemoveParty", "DetachPartyFromEvent", "FinishApplyingMembersChange", "MissionPartyFinishedRetreating", "OnTroopRemoved" };
		try
		{
			string[] array2 = array;
			foreach (string name in array2)
			{
				MethodInfo method = typeof(MapEventSide).GetMethod(name, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic, null, new Type[1] { typeof(MobileParty) }, null);
				if (method != null)
				{
					_removeNearbyToMapEventMethod = method;
					break;
				}
			}
		}
		catch
		{
		}
		if (_removeNearbyToMapEventMethod == null)
		{
			try
			{
				MethodInfo[] methods = typeof(MapEventSide).GetMethods(BindingFlags.DeclaredOnly | BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
				StringBuilder stringBuilder = new StringBuilder();
				stringBuilder.Append("Y.30C-C: MapEventSide instance methods taking MobileParty: ");
				MethodInfo[] array3 = methods;
				foreach (MethodInfo methodInfo in array3)
				{
					ParameterInfo[] parameters = methodInfo.GetParameters();
					if (parameters.Length == 1 && parameters[0].ParameterType == typeof(MobileParty))
					{
						stringBuilder.Append(methodInfo.Name).Append(", ");
					}
				}
				CrestDiag.Log("CrestBattleConvergenceLogic", stringBuilder.ToString());
				StringBuilder stringBuilder2 = new StringBuilder();
				stringBuilder2.Append("Y.30C-C: all MapEventSide instance methods (declared): ");
				MethodInfo[] array4 = methods;
				foreach (MethodInfo methodInfo2 in array4)
				{
					if (!methodInfo2.IsSpecialName)
					{
						stringBuilder2.Append(methodInfo2.Name).Append(", ");
						if (stringBuilder2.Length > 1500)
						{
							stringBuilder2.Append("...");
							break;
						}
					}
				}
				CrestDiag.Log("CrestBattleConvergenceLogic", stringBuilder2.ToString());
			}
			catch (Exception ex)
			{
				CrestDiag.LogCaught("CrestBattleConvergenceLogic", "GetRemoveNearbyMethod.enumerate", ex);
			}
		}
		return _removeNearbyToMapEventMethod;
	}

	private static MethodInfo? GetAddNearbyMethod()
	{
		if (_addNearbyResolved)
		{
			return _addNearbyToMapEventMethod;
		}
		_addNearbyResolved = true;
		try
		{
			_addNearbyToMapEventMethod = typeof(MapEventSide).GetMethod("AddNearbyPartyToPlayerMapEvent", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic, null, new Type[1] { typeof(MobileParty) }, null);
		}
		catch
		{
		}
		return _addNearbyToMapEventMethod;
	}

	private void RS_Stage2_Filter(MobileParty party, short teamnumber, float distAtDiscovery = -1f)
	{
		//IL_03c0: Unknown result type (might be due to invalid IL or missing references)
		//IL_03c6: Unknown result type (might be due to invalid IL or missing references)
		//IL_02d3: Unknown result type (might be due to invalid IL or missing references)
		//IL_0381: Unknown result type (might be due to invalid IL or missing references)
		//IL_005d: Unknown result type (might be due to invalid IL or missing references)
		//IL_0033: Unknown result type (might be due to invalid IL or missing references)
		//IL_0038: Unknown result type (might be due to invalid IL or missing references)
		//IL_046e: Unknown result type (might be due to invalid IL or missing references)
		//IL_04a7: Unknown result type (might be due to invalid IL or missing references)
		//IL_0068: Unknown result type (might be due to invalid IL or missing references)
		//IL_0075: Unknown result type (might be due to invalid IL or missing references)
		//IL_016d: Unknown result type (might be due to invalid IL or missing references)
		//IL_0186: Unknown result type (might be due to invalid IL or missing references)
		//IL_01c5: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			if (party == null || party.MapEvent != null || !party.IsActive || party.CurrentSettlement != null)
			{
				return;
			}
			BattleSideEnum val;
			if (teamnumber == 0)
			{
				val = currentplayerside;
				if (isplayerdefender)
				{
					PlayerReinforceParties.Add(party);
				}
				_playerSideRescueParties.Add(party);
			}
			else
			{
				val = (BattleSideEnum)(((int)currentplayerside == 0) ? 1 : 0);
			}
			try
			{
				MapEvent encounteredBattle = PlayerEncounter.EncounteredBattle;
				if (encounteredBattle != null)
				{
					MapEventSide val2 = (((int)val == 0) ? encounteredBattle.DefenderSide : encounteredBattle.AttackerSide);
					MethodInfo addNearbyMethod = GetAddNearbyMethod();
					if (val2 != null && addNearbyMethod != null)
					{
						addNearbyMethod.Invoke(val2, new object[1] { party });
						_joinerPartiesAddedToMapEvent.Add(party);
					}
				}
			}
			catch (Exception ex)
			{
				Exception ex2 = ex.InnerException ?? ex;
				CrestDiag.Log("CrestBattleConvergenceLogic", $"AddNearbyPartyToPlayerMapEvent failed for {party.Name}: {ex2.GetType().Name} {ex2.Message}  --  skipping spawn for safety");
				return;
			}
			int num = CrestConfig.GetInt("BattleConvergenceMaxActiveJoiners", 5);
			if (num < 1)
			{
				num = 1;
			}
			if (num > 50)
			{
				num = 50;
			}
			int num2 = (((int)val == 0) ? _activeDefenderJoiners : _activeAttackerJoiners);
			if (num2 >= num)
			{
				Queue<(MobileParty, short, float)> queue = (((int)val == 0) ? _waitingDefenderQueue : _waitingAttackerQueue);
				queue.Enqueue((party, teamnumber, distAtDiscovery));
				CrestDiag.Log("CrestBattleConvergenceLogic", $"  cap reached on {val} ({num2}/{num}); {party.Name} added to waiting list (size {queue.Count})");
				return;
			}
			int num3 = CrestConfig.GetInt("BattleConvergenceReservedAgentCap", 600);
			if (num3 < 100)
			{
				num3 = 100;
			}
			if (num3 > 2000)
			{
				num3 = 2000;
			}
			int num4 = reserved_Defender_Queue.Count + reserved_Attacker_Queue.Count;
			int num5 = 0;
			try
			{
				int? obj;
				if (party == null)
				{
					obj = null;
				}
				else
				{
					TroopRoster memberRoster = party.MemberRoster;
					obj = ((memberRoster != null) ? new int?(memberRoster.TotalManCount) : ((int?)null));
				}
				int? num6 = obj;
				num5 = num6.GetValueOrDefault();
			}
			catch
			{
				num5 = 100;
			}
			if (num4 + num5 > num3)
			{
				Queue<(MobileParty, short, float)> queue2 = (((int)val == 0) ? _waitingDefenderQueue : _waitingAttackerQueue);
				queue2.Enqueue((party, teamnumber, distAtDiscovery));
				CrestDiag.Log("CrestBattleConvergenceLogic", $"  reservedAgentCap look-ahead: queue={num4}+{num5}={num4 + num5} > cap={num3}; {party.Name} on {val} deferred (waitlist size {queue2.Count})");
				return;
			}
			ComputePartySpawnPosition(party, val);
			if ((int)val == 0)
			{
				Defender_Collect.Enqueue(party);
				_activeDefenderJoiners++;
			}
			else
			{
				Attacker_Collect.Enqueue(party);
				_activeAttackerJoiners++;
			}
			DefaultInterpolatedStringHandler defaultInterpolatedStringHandler = new DefaultInterpolatedStringHandler(37, 7);
			defaultInterpolatedStringHandler.AppendLiteral("queued ");
			defaultInterpolatedStringHandler.AppendFormatted<TextObject>(party.Name);
			defaultInterpolatedStringHandler.AppendLiteral(" (");
			IFaction mapFaction = party.MapFaction;
			defaultInterpolatedStringHandler.AppendFormatted<TextObject>((mapFaction != null) ? mapFaction.Name : null);
			defaultInterpolatedStringHandler.AppendLiteral(") team=");
			defaultInterpolatedStringHandler.AppendFormatted(teamnumber);
			defaultInterpolatedStringHandler.AppendLiteral(" side=");
			defaultInterpolatedStringHandler.AppendFormatted<BattleSideEnum>(val);
			defaultInterpolatedStringHandler.AppendLiteral(" ");
			defaultInterpolatedStringHandler.AppendLiteral("dist=");
			defaultInterpolatedStringHandler.AppendFormatted(distAtDiscovery, "F1");
			defaultInterpolatedStringHandler.AppendLiteral(" active=");
			defaultInterpolatedStringHandler.AppendFormatted(((int)val == 0) ? _activeDefenderJoiners : _activeAttackerJoiners);
			defaultInterpolatedStringHandler.AppendLiteral("/");
			defaultInterpolatedStringHandler.AppendFormatted(num);
			CrestDiag.Log("CrestBattleConvergenceLogic", defaultInterpolatedStringHandler.ToStringAndClear());
		}
		catch (Exception ex3)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "RS_Stage2_Filter", ex3);
		}
	}

	private void ComputePartySpawnPosition(MobileParty party, BattleSideEnum side)
	{
		//IL_0000: Unknown result type (might be due to invalid IL or missing references)
		//IL_0031: Unknown result type (might be due to invalid IL or missing references)
		//IL_0036: Unknown result type (might be due to invalid IL or missing references)
		//IL_0038: Unknown result type (might be due to invalid IL or missing references)
		//IL_003d: Unknown result type (might be due to invalid IL or missing references)
		//IL_003e: Unknown result type (might be due to invalid IL or missing references)
		//IL_0044: Unknown result type (might be due to invalid IL or missing references)
		//IL_004d: Unknown result type (might be due to invalid IL or missing references)
		//IL_0053: Unknown result type (might be due to invalid IL or missing references)
		//IL_008e: Unknown result type (might be due to invalid IL or missing references)
		//IL_0093: Unknown result type (might be due to invalid IL or missing references)
		//IL_00a8: Unknown result type (might be due to invalid IL or missing references)
		//IL_00ad: Unknown result type (might be due to invalid IL or missing references)
		//IL_00af: Unknown result type (might be due to invalid IL or missing references)
		//IL_00c4: Unknown result type (might be due to invalid IL or missing references)
		//IL_0147: Unknown result type (might be due to invalid IL or missing references)
		//IL_011b: Unknown result type (might be due to invalid IL or missing references)
		//IL_011d: Unknown result type (might be due to invalid IL or missing references)
		//IL_018f: Unknown result type (might be due to invalid IL or missing references)
		//IL_01ae: Unknown result type (might be due to invalid IL or missing references)
		//IL_01cd: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			List<Vec3> list = (((int)side == 0) ? _allDefenderFleePositions : _allAttackerFleePositions);
			if (list == null || list.Count == 0)
			{
				return;
			}
			MobileParty mainParty = MobileParty.MainParty;
			if (mainParty == null)
			{
				return;
			}
			Vec2 getPosition2D = party.GetPosition2D;
			Vec2 getPosition2D2 = mainParty.GetPosition2D;
			float num = getPosition2D.x - getPosition2D2.x;
			float num2 = getPosition2D.y - getPosition2D2.y;
			float num3 = (float)Math.Sqrt(num * num + num2 * num2);
			if (num3 < 0.001f)
			{
				return;
			}
			num /= num3;
			num2 /= num3;
			Vec3 val = list[0];
			float num4 = -2f;
			foreach (Vec3 item in list)
			{
				float num5 = item.x - _battleCenter.x;
				float num6 = item.y - _battleCenter.y;
				float num7 = (float)Math.Sqrt(num5 * num5 + num6 * num6);
				if (!(num7 < 0.001f))
				{
					num5 /= num7;
					num6 /= num7;
					float num8 = num5 * num + num6 * num2;
					if (num8 > num4)
					{
						num4 = num8;
						val = item;
					}
				}
			}
			_partySpawnPositions[party.Party] = val;
			if (debugmode)
			{
				CrestDiag.Log("CrestBattleConvergenceLogic", $"  spawnPos for {party.Name} -> ({val.x:F1},{val.y:F1},{val.z:F1}) worldDir=({num:F2},{num2:F2}) bestDot={num4:F2}");
			}
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "RS_Stage2_Filter", ex);
		}
	}

	private void RS_Stage3_Check(bool isdefender, bool firstarmy)
	{
	}

	private void RS_Register_Party(MobileParty party, BattleSideEnum side)
	{
		//IL_0008: Unknown result type (might be due to invalid IL or missing references)
		//IL_0108: Unknown result type (might be due to invalid IL or missing references)
		//IL_008a: Unknown result type (might be due to invalid IL or missing references)
		//IL_0090: Unknown result type (might be due to invalid IL or missing references)
		//IL_0094: Unknown result type (might be due to invalid IL or missing references)
		//IL_009b: Expected O, but got Unknown
		try
		{
			if (party == null)
			{
				return;
			}
			ConcurrentQueue<IAgentOriginBase> concurrentQueue = (((int)side == 0) ? reserved_Defender_Queue : reserved_Attacker_Queue);
			TroopRoster memberRoster = party.MemberRoster;
			if (memberRoster == null)
			{
				return;
			}
			int num = 0;
			for (int i = 0; i < memberRoster.Count; i++)
			{
				CharacterObject characterAtIndex = memberRoster.GetCharacterAtIndex(i);
				if (characterAtIndex == null || (((BasicCharacterObject)characterAtIndex).IsHero && characterAtIndex.HeroObject == Hero.MainHero))
				{
					continue;
				}
				int elementNumber = memberRoster.GetElementNumber(i);
				int elementWoundedNumber = memberRoster.GetElementWoundedNumber(i);
				int num2 = Math.Max(0, elementNumber - elementWoundedNumber);
				if (num2 > 0)
				{
					for (int j = 0; j < num2; j++)
					{
						PartyAgentOrigin item = new PartyAgentOrigin(party.Party, characterAtIndex, 0, default(UniqueTroopDescriptor), false, false);
						concurrentQueue.Enqueue((IAgentOriginBase)(object)item);
						num++;
					}
				}
			}
			if (debugmode || num > 0)
			{
				CrestDiag.Log("CrestBattleConvergenceLogic", $"registered {party.Name} on {side}: {num} agents queued (queue size now {concurrentQueue.Count})");
			}
			if (num <= 0)
			{
				return;
			}
			try
			{
				CrestBattleHornCue.TryPlayJoinHorn();
			}
			catch (Exception ex)
			{
				CrestDiag.LogCaught("CrestBattleConvergenceLogic", "TryPlayJoinHorn", ex);
			}
		}
		catch (Exception ex2)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "RS_Register_Party", ex2);
		}
	}

	private void RS_Stage4_Spawn(bool isdefender, bool playerteam, bool hasformation)
	{
		//IL_0343: Unknown result type (might be due to invalid IL or missing references)
		//IL_0362: Unknown result type (might be due to invalid IL or missing references)
		//IL_0381: Unknown result type (might be due to invalid IL or missing references)
		//IL_00f9: Unknown result type (might be due to invalid IL or missing references)
		//IL_0180: Unknown result type (might be due to invalid IL or missing references)
		//IL_01fc: Unknown result type (might be due to invalid IL or missing references)
		//IL_0175: Unknown result type (might be due to invalid IL or missing references)
		//IL_01f6: Unknown result type (might be due to invalid IL or missing references)
		//IL_0226: Unknown result type (might be due to invalid IL or missing references)
		//IL_0228: Unknown result type (might be due to invalid IL or missing references)
		//IL_025b: Unknown result type (might be due to invalid IL or missing references)
		//IL_025d: Unknown result type (might be due to invalid IL or missing references)
		//IL_02c9: Unknown result type (might be due to invalid IL or missing references)
		//IL_02d2: Unknown result type (might be due to invalid IL or missing references)
		//IL_02de: Unknown result type (might be due to invalid IL or missing references)
		//IL_02b3: Unknown result type (might be due to invalid IL or missing references)
		//IL_02b8: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			Mission current = Mission.Current;
			if (current == null)
			{
				return;
			}
			ConcurrentQueue<IAgentOriginBase> concurrentQueue = (isdefender ? reserved_Defender_Queue : reserved_Attacker_Queue);
			List<Vec3> list = (isdefender ? DefenderSpawnPosition : AttackerSpawnPosition);
			HashSet<Agent> hashSet = (isdefender ? NewAgentsDefend : NewAgentsAttack);
			if (concurrentQueue.IsEmpty || list.Count == 0)
			{
				return;
			}
			try
			{
				int num = ((List<Agent>)(object)current.Agents)?.Count ?? 0;
				int num2 = 2040;
				if (num + 30 >= num2)
				{
					if (!_capGuardLogged)
					{
						_capGuardLogged = true;
						CrestDiag.Log("CrestBattleConvergenceLogic", "convergence pausing -- live agents " + num + " near cap " + num2);
					}
					return;
				}
			}
			catch
			{
			}
			int num3 = 0;
			int num4 = 150;
			IAgentOriginBase result;
			while (num3 < num4 && concurrentQueue.TryDequeue(out result))
			{
				if (result == null)
				{
					continue;
				}
				BasicCharacterObject troop = result.Troop;
				int num5 = ((troop != null) ? troop.DefaultFormationGroup : 0);
				FormationClass val = (FormationClass)num5;
				Formation val2 = null;
				CrestSpot crestSpot = null;
				FormationClass val4;
				if (playerteam)
				{
					PartyAgentOrigin val3 = (PartyAgentOrigin)(object)((result is PartyAgentOrigin) ? result : null);
					if (val3 != null && val3.Party != null)
					{
						crestSpot = PickSpotForAgent(_allySpots, num5);
						if (crestSpot != null)
						{
							val2 = crestSpot.Formation;
						}
						else
						{
							int orAssignPoolIndex = GetOrAssignPoolIndex(val3.Party, isAlly: true);
							if (orAssignPoolIndex >= 0 && orAssignPoolIndex < _allyPools.Count)
							{
								val2 = GetClassFormationForTroop(_allyPools[orAssignPoolIndex], num5);
							}
						}
						val4 = (FormationClass)8;
						goto IL_01fe;
					}
				}
				if (playerteam)
				{
					val4 = (FormationClass)8;
				}
				else
				{
					PartyAgentOrigin val5 = (PartyAgentOrigin)(object)((result is PartyAgentOrigin) ? result : null);
					if (val5 != null && val5.Party != null)
					{
						crestSpot = PickSpotForAgent(_enemySpots, num5);
						if (crestSpot != null)
						{
							val2 = crestSpot.Formation;
						}
						else
						{
							int orAssignPoolIndex2 = GetOrAssignPoolIndex(val5.Party, isAlly: false);
							if (orAssignPoolIndex2 >= 0 && orAssignPoolIndex2 < _enemyPools.Count)
							{
								val2 = GetClassFormationForTroop(_enemyPools[orAssignPoolIndex2], num5);
							}
						}
						val4 = (FormationClass)10;
					}
					else
					{
						val4 = (FormationClass)10;
					}
				}
				goto IL_01fe;
				IL_01fe:
				if (crestSpot != null)
				{
					crestSpot.CurrentCount++;
				}
				Vec3 val6;
				if (val2 != null && _formationSpawnPositions.TryGetValue(val2, out var value))
				{
					val6 = value;
				}
				else
				{
					PartyAgentOrigin val7 = (PartyAgentOrigin)(object)((result is PartyAgentOrigin) ? result : null);
					if (val7 != null && val7.Party != null && _partySpawnPositions.TryGetValue(val7.Party, out var value2))
					{
						val6 = value2;
					}
					else
					{
						int num6 = (isdefender ? _defenderSpawnIdx++ : _attackerSpawnIdx++);
						if (list.Count == 0)
						{
							break;
						}
						val6 = list[(num6 % list.Count + list.Count) % list.Count];
					}
				}
				Agent val8 = null;
				try
				{
					val8 = current.SpawnTroop(result, playerteam, hasformation, true, false, num5, 0, true, true, (Vec3?)val6, (Vec2?)val6.AsVec2, (string)null, (ItemObject)null, val4, false);
					if (val8 != null && val2 != null)
					{
						try
						{
							val8.Formation = val2;
						}
						catch (Exception ex)
						{
							CrestDiag.LogCaught("CrestBattleConvergenceLogic", "Stage4.AssignCustomFormation", ex);
						}
					}
				}
				catch (Exception ex2)
				{
					Exception ex3 = ex2.InnerException ?? ex2;
					CrestDiag.Log("CrestBattleConvergenceLogic", $"SpawnTroop failed at pos=({val6.x:F1},{val6.y:F1},{val6.z:F1}): {ex3.GetType().Name} {ex3.Message}");
					continue;
				}
				if (val8 != null)
				{
					try
					{
						TryAutoDelegateAgent(current, val8);
					}
					catch (Exception ex4)
					{
						CrestDiag.LogCaught("CrestBattleConvergenceLogic", "TryAutoDelegateAgent", ex4);
					}
					hashSet.Add(val8);
					PartyAgentOrigin val9 = (PartyAgentOrigin)(object)((result is PartyAgentOrigin) ? result : null);
					if (val9 != null && val9.Party != null)
					{
						_agentParty[val8] = val9.Party;
						_partyLiveAgentCount[val9.Party] = ((!_partyLiveAgentCount.TryGetValue(val9.Party, out var value3)) ? 1 : (value3 + 1));
					}
					num3++;
				}
			}
			if (num3 > 0)
			{
				if (isdefender)
				{
					firstdefend = true;
				}
				else
				{
					firstattack = true;
				}
				if (debugmode)
				{
					CrestDiag.Log("CrestBattleConvergenceLogic", $"Stage4 spawned {num3} agents on {(isdefender ? "Defender" : "Attacker")} (queue remaining {concurrentQueue.Count})");
				}
			}
		}
		catch (Exception ex5)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "RS_Stage4_Spawn", ex5);
		}
	}

	private void TryAutoDelegateAgent(Mission mission, Agent agent)
	{
		//IL_010f: Unknown result type (might be due to invalid IL or missing references)
		//IL_011a: Unknown result type (might be due to invalid IL or missing references)
		//IL_0125: Unknown result type (might be due to invalid IL or missing references)
		//IL_0130: Unknown result type (might be due to invalid IL or missing references)
		//IL_013b: Unknown result type (might be due to invalid IL or missing references)
		if (mission == null || agent == null)
		{
			return;
		}
		try
		{
			Formation formation = agent.Formation;
			if (formation == null)
			{
				return;
			}
			if (formation.Captain == null)
			{
				try
				{
					formation.Captain = agent;
				}
				catch
				{
				}
			}
			if (!formation.IsAIControlled)
			{
				formation.SetControlledByAI(true, false);
			}
			if (_configuredFormations.Contains(formation))
			{
				return;
			}
			_configuredFormations.Add(formation);
			int value = 0;
			CrestPool crestPool = FindPoolForFormation(formation);
			if (crestPool != null)
			{
				value = crestPool.LeadTactics;
			}
			else
			{
				_formationLeaderTactics.TryGetValue(formation, out value);
			}
			int num = ((value >= 100) ? ((value < 200) ? 1 : 2) : 0);
			try
			{
				string value2 = "(none)";
				switch (num)
				{
				case 0:
					AttachAndSetWeight<BehaviorCharge>(formation, 1f);
					value2 = "Charge";
					break;
				case 1:
					AttachAndSetWeight<BehaviorAdvance>(formation, 1f);
					value2 = "Advance";
					break;
				case 2:
					AttachAndSetWeight<BehaviorFlank>(formation, 1f);
					value2 = "Flank";
					break;
				}
				_formationAttachedBehavior[formation] = value2;
			}
			catch (Exception ex)
			{
				CrestDiag.LogCaught("CrestBattleConvergenceLogic", "TryAutoDelegateAgent.AddBehaviorAndWeight", ex);
			}
			try
			{
				formation.SetFacingOrder(FacingOrder.FacingOrderLookAtEnemy);
				formation.SetFiringOrder(FiringOrder.FiringOrderFireAtWill);
				formation.SetRidingOrder(RidingOrder.RidingOrderFree);
				formation.SetArrangementOrder(ArrangementOrder.ArrangementOrderLine);
				formation.SetMovementOrder(MovementOrder.MovementOrderCharge);
			}
			catch (Exception ex2)
			{
				CrestDiag.LogCaught("CrestBattleConvergenceLogic", "TryAutoDelegateAgent.FormationOrders", ex2);
			}
			try
			{
				formation.PlayerOwner = null;
			}
			catch (Exception ex3)
			{
				CrestDiag.LogCaught("CrestBattleConvergenceLogic", "TryAutoDelegateAgent.ClearPlayerOwner", ex3);
			}
		}
		catch (Exception ex4)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "TryAutoDelegateAgent.Formation", ex4);
		}
	}

	private void EnsureCustomAllyFormations(Mission mission, int needCount)
	{
		//IL_003a: Unknown result type (might be due to invalid IL or missing references)
		//IL_0041: Expected O, but got Unknown
		//IL_0045: Unknown result type (might be due to invalid IL or missing references)
		//IL_004c: Expected O, but got Unknown
		//IL_0050: Unknown result type (might be due to invalid IL or missing references)
		//IL_0057: Expected O, but got Unknown
		if (mission == null)
		{
			return;
		}
		Team playerTeam = mission.PlayerTeam;
		if (playerTeam == null)
		{
			return;
		}
		int num = (needCount + 3 - 1) / 3;
		try
		{
			while (_allyPools.Count < num)
			{
				int count = _allyPools.Count;
				int num2 = 10 + count * 3;
				Formation val = null;
				Formation val2 = null;
				Formation val3 = null;
				try
				{
					val = new Formation(playerTeam, num2);
					val2 = new Formation(playerTeam, num2 + 1);
					val3 = new Formation(playerTeam, num2 + 2);
				}
				catch (Exception ex)
				{
					CrestDiag.LogCaught("CrestBattleConvergenceLogic", $"EnsureCustomAllyFormations.ctor(pool={count})", ex);
					break;
				}
				try
				{
					MBList<Formation> formationsIncludingEmpty = playerTeam.FormationsIncludingEmpty;
					if (formationsIncludingEmpty != null)
					{
						Formation[] array = (Formation[])(object)new Formation[3] { val, val2, val3 };
						foreach (Formation val4 in array)
						{
							if (val4 == null)
							{
								continue;
							}
							bool flag = false;
							foreach (Formation item in (List<Formation>)(object)formationsIncludingEmpty)
							{
								if (item == val4)
								{
									flag = true;
									break;
								}
							}
							if (!flag)
							{
								((List<Formation>)(object)formationsIncludingEmpty).Add(val4);
							}
						}
					}
				}
				catch (Exception ex2)
				{
					CrestDiag.LogCaught("CrestBattleConvergenceLogic", $"EnsureCustomAllyFormations.register(pool={count})", ex2);
				}
				_allyPools.Add(new CrestPool
				{
					Infantry = val,
					Archers = val2,
					Cavalry = val3
				});
				if (val != null)
				{
					_customAllyFormations.Add(val);
				}
				if (val2 != null)
				{
					_customAllyFormations.Add(val2);
				}
				if (val3 != null)
				{
					_customAllyFormations.Add(val3);
				}
				BulkAttachStandardBehaviors(val);
				BulkAttachStandardBehaviors(val2);
				BulkAttachStandardBehaviors(val3);
			}
			CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.30: ensured {_allyPools.Count} ally pools ({_allyPools.Count * 3} formations, indices 10..{10 + _allyPools.Count * 3 - 1})");
		}
		catch (Exception ex3)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "EnsureCustomAllyFormations", ex3);
		}
	}

	private void EnsureCustomEnemyFormations(Mission mission, int needCount)
	{
		//IL_00c1: Unknown result type (might be due to invalid IL or missing references)
		//IL_00c8: Expected O, but got Unknown
		//IL_00cd: Unknown result type (might be due to invalid IL or missing references)
		//IL_00d4: Expected O, but got Unknown
		//IL_00d9: Unknown result type (might be due to invalid IL or missing references)
		//IL_00e0: Expected O, but got Unknown
		//IL_0039: Unknown result type (might be due to invalid IL or missing references)
		//IL_0044: Unknown result type (might be due to invalid IL or missing references)
		if (mission == null)
		{
			return;
		}
		Team val = null;
		try
		{
			if (mission.PlayerTeam != null && mission.Teams != null)
			{
				foreach (Team item in (List<Team>)(object)mission.Teams)
				{
					if (item != null && item != mission.PlayerTeam && item.Side != mission.PlayerTeam.Side)
					{
						val = item;
						break;
					}
				}
			}
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "EnsureCustomEnemyFormations.findTeam", ex);
		}
		if (val == null)
		{
			CrestDiag.Log("CrestBattleConvergenceLogic", "Y.35: no enemy team found -- enemy pools disabled this battle");
			return;
		}
		int num = (needCount + 3 - 1) / 3;
		try
		{
			while (_enemyPools.Count < num)
			{
				int count = _enemyPools.Count;
				int num2 = 10 + count * 3;
				Formation val2 = null;
				Formation val3 = null;
				Formation val4 = null;
				try
				{
					val2 = new Formation(val, num2);
					val3 = new Formation(val, num2 + 1);
					val4 = new Formation(val, num2 + 2);
				}
				catch (Exception ex2)
				{
					CrestDiag.LogCaught("CrestBattleConvergenceLogic", $"EnsureCustomEnemyFormations.ctor(pool={count})", ex2);
					break;
				}
				try
				{
					MBList<Formation> formationsIncludingEmpty = val.FormationsIncludingEmpty;
					if (formationsIncludingEmpty != null)
					{
						Formation[] array = (Formation[])(object)new Formation[3] { val2, val3, val4 };
						foreach (Formation val5 in array)
						{
							if (val5 == null)
							{
								continue;
							}
							bool flag = false;
							foreach (Formation item2 in (List<Formation>)(object)formationsIncludingEmpty)
							{
								if (item2 == val5)
								{
									flag = true;
									break;
								}
							}
							if (!flag)
							{
								((List<Formation>)(object)formationsIncludingEmpty).Add(val5);
							}
						}
					}
				}
				catch (Exception ex3)
				{
					CrestDiag.LogCaught("CrestBattleConvergenceLogic", $"EnsureCustomEnemyFormations.register(pool={count})", ex3);
				}
				_enemyPools.Add(new CrestPool
				{
					Infantry = val2,
					Archers = val3,
					Cavalry = val4,
					IsEnemyPool = true
				});
				if (val2 != null)
				{
					_customEnemyFormations.Add(val2);
				}
				if (val3 != null)
				{
					_customEnemyFormations.Add(val3);
				}
				if (val4 != null)
				{
					_customEnemyFormations.Add(val4);
				}
				BulkAttachStandardBehaviors(val2);
				BulkAttachStandardBehaviors(val3);
				BulkAttachStandardBehaviors(val4);
			}
			CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.35: ensured {_enemyPools.Count} enemy pools ({_enemyPools.Count * 3} formations, indices {10}..{10 + _enemyPools.Count * 3 - 1})");
		}
		catch (Exception ex4)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "EnsureCustomEnemyFormations", ex4);
		}
	}

	private void EnsureSpotFormations(Mission mission)
	{
		//IL_0037: Unknown result type (might be due to invalid IL or missing references)
		//IL_003d: Unknown result type (might be due to invalid IL or missing references)
		if (mission == null)
		{
			return;
		}
		Team playerTeam = mission.PlayerTeam;
		if (playerTeam == null)
		{
			return;
		}
		Team val = null;
		try
		{
			if (mission.Teams != null)
			{
				foreach (Team item in (List<Team>)(object)mission.Teams)
				{
					if (item != null && item != playerTeam && item.Side != playerTeam.Side)
					{
						val = item;
						break;
					}
				}
			}
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "EnsureSpotFormations.findTeam", ex);
		}
		EnsureSpotFormationsForSide(_allySpots, playerTeam, "ally", 16);
		if (val != null)
		{
			EnsureSpotFormationsForSide(_enemySpots, val, "enemy", 16);
		}
		else
		{
			CrestDiag.Log("CrestBattleConvergenceLogic", "Y.60a: no enemy team -- enemy spot formations skipped");
		}
	}

	private void EnsureSpotFormationsForSide(List<CrestSpot> spots, Team team, string sideTag, int baseSlot)
	{
		//IL_00f8: Unknown result type (might be due to invalid IL or missing references)
		//IL_0151: Unknown result type (might be due to invalid IL or missing references)
		//IL_01cd: Unknown result type (might be due to invalid IL or missing references)
		//IL_01cf: Unknown result type (might be due to invalid IL or missing references)
		//IL_0044: Unknown result type (might be due to invalid IL or missing references)
		//IL_004e: Expected O, but got Unknown
		//IL_00ba: Unknown result type (might be due to invalid IL or missing references)
		//IL_00bf: Unknown result type (might be due to invalid IL or missing references)
		//IL_00d3: Unknown result type (might be due to invalid IL or missing references)
		//IL_00d5: Unknown result type (might be due to invalid IL or missing references)
		//IL_00d8: Unknown result type (might be due to invalid IL or missing references)
		//IL_00da: Unknown result type (might be due to invalid IL or missing references)
		//IL_00c3: Unknown result type (might be due to invalid IL or missing references)
		//IL_00c8: Unknown result type (might be due to invalid IL or missing references)
		//IL_00e5: Unknown result type (might be due to invalid IL or missing references)
		//IL_00cc: Unknown result type (might be due to invalid IL or missing references)
		//IL_00d1: Unknown result type (might be due to invalid IL or missing references)
		if (spots == null || spots.Count == 0)
		{
			CrestDiag.Log("CrestBattleConvergenceLogic", "Y.60a " + sideTag + ": 0 spots -- nothing to create");
			return;
		}
		for (int i = 0; i < spots.Count; i++)
		{
			CrestSpot crestSpot = spots[i];
			int num = baseSlot + i;
			try
			{
				crestSpot.FormationIndex = num;
				crestSpot.Formation = new Formation(team, num);
				MBList<Formation> formationsIncludingEmpty = team.FormationsIncludingEmpty;
				if (formationsIncludingEmpty != null)
				{
					bool flag = false;
					foreach (Formation item in (List<Formation>)(object)formationsIncludingEmpty)
					{
						if (item == crestSpot.Formation)
						{
							flag = true;
							break;
						}
					}
					if (!flag)
					{
						((List<Formation>)(object)formationsIncludingEmpty).Add(crestSpot.Formation);
					}
				}
				ArrangementOrder val = (crestSpot.IntendedArrangement = (ArrangementOrder)(crestSpot.ClassPreference switch
				{
					ClassPref.ArcherPreferred => ArrangementOrder.ArrangementOrderLoose, 
					ClassPref.CavalryPreferred => ArrangementOrder.ArrangementOrderSkein, 
					_ => ArrangementOrder.ArrangementOrderLine, 
				}));
				try
				{
					crestSpot.Formation.SetArrangementOrder(val);
				}
				catch
				{
				}
				try
				{
					crestSpot.Formation.SetFacingOrder(FacingOrder.FacingOrderLookAtEnemy);
				}
				catch
				{
				}
				BulkAttachStandardBehaviors(crestSpot.Formation);
				if (sideTag == "ally")
				{
					_customAllyFormations.Add(crestSpot.Formation);
				}
				else
				{
					_customEnemyFormations.Add(crestSpot.Formation);
				}
				_formationSpawnPositions[crestSpot.Formation] = crestSpot.Anchor;
				CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.60a spot-formation: {sideTag}.spot[{i}] {crestSpot.Role} idx={num} arr={val.OrderEnum} cap={crestSpot.Capacity}");
			}
			catch (Exception ex)
			{
				CrestDiag.LogCaught("CrestBattleConvergenceLogic", $"EnsureSpotFormations({sideTag}.{i})", ex);
			}
		}
		CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.60a {sideTag}: {spots.Count} spot formations created at slots {baseSlot}..{baseSlot + spots.Count - 1}");
	}

	private int GetOrAssignPoolIndex(PartyBase? party)
	{
		return GetOrAssignPoolIndex(party, isAlly: true);
	}

	private CrestPool? FindPoolForFormation(Formation? f)
	{
		if (f == null)
		{
			return null;
		}
		foreach (CrestPool allyPool in _allyPools)
		{
			if (allyPool != null && (allyPool.Infantry == f || allyPool.Archers == f || allyPool.Cavalry == f))
			{
				return allyPool;
			}
		}
		foreach (CrestPool enemyPool in _enemyPools)
		{
			if (enemyPool != null && (enemyPool.Infantry == f || enemyPool.Archers == f || enemyPool.Cavalry == f))
			{
				return enemyPool;
			}
		}
		return null;
	}

	private int GetOrAssignPoolIndex(PartyBase? party, bool isAlly)
	{
		if (party == null)
		{
			return -1;
		}
		List<CrestPool> list = (isAlly ? _allyPools : _enemyPools);
		Dictionary<PartyBase, int> dictionary = (isAlly ? _lordPoolIndex : _enemyLordPoolIndex);
		string value = (isAlly ? "ally" : "enemy");
		if (dictionary.TryGetValue(party, out var value2))
		{
			return value2;
		}
		for (int i = 0; i < list.Count; i++)
		{
			if (list[i].LordCount >= 3)
			{
				continue;
			}
			CrestPool crestPool = list[i];
			crestPool.LordCount++;
			dictionary[party] = i;
			int num = 0;
			try
			{
				Hero leaderHero = party.LeaderHero;
				if (leaderHero != null && leaderHero.IsAlive)
				{
					try
					{
						num = leaderHero.GetSkillValue(DefaultSkills.Tactics);
					}
					catch
					{
						num = 0;
					}
				}
			}
			catch
			{
				num = 0;
			}
			bool flag = crestPool.LordCount == 1;
			bool flag2 = num > crestPool.LeadTactics;
			if (flag || flag2)
			{
				crestPool.LeadTactics = num;
				crestPool.LeadParty = party;
				if (crestPool.SpawnTime < 0f)
				{
					Mission current = Mission.Current;
					crestPool.SpawnTime = ((current != null) ? current.CurrentTime : 0f);
				}
				ApplyPoolTierOrders(crestPool);
				if (flag)
				{
					ComputePoolFormationAnchors(crestPool, party);
				}
				CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.30: {value} pool[{i}] lead={party.Name} tactics={num} ({(flag ? "first" : "escalated")}); LordCount={crestPool.LordCount}");
			}
			else
			{
				CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.30: {value} pool[{i}] joined by {party.Name} (tactics={num}); pool lead unchanged ({crestPool.LeadTactics})");
			}
			return i;
		}
		return -1;
	}

	private void ComputePoolFormationAnchors(CrestPool pool, PartyBase party)
	{
		//IL_0047: Unknown result type (might be due to invalid IL or missing references)
		//IL_005a: Unknown result type (might be due to invalid IL or missing references)
		//IL_0036: Unknown result type (might be due to invalid IL or missing references)
		//IL_003b: Unknown result type (might be due to invalid IL or missing references)
		//IL_009e: Unknown result type (might be due to invalid IL or missing references)
		//IL_009f: Unknown result type (might be due to invalid IL or missing references)
		//IL_00a3: Unknown result type (might be due to invalid IL or missing references)
		//IL_00b2: Unknown result type (might be due to invalid IL or missing references)
		//IL_00c1: Unknown result type (might be due to invalid IL or missing references)
		//IL_00d3: Unknown result type (might be due to invalid IL or missing references)
		//IL_00e2: Unknown result type (might be due to invalid IL or missing references)
		//IL_00f1: Unknown result type (might be due to invalid IL or missing references)
		//IL_0115: Unknown result type (might be due to invalid IL or missing references)
		//IL_0130: Unknown result type (might be due to invalid IL or missing references)
		//IL_016f: Unknown result type (might be due to invalid IL or missing references)
		//IL_018e: Unknown result type (might be due to invalid IL or missing references)
		//IL_01b9: Unknown result type (might be due to invalid IL or missing references)
		//IL_01d8: Unknown result type (might be due to invalid IL or missing references)
		//IL_0203: Unknown result type (might be due to invalid IL or missing references)
		//IL_0222: Unknown result type (might be due to invalid IL or missing references)
		//IL_014b: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			if (party != null && (pool.Infantry != null || pool.Archers != null || pool.Cavalry != null))
			{
				if (!_partySpawnPositions.TryGetValue(party, out var value))
				{
					value = _battleCenter;
				}
				float num = _battleCenter.x - value.x;
				float num2 = _battleCenter.y - value.y;
				float num3 = (float)Math.Sqrt(num * num + num2 * num2);
				if (num3 < 0.001f)
				{
					num = 0f;
					num2 = 1f;
				}
				else
				{
					num /= num3;
					num2 /= num3;
				}
				float num4 = 0f - num;
				float num5 = 0f - num2;
				float num6 = num2;
				float num7 = 0f - num;
				Vec3 val = value;
				Vec3 val2 = default(Vec3);
				val2 = new Vec3(value.x + num4 * 12f, value.y + num5 * 12f, value.z, -1f);
				Vec3 val3 = default(Vec3);
				val3 = new Vec3(value.x + num6 * 18f, value.y + num7 * 18f, value.z, -1f);
				if (pool.Infantry != null)
				{
					_formationSpawnPositions[pool.Infantry] = val;
				}
				if (pool.Archers != null)
				{
					_formationSpawnPositions[pool.Archers] = val2;
				}
				if (pool.Cavalry != null)
				{
					_formationSpawnPositions[pool.Cavalry] = val3;
				}
				CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.34: pool anchors set inf=({val.x:F1},{val.y:F1}) arch=({val2.x:F1},{val2.y:F1}) cav=({val3.x:F1},{val3.y:F1})");
			}
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "ComputePoolFormationAnchors", ex);
		}
	}

	private void TickPoolDiagnostics(Mission mission, float now)
	{
		try
		{
			(List<CrestPool>, string)[] array = new(List<CrestPool>, string)[2]
			{
				(_allyPools, "ally"),
				(_enemyPools, "enemy")
			};
			(List<CrestPool>, string)[] array2 = array;
			for (int i = 0; i < array2.Length; i++)
			{
				(List<CrestPool>, string) tuple = array2[i];
				List<CrestPool> item = tuple.Item1;
				string item2 = tuple.Item2;
				for (int j = 0; j < item.Count; j++)
				{
					CrestPool crestPool = item[j];
					if (crestPool == null)
					{
						continue;
					}
					Formation? infantry = crestPool.Infantry;
					int num = ((infantry != null) ? infantry.CountOfUnits : 0);
					Formation? archers = crestPool.Archers;
					int num2 = num + ((archers != null) ? archers.CountOfUnits : 0);
					Formation? cavalry = crestPool.Cavalry;
					int num3 = num2 + ((cavalry != null) ? cavalry.CountOfUnits : 0);
					if (num3 <= 0)
					{
						continue;
					}
					int leadTactics = crestPool.LeadTactics;
					int value = ((leadTactics >= 50) ? ((leadTactics < 100) ? 1 : ((leadTactics < 200) ? 2 : 3)) : 0);
					string value2 = (crestPool.ShieldWallActive ? "ShieldWall" : (crestPool.CircleActive ? "Circle" : "Standard"));
					PartyBase? leadParty = crestPool.LeadParty;
					string value3 = ((leadParty == null) ? null : ((object)leadParty.Name)?.ToString()) ?? "(none)";
					string text = "?";
					try
					{
						Team val = ((!(item2 == "ally")) ? crestPool.Infantry?.Team : crestPool.Infantry?.Team);
						if (val != null)
						{
							Type type = ((object)val).GetType();
							object obj = null;
							object obj2 = type.GetProperty("TeamAI")?.GetValue(val);
							if (obj2 != null)
							{
								Type type2 = obj2.GetType();
								string[] array3 = new string[4] { "CurrentTactic", "SelectedTactic", "ActiveTactic", "Tactic" };
								foreach (string name in array3)
								{
									object obj3 = type2.GetProperty(name, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)?.GetValue(obj2);
									if (obj3 != null)
									{
										obj = obj3;
										break;
									}
								}
							}
							if (obj != null)
							{
								text = obj.GetType().Name;
							}
							if (text == "?" && !_teamTacticDiscoveryLogged && obj2 != null)
							{
								_teamTacticDiscoveryLogged = true;
								try
								{
									BindingFlags bindingFlags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
									Type type3 = obj2.GetType();
									List<string> list = new List<string>();
									Type type4 = type3;
									while (type4 != null && type4 != typeof(object))
									{
										PropertyInfo[] properties = type4.GetProperties(bindingFlags | BindingFlags.DeclaredOnly);
										foreach (PropertyInfo propertyInfo in properties)
										{
											list.Add("p:" + type4.Name + "." + propertyInfo.Name + ":" + propertyInfo.PropertyType.Name);
										}
										FieldInfo[] fields = type4.GetFields(bindingFlags | BindingFlags.DeclaredOnly);
										foreach (FieldInfo fieldInfo in fields)
										{
											list.Add("f:" + type4.Name + "." + fieldInfo.Name + ":" + fieldInfo.FieldType.Name);
										}
										type4 = type4.BaseType;
									}
									string value4 = string.Join(", ", list.Take(100));
									CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.52d teamai-discovery: type={type3.FullName} hits=[{value4}]");
								}
								catch
								{
								}
							}
						}
					}
					catch
					{
					}
					CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.42 [{item2}.{j}] lead={value3} tier={value} parity={crestPool.LastParityDelta} variant={value2} units={num3} engineTactic={text}");
					LogFormationSnapshot(mission, crestPool, "inf", crestPool.Infantry, item2, j);
					LogFormationSnapshot(mission, crestPool, "arch", crestPool.Archers, item2, j);
					LogFormationSnapshot(mission, crestPool, "cav", crestPool.Cavalry, item2, j);
				}
			}
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "TickPoolDiagnostics", ex);
		}
	}

	private void TickSpotDiagnostics(Mission mission, float now)
	{
		//IL_0147: Unknown result type (might be due to invalid IL or missing references)
		//IL_014c: Unknown result type (might be due to invalid IL or missing references)
		//IL_0154: Unknown result type (might be due to invalid IL or missing references)
		//IL_0159: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			(List<CrestSpot>, string)[] array = new(List<CrestSpot>, string)[2]
			{
				(_allySpots, "ally"),
				(_enemySpots, "enemy")
			};
			(List<CrestSpot>, string)[] array2 = array;
			for (int i = 0; i < array2.Length; i++)
			{
				var (list, text) = array2[i];
				if (list == null)
				{
					continue;
				}
				for (int j = 0; j < list.Count; j++)
				{
					CrestSpot crestSpot = list[j];
					if (crestSpot?.Formation == null)
					{
						continue;
					}
					int countOfUnits = crestSpot.Formation.CountOfUnits;
					if (countOfUnits <= 0)
					{
						if (crestSpot.CurrentCount != 0)
						{
							CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.60c [{text}.spot[{j}] {crestSpot.Role}]: routed={crestSpot.CurrentCount} but units=0 (all dead/despawned)");
						}
						continue;
					}
					ApplySpotOrders(crestSpot);
					CrestPool pool = new CrestPool
					{
						Infantry = crestSpot.Formation,
						IntendedInfMovement = crestSpot.IntendedMovement,
						IntendedInfArrangement = crestSpot.IntendedArrangement,
						InfCavAdvanceApplied = crestSpot.AdvanceApplied,
						LeadTactics = crestSpot.LeadTactics,
						LeadParty = crestSpot.LeadParty,
						ShieldWallActive = crestSpot.ShieldWallActive,
						CircleActive = crestSpot.CircleActive,
						LastParityDelta = crestSpot.LastParityDelta,
						IsEnemyPool = (text == "enemy")
					};
					string value = (crestSpot.ShieldWallActive ? "ShieldWall" : (crestSpot.CircleActive ? "Circle" : "Standard"));
					PartyBase? leadParty = crestSpot.LeadParty;
					string value2 = ((leadParty == null) ? null : ((object)leadParty.Name)?.ToString()) ?? "(none)";
					CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.60c [{text}.spot[{j}] {crestSpot.Role}] cap={crestSpot.Capacity} routed={crestSpot.CurrentCount} units={countOfUnits} variant={value} lead={value2} pref={crestSpot.ClassPreference}");
					bool losToEnemy = ComputeLOSForSpot(crestSpot, mission);
					string spotRole = crestSpot.Role.ToString();
					LogFormationSnapshot(mission, pool, $"spot{j}", crestSpot.Formation, text, j, losToEnemy, spotRole);
				}
			}
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "TickSpotDiagnostics", ex);
		}
	}

	private static bool TryGetFormationCenter(Formation? f, out float x, out float y)
	{
		x = 0f;
		y = 0f;
		if (f == null)
		{
			return false;
		}
		try
		{
			try
			{
				Type type = ((object)f).GetType();
				string[] array = new string[3] { "CurrentPosition", "OrderPosition", "FormationGroupPosition" };
				foreach (string name in array)
				{
					PropertyInfo property = type.GetProperty(name, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
					if (property == null)
					{
						continue;
					}
					object value = property.GetValue(f);
					if (value == null)
					{
						continue;
					}
					Type type2 = value.GetType();
					FieldInfo fieldInfo = type2.GetField("x") ?? type2.GetField("X");
					FieldInfo fieldInfo2 = type2.GetField("y") ?? type2.GetField("Y");
					if (fieldInfo != null && fieldInfo2 != null)
					{
						x = (float)fieldInfo.GetValue(value);
						y = (float)fieldInfo2.GetValue(value);
						if (x != 0f || y != 0f)
						{
							return true;
						}
					}
					MethodInfo methodInfo = type2.GetMethod("AsVec2") ?? type2.GetProperty("AsVec2")?.GetGetMethod();
					if (!(methodInfo != null))
					{
						continue;
					}
					object obj = methodInfo.Invoke(value, null);
					if (obj == null)
					{
						continue;
					}
					Type type3 = obj.GetType();
					FieldInfo fieldInfo3 = type3.GetField("x") ?? type3.GetField("X");
					FieldInfo fieldInfo4 = type3.GetField("y") ?? type3.GetField("Y");
					if (fieldInfo3 != null && fieldInfo4 != null)
					{
						x = (float)fieldInfo3.GetValue(obj);
						y = (float)fieldInfo4.GetValue(obj);
						if (x != 0f || y != 0f)
						{
							return true;
						}
					}
				}
			}
			catch
			{
			}
			FormationQuerySystem querySystem = f.QuerySystem;
			if (querySystem == null)
			{
				return false;
			}
			Type type4 = ((object)querySystem).GetType();
			if (_qsPositionProp == null)
			{
				string[] array2 = new string[6] { "AverageAllyPosition", "AveragePosition", "MedianPosition", "GeoMedianPosition", "MedianTargetFormationPosition", "OrderPosition" };
				string[] array3 = array2;
				foreach (string name2 in array3)
				{
					PropertyInfo property2 = type4.GetProperty(name2, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
					if (!(property2 == null))
					{
						_qsPositionProp = property2;
						break;
					}
				}
				if (!_qsDiscoveryLogged)
				{
					_qsDiscoveryLogged = true;
					try
					{
						PropertyInfo[] properties = type4.GetProperties(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
						string value2 = string.Join(", ", properties.Select((PropertyInfo p) => p.Name + ":" + p.PropertyType.Name).Take(60));
						CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.42c qs-discovery: type={type4.FullName} resolvedProp={_qsPositionProp?.Name ?? "(none)"} props=[{value2}]");
					}
					catch
					{
					}
				}
			}
			if (_qsPositionProp == null)
			{
				return false;
			}
			object value3 = _qsPositionProp.GetValue(querySystem);
			if (value3 == null)
			{
				return false;
			}
			Type type5 = value3.GetType();
			(string, string)[] array4 = new(string, string)[2]
			{
				("x", "y"),
				("X", "Y")
			};
			for (int num = 0; num < array4.Length; num++)
			{
				(string, string) tuple = array4[num];
				string item = tuple.Item1;
				string item2 = tuple.Item2;
				FieldInfo field = type5.GetField(item);
				FieldInfo field2 = type5.GetField(item2);
				if (field != null && field2 != null)
				{
					x = (float)field.GetValue(value3);
					y = (float)field2.GetValue(value3);
					return true;
				}
				PropertyInfo property3 = type5.GetProperty(item);
				PropertyInfo property4 = type5.GetProperty(item2);
				if (property3 != null && property4 != null)
				{
					x = (float)property3.GetValue(value3);
					y = (float)property4.GetValue(value3);
					return true;
				}
			}
			MethodInfo method = type5.GetMethod("AsVec2");
			PropertyInfo property5 = type5.GetProperty("AsVec2");
			object obj4 = null;
			if (method != null)
			{
				obj4 = method.Invoke(value3, null);
			}
			else if (property5 != null)
			{
				obj4 = property5.GetValue(value3);
			}
			if (obj4 != null)
			{
				Type type6 = obj4.GetType();
				FieldInfo fieldInfo5 = type6.GetField("x") ?? type6.GetField("X");
				FieldInfo fieldInfo6 = type6.GetField("y") ?? type6.GetField("Y");
				if (fieldInfo5 != null && fieldInfo6 != null)
				{
					x = (float)fieldInfo5.GetValue(obj4);
					y = (float)fieldInfo6.GetValue(obj4);
					return true;
				}
			}
		}
		catch
		{
		}
		return false;
	}

	private void LogFormationSnapshot(Mission mission, CrestPool pool, string label, Formation? f, string sideTag, int poolIdx, bool losToEnemy = true, string spotRole = "")
	{
		//IL_057d: Unknown result type (might be due to invalid IL or missing references)
		//IL_0582: Unknown result type (might be due to invalid IL or missing references)
		//IL_0599: Unknown result type (might be due to invalid IL or missing references)
		//IL_059e: Unknown result type (might be due to invalid IL or missing references)
		//IL_0227: Unknown result type (might be due to invalid IL or missing references)
		//IL_022c: Unknown result type (might be due to invalid IL or missing references)
		//IL_0230: Unknown result type (might be due to invalid IL or missing references)
		//IL_0235: Unknown result type (might be due to invalid IL or missing references)
		//IL_05c4: Unknown result type (might be due to invalid IL or missing references)
		//IL_05c9: Unknown result type (might be due to invalid IL or missing references)
		//IL_05e0: Unknown result type (might be due to invalid IL or missing references)
		//IL_05e5: Unknown result type (might be due to invalid IL or missing references)
		//IL_00ac: Unknown result type (might be due to invalid IL or missing references)
		//IL_00b7: Unknown result type (might be due to invalid IL or missing references)
		//IL_0608: Unknown result type (might be due to invalid IL or missing references)
		//IL_060d: Unknown result type (might be due to invalid IL or missing references)
		//IL_0624: Unknown result type (might be due to invalid IL or missing references)
		//IL_0629: Unknown result type (might be due to invalid IL or missing references)
		//IL_0120: Unknown result type (might be due to invalid IL or missing references)
		//IL_0127: Unknown result type (might be due to invalid IL or missing references)
		//IL_117e: Unknown result type (might be due to invalid IL or missing references)
		//IL_118a: Unknown result type (might be due to invalid IL or missing references)
		//IL_119c: Unknown result type (might be due to invalid IL or missing references)
		//IL_11ae: Unknown result type (might be due to invalid IL or missing references)
		//IL_1235: Unknown result type (might be due to invalid IL or missing references)
		//IL_1247: Unknown result type (might be due to invalid IL or missing references)
		//IL_12ce: Unknown result type (might be due to invalid IL or missing references)
		//IL_12e0: Unknown result type (might be due to invalid IL or missing references)
		//IL_1367: Unknown result type (might be due to invalid IL or missing references)
		//IL_1379: Unknown result type (might be due to invalid IL or missing references)
		//IL_1400: Unknown result type (might be due to invalid IL or missing references)
		//IL_1412: Unknown result type (might be due to invalid IL or missing references)
		if (f == null)
		{
			return;
		}
		try
		{
			int countOfUnits = f.CountOfUnits;
			if (countOfUnits <= 0)
			{
				CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.42 [{sideTag}.{poolIdx}] {label}: units=0 (empty)");
				return;
			}
			float x = 0f;
			float y = 0f;
			TryGetFormationCenter(f, out x, out y);
			float num = -1f;
			if (_formationSpawnPositions.TryGetValue(f, out var value))
			{
				float num2 = x - value.x;
				float num3 = y - value.y;
				num = (float)Math.Sqrt(num2 * num2 + num3 * num3);
			}
			float num4 = -1f;
			try
			{
				Team team = f.Team;
				if (team != null && ((mission != null) ? mission.Teams : null) != null)
				{
					foreach (Team item in (List<Team>)(object)mission.Teams)
					{
						if (item == null || item.Side == team.Side)
						{
							continue;
						}
						MBList<Formation> formationsIncludingEmpty = item.FormationsIncludingEmpty;
						if (formationsIncludingEmpty == null)
						{
							continue;
						}
						foreach (Formation item2 in (List<Formation>)(object)formationsIncludingEmpty)
						{
							if (item2 == null || item2.CountOfUnits <= 0)
							{
								continue;
							}
							try
							{
								float x2 = 0f;
								float y2 = 0f;
								if (TryGetFormationCenter(item2, out x2, out y2))
								{
									float num5 = x2 - x;
									float num6 = y2 - y;
									float num7 = (float)Math.Sqrt(num5 * num5 + num6 * num6);
									if (num4 < 0f || num7 < num4)
									{
										num4 = num7;
									}
								}
							}
							catch
							{
							}
						}
					}
				}
			}
			catch
			{
			}
			string text = "n/a";
			string value2 = "n/a";
			try
			{
				Type type = ((object)f).GetType();
				PropertyInfo property = type.GetProperty("MovementOrder");
				if (property == null)
				{
					try
					{
						MovementOrder readonlyMovementOrderReference = f.GetReadonlyMovementOrderReference();
						text = ((object)readonlyMovementOrderReference.OrderType/*cast due to constrained. prefix*/).ToString();
					}
					catch
					{
					}
				}
				PropertyInfo property2 = type.GetProperty("ArrangementOrder");
				if (property != null)
				{
					object value3 = property.GetValue(f);
					if (value3 != null)
					{
						Type type2 = value3.GetType();
						object obj4 = ((object)type2.GetField("OrderType")) ?? ((object)type2.GetProperty("OrderType"));
						if (obj4 is FieldInfo fieldInfo)
						{
							text = fieldInfo.GetValue(value3)?.ToString() ?? "n/a";
						}
						else if (obj4 is PropertyInfo propertyInfo)
						{
							text = propertyInfo.GetValue(value3)?.ToString() ?? "n/a";
						}
					}
				}
				if (property2 != null)
				{
					object value4 = property2.GetValue(f);
					if (value4 != null)
					{
						Type type3 = value4.GetType();
						object obj5 = ((object)type3.GetField("OrderEnum")) ?? ((object)type3.GetProperty("OrderEnum"));
						if (obj5 is FieldInfo fieldInfo2)
						{
							value2 = fieldInfo2.GetValue(value4)?.ToString() ?? "n/a";
						}
						else if (obj5 is PropertyInfo propertyInfo2)
						{
							value2 = propertyInfo2.GetValue(value4)?.ToString() ?? "n/a";
						}
					}
				}
			}
			catch
			{
			}
			if (text == "n/a" && !_formationMoveDiscoveryLogged)
			{
				_formationMoveDiscoveryLogged = true;
				try
				{
					Type type4 = ((object)f).GetType();
					BindingFlags bindingAttr = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
					PropertyInfo[] properties = type4.GetProperties(bindingAttr);
					MethodInfo[] methods = type4.GetMethods(bindingAttr);
					List<string> list = new List<string>();
					PropertyInfo[] array = properties;
					foreach (PropertyInfo propertyInfo3 in array)
					{
						string name = propertyInfo3.Name;
						if (name.IndexOf("Move", StringComparison.OrdinalIgnoreCase) >= 0 || name.IndexOf("Order", StringComparison.OrdinalIgnoreCase) >= 0)
						{
							list.Add("p:" + name + ":" + propertyInfo3.PropertyType.Name);
						}
					}
					MethodInfo[] array2 = methods;
					foreach (MethodInfo methodInfo in array2)
					{
						string name2 = methodInfo.Name;
						if (methodInfo.GetParameters().Length == 0 && !name2.StartsWith("get_") && !name2.StartsWith("set_") && (name2.IndexOf("Move", StringComparison.OrdinalIgnoreCase) >= 0 || name2.IndexOf("Order", StringComparison.OrdinalIgnoreCase) >= 0))
						{
							list.Add("m:" + name2 + "():" + methodInfo.ReturnType.Name);
						}
					}
					string value5 = string.Join(", ", list.Take(80));
					CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.52c formation-move-discovery: type={type4.FullName} hits=[{value5}]");
				}
				catch
				{
				}
			}
			string value6 = "?";
			string value7 = "?";
			if (f == pool.Infantry)
			{
				value6 = ((object)pool.IntendedInfMovement.OrderType/*cast due to constrained. prefix*/).ToString();
				value7 = pool.IntendedInfArrangement.OrderEnum.ToString();
			}
			else if (f == pool.Archers)
			{
				value6 = ((object)pool.IntendedArchMovement.OrderType/*cast due to constrained. prefix*/).ToString();
				value7 = pool.IntendedArchArrangement.OrderEnum.ToString();
			}
			else if (f == pool.Cavalry)
			{
				value6 = ((object)pool.IntendedCavMovement.OrderType/*cast due to constrained. prefix*/).ToString();
				value7 = pool.IntendedCavArrangement.OrderEnum.ToString();
			}
			string value8 = "(unset)";
			if (_formationAttachedBehavior.TryGetValue(f, out string value9) && !string.IsNullOrEmpty(value9))
			{
				value8 = value9;
			}
			string value10 = "?";
			float num8 = -1f;
			float num9 = -1f;
			try
			{
				FormationAI aI = f.AI;
				if (aI != null)
				{
					IEnumerable enumerable = null;
					Type type5 = ((object)aI).GetType();
					FieldInfo field = type5.GetField("_behaviors", BindingFlags.Instance | BindingFlags.NonPublic);
					if (field != null)
					{
						enumerable = field.GetValue(aI) as IEnumerable;
					}
					if (enumerable == null)
					{
						PropertyInfo property3 = type5.GetProperty("Behaviors", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
						if (property3 != null)
						{
							enumerable = property3.GetValue(aI) as IEnumerable;
						}
					}
					if (enumerable != null)
					{
						StringBuilder stringBuilder = new StringBuilder();
						foreach (object item3 in enumerable)
						{
							if (item3 == null)
							{
								continue;
							}
							Type type6 = item3.GetType();
							float num10 = -1f;
							float num11 = -1f;
							string name3 = type6.Name;
							if (!_behaviorDiscoveryLogged)
							{
								_behaviorDiscoveryLogged = true;
								try
								{
									BindingFlags bindingFlags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
									List<string> list2 = new List<string>();
									Type type7 = type6;
									while (type7 != null && type7 != typeof(object))
									{
										PropertyInfo[] properties2 = type7.GetProperties(bindingFlags | BindingFlags.DeclaredOnly);
										foreach (PropertyInfo propertyInfo4 in properties2)
										{
											string name4 = propertyInfo4.Name;
											if (name4.IndexOf("Weight", StringComparison.OrdinalIgnoreCase) >= 0 || name4.IndexOf("Calc", StringComparison.OrdinalIgnoreCase) >= 0 || name4.IndexOf("Order", StringComparison.OrdinalIgnoreCase) >= 0 || name4.IndexOf("Aware", StringComparison.OrdinalIgnoreCase) >= 0 || name4.IndexOf("Active", StringComparison.OrdinalIgnoreCase) >= 0)
											{
												list2.Add("p:" + type7.Name + "." + name4 + ":" + propertyInfo4.PropertyType.Name);
											}
										}
										FieldInfo[] fields = type7.GetFields(bindingFlags | BindingFlags.DeclaredOnly);
										foreach (FieldInfo fieldInfo3 in fields)
										{
											string name5 = fieldInfo3.Name;
											if (name5.IndexOf("weight", StringComparison.OrdinalIgnoreCase) >= 0 || name5.IndexOf("calc", StringComparison.OrdinalIgnoreCase) >= 0)
											{
												list2.Add("f:" + type7.Name + "." + name5 + ":" + fieldInfo3.FieldType.Name);
											}
										}
										MethodInfo[] methods2 = type7.GetMethods(bindingFlags | BindingFlags.DeclaredOnly);
										foreach (MethodInfo methodInfo2 in methods2)
										{
											string name6 = methodInfo2.Name;
											if (!name6.StartsWith("get_") && !name6.StartsWith("set_") && methodInfo2.GetParameters().Length == 0 && (name6.IndexOf("Weight", StringComparison.OrdinalIgnoreCase) >= 0 || name6.IndexOf("Calc", StringComparison.OrdinalIgnoreCase) >= 0 || name6.IndexOf("Get", StringComparison.OrdinalIgnoreCase) >= 0))
											{
												list2.Add("m:" + type7.Name + "." + name6 + "():" + methodInfo2.ReturnType.Name);
											}
										}
										type7 = type7.BaseType;
									}
									string value11 = string.Join(", ", list2.Take(100));
									CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.52d behavior-discovery: type={type6.FullName} hits=[{value11}]");
								}
								catch
								{
								}
							}
							try
							{
								MethodInfo methodInfo3 = null;
								Type type8 = type6;
								while (methodInfo3 == null && type8 != null && type8 != typeof(object))
								{
									methodInfo3 = type8.GetMethod("GetAiWeight", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic, null, Type.EmptyTypes, null) ?? type8.GetMethod("GetAIWeight", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic, null, Type.EmptyTypes, null);
									type8 = type8.BaseType;
								}
								if (methodInfo3 != null && methodInfo3.Invoke(item3, null) is float num12)
								{
									num10 = num12;
								}
							}
							catch
							{
							}
							try
							{
								PropertyInfo property4 = type6.GetProperty("WeightFactor", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
								Type baseType = type6.BaseType;
								while (property4 == null && baseType != null && baseType != typeof(object))
								{
									property4 = baseType.GetProperty("WeightFactor", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
									baseType = baseType.BaseType;
								}
								if (property4 != null)
								{
									num11 = (float)(property4.GetValue(item3) ?? ((object)(-1f)));
								}
							}
							catch
							{
							}
							if (name3 == "BehaviorRetreat" && num10 > num8)
							{
								num8 = num10;
							}
							else if (name3 == "BehaviorCharge" && num10 > num9)
							{
								num9 = num10;
							}
							if (stringBuilder.Length > 0)
							{
								stringBuilder.Append(',');
							}
							stringBuilder.Append(type6.Name.Replace("Behavior", ""));
							stringBuilder.Append(':');
							stringBuilder.Append(num10.ToString("F2"));
							stringBuilder.Append('x');
							stringBuilder.Append(num11.ToString("F2"));
						}
						value10 = stringBuilder.ToString();
					}
				}
			}
			catch
			{
			}
			string value12 = "null";
			try
			{
				PropertyInfo property5 = ((object)f).GetType().GetProperty("Captain");
				object obj12 = property5?.GetValue(f);
				if (obj12 == null && countOfUnits > 0)
				{
					Agent val = null;
					try
					{
						MethodInfo method = ((object)f).GetType().GetMethod("GetFirstUnit", Type.EmptyTypes);
						if (method != null)
						{
							object obj13 = method.Invoke(f, null);
							val = (Agent)((obj13 is Agent) ? obj13 : null);
						}
						if (val == null)
						{
							object obj14 = ((object)f).GetType().GetProperty("Arrangement", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)?.GetValue(f);
							if (obj14 != null)
							{
								MethodInfo method2 = obj14.GetType().GetMethod("GetAllUnits");
								if (method2 != null && method2.Invoke(obj14, null) is IEnumerable enumerable2)
								{
									foreach (object item4 in enumerable2)
									{
										Agent val2 = (Agent)((item4 is Agent) ? item4 : null);
										if (val2 != null && val2.IsActive())
										{
											val = val2;
											break;
										}
									}
								}
							}
						}
					}
					catch
					{
					}
					if (val != null && val.IsActive())
					{
						try
						{
							property5?.SetValue(f, val);
							obj12 = property5?.GetValue(f);
							CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.53 re-elect captain: [{sideTag}.{poolIdx}] {label} units={countOfUnits} -> {val.Name ?? "?"}");
						}
						catch
						{
						}
					}
				}
				if (obj12 != null)
				{
					string value13 = obj12.GetType().GetProperty("Name")?.GetValue(obj12)?.ToString() ?? "?";
					bool value14 = false;
					try
					{
						MethodInfo method3 = obj12.GetType().GetMethod("IsActive");
						if (method3 != null)
						{
							value14 = (bool)(method3.Invoke(obj12, null) ?? ((object)false));
						}
					}
					catch
					{
					}
					value12 = $"{value13}(alive={value14})";
				}
			}
			catch
			{
			}
			CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.42 [{sideTag}.{poolIdx}] {label}: units={countOfUnits} pos=({x:F1},{y:F1}) anchorD={num:F1} enemyD={num4:F1} engineMove={text} engineArr={value2} wantMove={value6} wantArr={value7} beh={value8} weights={value10} captain={value12}");
			try
			{
				bool isCav = f == pool.Cavalry;
				bool flag = f == pool.Infantry;
				bool flag2 = f == pool.Archers;
				Y54Decision y54Decision = CrestFormationRules.Evaluate(isCav, countOfUnits, num8, num, num4, text, losToEnemy, spotRole);
				if (CrestVerbose.Enabled)
				{
					CrestVerbose.LogRule(sideTag, poolIdx, label, isCav, countOfUnits, num8, num, num4, text, losToEnemy, spotRole, y54Decision.Action.ToString(), y54Decision.Reason ?? string.Empty);
				}
				if (CrestRecorder.Enabled)
				{
					float at = 0f;
					try
					{
						if (mission != null)
						{
							at = mission.CurrentTime;
						}
					}
					catch
					{
					}
					CrestRecorder.RecordTick(at, sideTag, poolIdx, label, isCav, countOfUnits, num8, num, num4, text, losToEnemy, spotRole, y54Decision.Action.ToString(), y54Decision.Reason ?? string.Empty);
				}
				bool flag3 = false;
				try
				{
					switch (y54Decision.Action)
					{
					case Y54Action.CavUnstuck:
						f.SetMovementOrder(MovementOrder.MovementOrderCharge);
						f.SetArrangementOrder(ArrangementOrder.ArrangementOrderSkein);
						_y56MovementOverride[f] = MovementOrder.MovementOrderCharge;
						_y56ArrangementOverride[f] = ArrangementOrder.ArrangementOrderSkein;
						flag3 = true;
						CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.54 override: [{sideTag}.{poolIdx}] {label} cav-unstuck: {y54Decision.Reason}");
						break;
					case Y54Action.BrokenRetreat:
						f.SetMovementOrder(MovementOrder.MovementOrderRetreat);
						_y56MovementOverride[f] = MovementOrder.MovementOrderRetreat;
						flag3 = true;
						CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.54 override: [{sideTag}.{poolIdx}] {label} broken-retreat: {y54Decision.Reason}");
						break;
					case Y54Action.WanderClamp:
						f.SetMovementOrder(MovementOrder.MovementOrderStop);
						_y56MovementOverride[f] = MovementOrder.MovementOrderStop;
						flag3 = true;
						CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.54 override: [{sideTag}.{poolIdx}] {label} wander-clamp: {y54Decision.Reason}");
						break;
					case Y54Action.HoldNoLOS:
						f.SetMovementOrder(MovementOrder.MovementOrderStop);
						_y56MovementOverride[f] = MovementOrder.MovementOrderStop;
						flag3 = true;
						CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.54 override: [{sideTag}.{poolIdx}] {label} no-los: {y54Decision.Reason}");
						break;
					case Y54Action.AmbushHold:
						f.SetMovementOrder(MovementOrder.MovementOrderStop);
						_y56MovementOverride[f] = MovementOrder.MovementOrderStop;
						flag3 = true;
						CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.54 override: [{sideTag}.{poolIdx}] {label} ambush-hold: {y54Decision.Reason}");
						break;
					}
				}
				catch
				{
				}
				if (!flag3 && (_y56MovementOverride.Remove(f) | _y56ArrangementOverride.Remove(f)))
				{
					CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.56 clear: [{sideTag}.{poolIdx}] {label} override released (anchorD={num:F1} enemyD={num4:F1} units={countOfUnits} engineMove={text})");
				}
			}
			catch
			{
			}
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "LogFormationSnapshot", ex);
		}
	}

	private int CheckPoolParity(Mission mission)
	{
		//IL_004c: Unknown result type (might be due to invalid IL or missing references)
		//IL_0052: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			if (((mission != null) ? mission.Teams : null) == null)
			{
				return 0;
			}
			int num = 0;
			int num2 = 0;
			foreach (Team item in (List<Team>)(object)mission.Teams)
			{
				if (item != null)
				{
					int num3 = ((List<Agent>)(object)item.ActiveAgents)?.Count ?? 0;
					if (item.Side == currentplayerside)
					{
						num += num3;
					}
					else
					{
						num2 += num3;
					}
				}
			}
			return num - num2;
		}
		catch
		{
			return 0;
		}
	}

	private void ApplyPoolTierOrders(CrestPool pool)
	{
		//IL_005a: Unknown result type (might be due to invalid IL or missing references)
		//IL_0066: Unknown result type (might be due to invalid IL or missing references)
		//IL_0072: Unknown result type (might be due to invalid IL or missing references)
		//IL_0117: Unknown result type (might be due to invalid IL or missing references)
		//IL_011c: Unknown result type (might be due to invalid IL or missing references)
		//IL_0122: Unknown result type (might be due to invalid IL or missing references)
		//IL_0127: Unknown result type (might be due to invalid IL or missing references)
		//IL_012d: Unknown result type (might be due to invalid IL or missing references)
		//IL_0132: Unknown result type (might be due to invalid IL or missing references)
		//IL_0138: Unknown result type (might be due to invalid IL or missing references)
		//IL_013d: Unknown result type (might be due to invalid IL or missing references)
		//IL_0143: Unknown result type (might be due to invalid IL or missing references)
		//IL_0148: Unknown result type (might be due to invalid IL or missing references)
		//IL_014e: Unknown result type (might be due to invalid IL or missing references)
		//IL_0153: Unknown result type (might be due to invalid IL or missing references)
		//IL_017f: Unknown result type (might be due to invalid IL or missing references)
		//IL_018f: Unknown result type (might be due to invalid IL or missing references)
		//IL_019f: Unknown result type (might be due to invalid IL or missing references)
		//IL_01b6: Unknown result type (might be due to invalid IL or missing references)
		//IL_01bb: Unknown result type (might be due to invalid IL or missing references)
		//IL_01c1: Unknown result type (might be due to invalid IL or missing references)
		//IL_01c6: Unknown result type (might be due to invalid IL or missing references)
		//IL_01cc: Unknown result type (might be due to invalid IL or missing references)
		//IL_01d1: Unknown result type (might be due to invalid IL or missing references)
		//IL_01d7: Unknown result type (might be due to invalid IL or missing references)
		//IL_01dc: Unknown result type (might be due to invalid IL or missing references)
		//IL_01e2: Unknown result type (might be due to invalid IL or missing references)
		//IL_01e7: Unknown result type (might be due to invalid IL or missing references)
		//IL_01ed: Unknown result type (might be due to invalid IL or missing references)
		//IL_01f2: Unknown result type (might be due to invalid IL or missing references)
		//IL_0205: Unknown result type (might be due to invalid IL or missing references)
		//IL_027e: Unknown result type (might be due to invalid IL or missing references)
		//IL_0283: Unknown result type (might be due to invalid IL or missing references)
		//IL_0289: Unknown result type (might be due to invalid IL or missing references)
		//IL_028e: Unknown result type (might be due to invalid IL or missing references)
		//IL_0294: Unknown result type (might be due to invalid IL or missing references)
		//IL_0299: Unknown result type (might be due to invalid IL or missing references)
		//IL_029f: Unknown result type (might be due to invalid IL or missing references)
		//IL_02a4: Unknown result type (might be due to invalid IL or missing references)
		//IL_02aa: Unknown result type (might be due to invalid IL or missing references)
		//IL_02af: Unknown result type (might be due to invalid IL or missing references)
		//IL_02b5: Unknown result type (might be due to invalid IL or missing references)
		//IL_02ba: Unknown result type (might be due to invalid IL or missing references)
		//IL_021d: Unknown result type (might be due to invalid IL or missing references)
		//IL_03a2: Unknown result type (might be due to invalid IL or missing references)
		//IL_03a7: Unknown result type (might be due to invalid IL or missing references)
		//IL_03ad: Unknown result type (might be due to invalid IL or missing references)
		//IL_03b2: Unknown result type (might be due to invalid IL or missing references)
		//IL_03b8: Unknown result type (might be due to invalid IL or missing references)
		//IL_03bd: Unknown result type (might be due to invalid IL or missing references)
		//IL_03c3: Unknown result type (might be due to invalid IL or missing references)
		//IL_03c8: Unknown result type (might be due to invalid IL or missing references)
		//IL_03ce: Unknown result type (might be due to invalid IL or missing references)
		//IL_03d3: Unknown result type (might be due to invalid IL or missing references)
		//IL_03d9: Unknown result type (might be due to invalid IL or missing references)
		//IL_03de: Unknown result type (might be due to invalid IL or missing references)
		//IL_02cd: Unknown result type (might be due to invalid IL or missing references)
		//IL_0235: Unknown result type (might be due to invalid IL or missing references)
		//IL_03f1: Unknown result type (might be due to invalid IL or missing references)
		//IL_02e5: Unknown result type (might be due to invalid IL or missing references)
		//IL_0409: Unknown result type (might be due to invalid IL or missing references)
		//IL_02fd: Unknown result type (might be due to invalid IL or missing references)
		//IL_0421: Unknown result type (might be due to invalid IL or missing references)
		//IL_0331: Unknown result type (might be due to invalid IL or missing references)
		//IL_0336: Unknown result type (might be due to invalid IL or missing references)
		//IL_034c: Unknown result type (might be due to invalid IL or missing references)
		//IL_0452: Unknown result type (might be due to invalid IL or missing references)
		//IL_0457: Unknown result type (might be due to invalid IL or missing references)
		//IL_046d: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			int leadTactics = pool.LeadTactics;
			int num = ((leadTactics >= 50) ? ((leadTactics < 100) ? 1 : ((leadTactics < 200) ? 2 : 3)) : 0);
			Formation[] array = (Formation[])(object)new Formation[3] { pool.Infantry, pool.Archers, pool.Cavalry };
			foreach (Formation val in array)
			{
				if (val == null)
				{
					continue;
				}
				try
				{
					val.SetFacingOrder(FacingOrder.FacingOrderLookAtEnemy);
					val.SetFiringOrder(FiringOrder.FiringOrderFireAtWill);
					val.SetRidingOrder(RidingOrder.RidingOrderFree);
					if (!val.IsAIControlled)
					{
						val.SetControlledByAI(true, false);
					}
					val.PlayerOwner = null;
				}
				catch (Exception ex)
				{
					CrestDiag.LogCaught("CrestBattleConvergenceLogic", "ApplyPoolTierOrders.baseline", ex);
				}
			}
			Mission current = Mission.Current;
			int num2 = ((current != null) ? CheckPoolParity(current) : 0);
			if (pool.IsEnemyPool)
			{
				num2 = -num2;
			}
			pool.LastParityDelta = num2;
			pool.LastParityCheck = ((current != null) ? current.CurrentTime : 0f);
			pool.ShieldWallActive = false;
			pool.CircleActive = false;
			pool.ShieldWallStopAt = -1f;
			switch (num)
			{
			case 0:
				pool.IntendedInfMovement = MovementOrder.MovementOrderAdvance;
				pool.IntendedArchMovement = MovementOrder.MovementOrderAdvance;
				pool.IntendedCavMovement = MovementOrder.MovementOrderAdvance;
				pool.IntendedInfArrangement = ArrangementOrder.ArrangementOrderLine;
				pool.IntendedArchArrangement = ArrangementOrder.ArrangementOrderLine;
				pool.IntendedCavArrangement = ArrangementOrder.ArrangementOrderLine;
				AttachBehavior<BehaviorCharge>(pool.Infantry);
				AttachBehavior<BehaviorCharge>(pool.Archers);
				AttachBehavior<BehaviorCharge>(pool.Cavalry);
				SetMovement(pool.Infantry, MovementOrder.MovementOrderAdvance);
				SetMovement(pool.Archers, MovementOrder.MovementOrderAdvance);
				SetMovement(pool.Cavalry, MovementOrder.MovementOrderAdvance);
				break;
			case 1:
				pool.IntendedInfArrangement = ArrangementOrder.ArrangementOrderLine;
				pool.IntendedArchArrangement = ArrangementOrder.ArrangementOrderLoose;
				pool.IntendedCavArrangement = ArrangementOrder.ArrangementOrderSkein;
				pool.IntendedInfMovement = MovementOrder.MovementOrderAdvance;
				pool.IntendedArchMovement = MovementOrder.MovementOrderAdvance;
				pool.IntendedCavMovement = MovementOrder.MovementOrderAdvance;
				if (pool.Infantry != null)
				{
					pool.Infantry.SetArrangementOrder(ArrangementOrder.ArrangementOrderLine);
				}
				if (pool.Archers != null)
				{
					pool.Archers.SetArrangementOrder(ArrangementOrder.ArrangementOrderLoose);
				}
				if (pool.Cavalry != null)
				{
					pool.Cavalry.SetArrangementOrder(ArrangementOrder.ArrangementOrderSkein);
				}
				AttachBehavior<BehaviorAdvance>(pool.Infantry);
				AttachBehavior<BehaviorAdvance>(pool.Archers);
				AttachBehavior<BehaviorAdvance>(pool.Cavalry);
				break;
			case 2:
				if (num2 <= -100)
				{
					ApplyShieldWallVariant(pool);
					break;
				}
				pool.IntendedInfArrangement = ArrangementOrder.ArrangementOrderLine;
				pool.IntendedArchArrangement = ArrangementOrder.ArrangementOrderLine;
				pool.IntendedCavArrangement = ArrangementOrder.ArrangementOrderSkein;
				pool.IntendedInfMovement = MovementOrder.MovementOrderAdvance;
				pool.IntendedArchMovement = MovementOrder.MovementOrderAdvance;
				pool.IntendedCavMovement = MovementOrder.MovementOrderAdvance;
				if (pool.Infantry != null)
				{
					pool.Infantry.SetArrangementOrder(ArrangementOrder.ArrangementOrderLine);
				}
				if (pool.Archers != null)
				{
					pool.Archers.SetArrangementOrder(ArrangementOrder.ArrangementOrderLine);
				}
				if (pool.Cavalry != null)
				{
					pool.Cavalry.SetArrangementOrder(ArrangementOrder.ArrangementOrderSkein);
				}
				AttachBehavior<BehaviorAdvance>(pool.Infantry);
				AttachBehavior<BehaviorAdvance>(pool.Archers);
				AttachBehavior<BehaviorAdvance>(pool.Cavalry);
				if (num2 >= 50)
				{
					pool.IntendedCavMovement = MovementOrder.MovementOrderCharge;
					AttachBehavior<BehaviorCharge>(pool.Cavalry);
					SetMovement(pool.Cavalry, MovementOrder.MovementOrderCharge);
				}
				break;
			default:
				if (num2 <= -200)
				{
					ApplyCircleVariant(pool);
					break;
				}
				if (num2 <= -100)
				{
					ApplyShieldWallVariant(pool);
					AttachBehavior<BehaviorFlank>(pool.Infantry);
					AttachBehavior<BehaviorFlank>(pool.Archers);
					AttachBehavior<BehaviorFlank>(pool.Cavalry);
					break;
				}
				pool.IntendedInfArrangement = ArrangementOrder.ArrangementOrderLine;
				pool.IntendedArchArrangement = ArrangementOrder.ArrangementOrderLine;
				pool.IntendedCavArrangement = ArrangementOrder.ArrangementOrderSkein;
				pool.IntendedInfMovement = MovementOrder.MovementOrderAdvance;
				pool.IntendedArchMovement = MovementOrder.MovementOrderAdvance;
				pool.IntendedCavMovement = MovementOrder.MovementOrderAdvance;
				if (pool.Infantry != null)
				{
					pool.Infantry.SetArrangementOrder(ArrangementOrder.ArrangementOrderLine);
				}
				if (pool.Archers != null)
				{
					pool.Archers.SetArrangementOrder(ArrangementOrder.ArrangementOrderLine);
				}
				if (pool.Cavalry != null)
				{
					pool.Cavalry.SetArrangementOrder(ArrangementOrder.ArrangementOrderSkein);
				}
				AttachBehavior<BehaviorFlank>(pool.Infantry);
				AttachBehavior<BehaviorFlank>(pool.Archers);
				AttachBehavior<BehaviorFlank>(pool.Cavalry);
				if (num2 >= 50)
				{
					pool.IntendedCavMovement = MovementOrder.MovementOrderCharge;
					AttachBehavior<BehaviorCharge>(pool.Cavalry);
					SetMovement(pool.Cavalry, MovementOrder.MovementOrderCharge);
				}
				break;
			}
			pool.InfCavAdvanceApplied = num == 0 || pool.ShieldWallActive || pool.CircleActive;
			pool.ArchAdvanceApplied = num == 0 || pool.ShieldWallActive || pool.CircleActive;
			CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.30B: pool tier={num} delta={num2} variant={(pool.CircleActive ? "Circle" : (pool.ShieldWallActive ? "ShieldWall" : "Standard"))}");
		}
		catch (Exception ex2)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "ApplyPoolTierOrders", ex2);
		}
	}

	private void ApplySpotOrders(CrestSpot spot)
	{
		//IL_0255: Unknown result type (might be due to invalid IL or missing references)
		//IL_0324: Unknown result type (might be due to invalid IL or missing references)
		//IL_0326: Unknown result type (might be due to invalid IL or missing references)
		//IL_0340: Unknown result type (might be due to invalid IL or missing references)
		//IL_012b: Unknown result type (might be due to invalid IL or missing references)
		//IL_0130: Unknown result type (might be due to invalid IL or missing references)
		//IL_0146: Unknown result type (might be due to invalid IL or missing references)
		//IL_014b: Unknown result type (might be due to invalid IL or missing references)
		//IL_0119: Unknown result type (might be due to invalid IL or missing references)
		//IL_011e: Unknown result type (might be due to invalid IL or missing references)
		//IL_0122: Unknown result type (might be due to invalid IL or missing references)
		//IL_0127: Unknown result type (might be due to invalid IL or missing references)
		//IL_013d: Unknown result type (might be due to invalid IL or missing references)
		//IL_0142: Unknown result type (might be due to invalid IL or missing references)
		//IL_0134: Unknown result type (might be due to invalid IL or missing references)
		//IL_0139: Unknown result type (might be due to invalid IL or missing references)
		//IL_014d: Unknown result type (might be due to invalid IL or missing references)
		//IL_014f: Unknown result type (might be due to invalid IL or missing references)
		//IL_0170: Unknown result type (might be due to invalid IL or missing references)
		//IL_0175: Unknown result type (might be due to invalid IL or missing references)
		//IL_0179: Unknown result type (might be due to invalid IL or missing references)
		//IL_017e: Unknown result type (might be due to invalid IL or missing references)
		//IL_0182: Unknown result type (might be due to invalid IL or missing references)
		//IL_0187: Unknown result type (might be due to invalid IL or missing references)
		//IL_0192: Unknown result type (might be due to invalid IL or missing references)
		//IL_0194: Unknown result type (might be due to invalid IL or missing references)
		//IL_018b: Unknown result type (might be due to invalid IL or missing references)
		//IL_0190: Unknown result type (might be due to invalid IL or missing references)
		//IL_0238: Unknown result type (might be due to invalid IL or missing references)
		//IL_023a: Unknown result type (might be due to invalid IL or missing references)
		//IL_0240: Unknown result type (might be due to invalid IL or missing references)
		//IL_0242: Unknown result type (might be due to invalid IL or missing references)
		//IL_01b1: Unknown result type (might be due to invalid IL or missing references)
		//IL_01b6: Unknown result type (might be due to invalid IL or missing references)
		//IL_01b8: Unknown result type (might be due to invalid IL or missing references)
		//IL_01bd: Unknown result type (might be due to invalid IL or missing references)
		//IL_0248: Unknown result type (might be due to invalid IL or missing references)
		//IL_0068: Unknown result type (might be due to invalid IL or missing references)
		//IL_0073: Unknown result type (might be due to invalid IL or missing references)
		//IL_007e: Unknown result type (might be due to invalid IL or missing references)
		//IL_01d8: Unknown result type (might be due to invalid IL or missing references)
		//IL_01dd: Unknown result type (might be due to invalid IL or missing references)
		//IL_01df: Unknown result type (might be due to invalid IL or missing references)
		//IL_01e4: Unknown result type (might be due to invalid IL or missing references)
		//IL_0216: Unknown result type (might be due to invalid IL or missing references)
		//IL_021b: Unknown result type (might be due to invalid IL or missing references)
		if (spot == null || spot.Formation == null || spot.CurrentCount <= 0)
		{
			return;
		}
		try
		{
			int num = ((spot.LeadTactics > 0) ? spot.LeadTactics : 150);
			int num2 = ((num >= 50) ? ((num < 100) ? 1 : ((num < 200) ? 2 : 3)) : 0);
			Formation formation = spot.Formation;
			string value = (spot.IsEnemySpot ? "enemy" : "ally");
			try
			{
				formation.SetFacingOrder(FacingOrder.FacingOrderLookAtEnemy);
				formation.SetFiringOrder(FiringOrder.FiringOrderFireAtWill);
				formation.SetRidingOrder(RidingOrder.RidingOrderFree);
				if (!formation.IsAIControlled)
				{
					formation.SetControlledByAI(true, false);
				}
				formation.PlayerOwner = null;
			}
			catch (Exception ex)
			{
				CrestDiag.LogCaught("CrestBattleConvergenceLogic", "ApplySpotOrders.baseline", ex);
			}
			int num3 = (spot.LastParityDelta = ComputeSpotParity(spot));
			Mission current = Mission.Current;
			spot.LastParityCheck = ((current != null) ? current.CurrentTime : 0f);
			spot.ShieldWallActive = false;
			spot.CircleActive = false;
			ArrangementOrder val = (ArrangementOrder)(spot.Role switch
			{
				SpotRole.FlankLeft => ArrangementOrder.ArrangementOrderSkein, 
				SpotRole.FlankRight => ArrangementOrder.ArrangementOrderSkein, 
				SpotRole.Overlook => ArrangementOrder.ArrangementOrderLoose, 
				SpotRole.Reserve => ArrangementOrder.ArrangementOrderLine, 
				SpotRole.Anchor => ArrangementOrder.ArrangementOrderLine, 
				_ => ArrangementOrder.ArrangementOrderLine, 
			});
			MovementOrder val2 = (MovementOrder)(spot.Role switch
			{
				SpotRole.Front => MovementOrder.MovementOrderAdvance, 
				SpotRole.FlankLeft => MovementOrder.MovementOrderAdvance, 
				SpotRole.FlankRight => MovementOrder.MovementOrderAdvance, 
				_ => MovementOrder.MovementOrderAdvance, // Y.75: was Stop -> caused Overlook/Reserve/Anchor/Ambush spots to statue forever
			});
			if (num2 == 0)
			{
				AttachBehavior<BehaviorCharge>(formation);
			}
			else if (num3 <= -200 && num2 >= 3)
			{
				val = ArrangementOrder.ArrangementOrderCircle;
				val2 = MovementOrder.MovementOrderStop;
				spot.CircleActive = true;
				AttachBehavior<BehaviorDefend>(formation);
			}
			else if (num3 <= -100 && num2 >= 2)
			{
				val = ArrangementOrder.ArrangementOrderShieldWall;
				val2 = MovementOrder.MovementOrderStop;
				spot.ShieldWallActive = true;
				AttachBehavior<BehaviorAdvance>(formation);
			}
			else if ((spot.Role == SpotRole.FlankLeft || spot.Role == SpotRole.FlankRight) && num3 >= 50)
			{
				val2 = MovementOrder.MovementOrderCharge;
				AttachBehavior<BehaviorCharge>(formation);
			}
			else if (num2 >= 3)
			{
				AttachBehavior<BehaviorFlank>(formation);
			}
			else
			{
				AttachBehavior<BehaviorAdvance>(formation);
			}
			spot.IntendedArrangement = val;
			spot.IntendedMovement = val2;
			try
			{
				formation.SetArrangementOrder(val);
			}
			catch
			{
			}
			SetMovement(formation, val2);
			spot.AdvanceApplied = true;
			CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.60d spot-orders [{value}.{spot.Role}] tier={num2} delta={num3} variant={(spot.CircleActive ? "Circle" : (spot.ShieldWallActive ? "ShieldWall" : "Standard"))} arr={val.OrderEnum} mv={val2.OrderType}");
		}
		catch (Exception ex2)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "ApplySpotOrders", ex2);
		}
	}

	private int ComputeSpotParity(CrestSpot spot)
	{
		if (spot?.Formation == null)
		{
			return 0;
		}
		int countOfUnits = spot.Formation.CountOfUnits;
		List<CrestSpot> list = (spot.IsEnemySpot ? _allySpots : _enemySpots);
		if (list == null || list.Count == 0)
		{
			return countOfUnits;
		}
		int num = 0;
		float num2 = float.MaxValue;
		foreach (CrestSpot item in list)
		{
			if (item?.Formation == null)
			{
				continue;
			}
			int countOfUnits2 = item.Formation.CountOfUnits;
			if (countOfUnits2 > 0)
			{
				float num3 = item.Anchor.x - spot.Anchor.x;
				float num4 = item.Anchor.y - spot.Anchor.y;
				float num5 = num3 * num3 + num4 * num4;
				if (num5 < num2)
				{
					num2 = num5;
					num = countOfUnits2;
				}
			}
		}
		return countOfUnits - num;
	}

	private bool ComputeLOSForSpot(CrestSpot spot, Mission mission)
	{
		if (spot?.Formation == null || (NativeObject)(object)((mission != null) ? mission.Scene : null) == (NativeObject)null)
		{
			return true;
		}
		try
		{
			List<CrestSpot> list = (spot.IsEnemySpot ? _allySpots : _enemySpots);
			if (list == null || list.Count == 0)
			{
				return true;
			}
			CrestSpot crestSpot = null;
			float num = float.MaxValue;
			foreach (CrestSpot item in list)
			{
				if (item?.Formation != null && item.Formation.CountOfUnits > 0)
				{
					float num2 = item.Anchor.x - spot.Anchor.x;
					float num3 = item.Anchor.y - spot.Anchor.y;
					float num4 = num2 * num2 + num3 * num3;
					if (num4 < num)
					{
						num = num4;
						crestSpot = item;
					}
				}
			}
			if (crestSpot == null)
			{
				return true;
			}
			Type type = ((object)mission.Scene).GetType();
			if (!_losDiscoveryLogged)
			{
				_losDiscoveryLogged = true;
				try
				{
					List<string> list2 = new List<string>();
					MethodInfo[] methods = type.GetMethods();
					foreach (MethodInfo methodInfo in methods)
					{
						string name = methodInfo.Name;
						if (name.IndexOf("Ray", StringComparison.OrdinalIgnoreCase) >= 0 || name.IndexOf("LineCheck", StringComparison.OrdinalIgnoreCase) >= 0 || name.IndexOf("CheckLine", StringComparison.OrdinalIgnoreCase) >= 0)
						{
							list2.Add(name + "(" + methodInfo.GetParameters().Length + ")");
						}
					}
					CrestDiag.Log("CrestBattleConvergenceLogic", $"Y.66 los-discovery: type={type.FullName} methods=[{string.Join(", ", list2)}]");
				}
				catch
				{
				}
			}
			return true;
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "ComputeLOSForSpot", ex);
			return true;
		}
	}

	private void ApplyShieldWallVariant(CrestPool pool)
	{
		//IL_0001: Unknown result type (might be due to invalid IL or missing references)
		//IL_0006: Unknown result type (might be due to invalid IL or missing references)
		//IL_000c: Unknown result type (might be due to invalid IL or missing references)
		//IL_0011: Unknown result type (might be due to invalid IL or missing references)
		//IL_0017: Unknown result type (might be due to invalid IL or missing references)
		//IL_001c: Unknown result type (might be due to invalid IL or missing references)
		//IL_0022: Unknown result type (might be due to invalid IL or missing references)
		//IL_0027: Unknown result type (might be due to invalid IL or missing references)
		//IL_002d: Unknown result type (might be due to invalid IL or missing references)
		//IL_0032: Unknown result type (might be due to invalid IL or missing references)
		//IL_0038: Unknown result type (might be due to invalid IL or missing references)
		//IL_003d: Unknown result type (might be due to invalid IL or missing references)
		//IL_0050: Unknown result type (might be due to invalid IL or missing references)
		//IL_0068: Unknown result type (might be due to invalid IL or missing references)
		//IL_00b1: Unknown result type (might be due to invalid IL or missing references)
		//IL_00c1: Unknown result type (might be due to invalid IL or missing references)
		//IL_00d1: Unknown result type (might be due to invalid IL or missing references)
		//IL_0080: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			pool.IntendedInfArrangement = ArrangementOrder.ArrangementOrderShieldWall;
			pool.IntendedCavArrangement = ArrangementOrder.ArrangementOrderShieldWall;
			pool.IntendedArchArrangement = ArrangementOrder.ArrangementOrderLine;
			pool.IntendedInfMovement = MovementOrder.MovementOrderStop;
			pool.IntendedCavMovement = MovementOrder.MovementOrderStop;
			pool.IntendedArchMovement = MovementOrder.MovementOrderStop;
			if (pool.Infantry != null)
			{
				pool.Infantry.SetArrangementOrder(ArrangementOrder.ArrangementOrderShieldWall);
			}
			if (pool.Cavalry != null)
			{
				pool.Cavalry.SetArrangementOrder(ArrangementOrder.ArrangementOrderShieldWall);
			}
			if (pool.Archers != null)
			{
				pool.Archers.SetArrangementOrder(ArrangementOrder.ArrangementOrderLine);
			}
			AttachBehavior<BehaviorAdvance>(pool.Infantry);
			AttachBehavior<BehaviorAdvance>(pool.Archers);
			AttachBehavior<BehaviorAdvance>(pool.Cavalry);
			SetMovement(pool.Infantry, MovementOrder.MovementOrderAdvance);
			SetMovement(pool.Cavalry, MovementOrder.MovementOrderAdvance);
			SetMovement(pool.Archers, MovementOrder.MovementOrderStop);
			pool.ShieldWallActive = true;
			Mission current = Mission.Current;
			pool.ShieldWallStopAt = ((current != null) ? current.CurrentTime : 0f) + 5f;
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "ApplyShieldWallVariant", ex);
		}
	}

	private void ApplyCircleVariant(CrestPool pool)
	{
		//IL_0001: Unknown result type (might be due to invalid IL or missing references)
		//IL_0006: Unknown result type (might be due to invalid IL or missing references)
		//IL_000c: Unknown result type (might be due to invalid IL or missing references)
		//IL_0011: Unknown result type (might be due to invalid IL or missing references)
		//IL_0017: Unknown result type (might be due to invalid IL or missing references)
		//IL_001c: Unknown result type (might be due to invalid IL or missing references)
		//IL_0022: Unknown result type (might be due to invalid IL or missing references)
		//IL_0027: Unknown result type (might be due to invalid IL or missing references)
		//IL_002d: Unknown result type (might be due to invalid IL or missing references)
		//IL_0032: Unknown result type (might be due to invalid IL or missing references)
		//IL_0038: Unknown result type (might be due to invalid IL or missing references)
		//IL_003d: Unknown result type (might be due to invalid IL or missing references)
		//IL_0050: Unknown result type (might be due to invalid IL or missing references)
		//IL_0068: Unknown result type (might be due to invalid IL or missing references)
		//IL_00b1: Unknown result type (might be due to invalid IL or missing references)
		//IL_00c1: Unknown result type (might be due to invalid IL or missing references)
		//IL_00d1: Unknown result type (might be due to invalid IL or missing references)
		//IL_0080: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			pool.IntendedInfArrangement = ArrangementOrder.ArrangementOrderCircle;
			pool.IntendedCavArrangement = ArrangementOrder.ArrangementOrderCircle;
			pool.IntendedArchArrangement = ArrangementOrder.ArrangementOrderCircle;
			pool.IntendedInfMovement = MovementOrder.MovementOrderStop;
			pool.IntendedCavMovement = MovementOrder.MovementOrderStop;
			pool.IntendedArchMovement = MovementOrder.MovementOrderStop;
			if (pool.Infantry != null)
			{
				pool.Infantry.SetArrangementOrder(ArrangementOrder.ArrangementOrderCircle);
			}
			if (pool.Cavalry != null)
			{
				pool.Cavalry.SetArrangementOrder(ArrangementOrder.ArrangementOrderCircle);
			}
			if (pool.Archers != null)
			{
				pool.Archers.SetArrangementOrder(ArrangementOrder.ArrangementOrderCircle);
			}
			AttachBehavior<BehaviorFlank>(pool.Infantry);
			AttachBehavior<BehaviorFlank>(pool.Archers);
			AttachBehavior<BehaviorFlank>(pool.Cavalry);
			SetMovement(pool.Infantry, MovementOrder.MovementOrderStop);
			SetMovement(pool.Cavalry, MovementOrder.MovementOrderStop);
			SetMovement(pool.Archers, MovementOrder.MovementOrderStop);
			pool.CircleActive = true;
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "ApplyCircleVariant", ex);
		}
	}

	private static void BulkAttachStandardBehaviors(Formation? f)
	{
	}

	private static void AttachBehavior<T>(Formation? f) where T : BehaviorComponent
	{
		if (f == null)
		{
			return;
		}
		try
		{
			FormationAI aI = f.AI;
			if (aI == null || aI.GetBehavior<T>() != null)
			{
				return;
			}
			ConstructorInfo constructor = typeof(T).GetConstructor(new Type[1] { typeof(Formation) });
			if (constructor != null)
			{
				object obj = constructor.Invoke(new object[1] { f });
				BehaviorComponent val = (BehaviorComponent)((obj is BehaviorComponent) ? obj : null);
				if (val != null)
				{
					aI.AddAiBehavior(val);
				}
			}
		}
		catch
		{
		}
	}

	private static void AttachAndSetWeight<T>(Formation? f, float weight = 1f) where T : BehaviorComponent
	{
		if (f == null)
		{
			return;
		}
		AttachBehavior<T>(f);
		try
		{
			FormationAI aI = f.AI;
			if (aI != null)
			{
				aI.SetBehaviorWeight<T>(weight);
			}
		}
		catch (Exception ex)
		{
			CrestDiag.LogCaught("CrestBattleConvergenceLogic", "AttachAndSetWeight<" + typeof(T).Name + ">", ex);
		}
	}

	private static void SetMovement(Formation? f, MovementOrder order)
	{
		//IL_0006: Unknown result type (might be due to invalid IL or missing references)
		if (f == null)
		{
			return;
		}
		try
		{
			f.SetMovementOrder(order);
		}
		catch
		{
		}
	}

	private void ApplyMovementOverrideOrPool(Formation f, MovementOrder poolDefault)
	{
		//IL_0019: Unknown result type (might be due to invalid IL or missing references)
		//IL_0011: Unknown result type (might be due to invalid IL or missing references)
		if (_y56MovementOverride.TryGetValue(f, out var value))
		{
			SetMovement(f, value);
		}
		else
		{
			SetMovement(f, poolDefault);
		}
	}

	private void ApplyArrangementOverrideOrPool(Formation f, ArrangementOrder poolDefault)
	{
		//IL_001a: Unknown result type (might be due to invalid IL or missing references)
		//IL_0011: Unknown result type (might be due to invalid IL or missing references)
		try
		{
			if (_y56ArrangementOverride.TryGetValue(f, out var value))
			{
				f.SetArrangementOrder(value);
			}
			else
			{
				f.SetArrangementOrder(poolDefault);
			}
		}
		catch
		{
		}
	}

	private static int ParityZone(int delta)
	{
		if (delta <= -200)
		{
			return -2;
		}
		if (delta <= -100)
		{
			return -1;
		}
		if (delta >= 50)
		{
			return 1;
		}
		return 0;
	}

	private Formation? GetClassFormationForTroop(CrestPool pool, int defaultFormationGroup)
	{
		return (Formation?)(defaultFormationGroup switch
		{
			1 => pool.Archers, 
			2 => pool.Cavalry, 
			3 => pool.Cavalry, 
			_ => pool.Infantry, 
		});
	}

	private CrestSpot? PickSpotForAgent(List<CrestSpot> spots, int troopFormationGroup)
	{
		if (spots == null || spots.Count == 0)
		{
			return null;
		}
		ClassPref classPref = troopFormationGroup switch
		{
			1 => ClassPref.ArcherPreferred, 
			2 => ClassPref.CavalryPreferred, 
			3 => ClassPref.CavalryPreferred, 
			_ => ClassPref.InfantryPreferred, 
		};
		CrestSpot crestSpot = null;
		int num = -1;
		foreach (CrestSpot spot in spots)
		{
			if (spot.Formation != null && spot.CurrentCount < spot.Capacity && spot.ClassPreference == classPref)
			{
				int num2 = spot.Capacity - spot.CurrentCount;
				if (num2 > num)
				{
					crestSpot = spot;
					num = num2;
				}
			}
		}
		if (crestSpot != null)
		{
			return crestSpot;
		}
		foreach (CrestSpot spot2 in spots)
		{
			if (spot2.Formation != null && spot2.CurrentCount < spot2.Capacity && spot2.ClassPreference == ClassPref.Mixed)
			{
				int num3 = spot2.Capacity - spot2.CurrentCount;
				if (num3 > num)
				{
					crestSpot = spot2;
					num = num3;
				}
			}
		}
		if (crestSpot != null)
		{
			return crestSpot;
		}
		foreach (CrestSpot spot3 in spots)
		{
			if (spot3.Formation != null && spot3.CurrentCount < spot3.Capacity)
			{
				int num4 = spot3.Capacity - spot3.CurrentCount;
				if (num4 > num)
				{
					crestSpot = spot3;
					num = num4;
				}
			}
		}
		return crestSpot;
	}

	private Formation? GetOrAssignCustomFormation(PartyBase party)
	{
		if (party == null)
		{
			return null;
		}
		if (_partyCustomFormation.TryGetValue(party, out Formation value))
		{
			return value;
		}
		if (_customAllyFormations.Count == 0)
		{
			return null;
		}
		if (_allyFormationSlotCounter >= _customAllyFormations.Count)
		{
			return null;
		}
		Formation val = _customAllyFormations[_allyFormationSlotCounter];
		_allyFormationSlotCounter++;
		_partyCustomFormation[party] = val;
		return val;
	}

	private bool RS_Calculate_Join(bool isdefender)
	{
		return true;
	}

	private bool RS_Morale_Check(bool isdefender)
	{
		return true;
	}

	internal static float CalculateArrivalDelay(float distance, float speed, int delayModifierMs, float bonusFactor)
	{
		if (distance <= 0f)
		{
			return -1f;
		}
		float num = distance * 6f;
		float num2 = Math.Max(0.1f, (float)delayModifierMs / 1000f);
		num *= num2;
		num *= bonusFactor;
		if (num < 5f)
		{
			num = 5f;
		}
		if (num > 600f)
		{
			num = 600f;
		}
		return num;
	}
}
#endif // BANNERLORD_API_1_4_PLUS
