using System;
using System.Collections.Generic;

using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Actions;
using TaleWorlds.CampaignSystem.CampaignBehaviors;
using TaleWorlds.CampaignSystem.Conversation;
using TaleWorlds.Core;

namespace Bannerlord.Harmony;

/// <summary>
/// Y.12d-feature#128: post-battle dialogue with lords who joined as
/// reinforcements. When a lord rides to your battle and survives the fight,
/// their hero ID is tracked here. Next time the player meets that hero in
/// conversation, a greeting line fires and they receive a small relation
/// bonus. The flag clears after the line plays so it's a one-shot per
/// rescue event.
///
/// Hooked from SubModule via campaignGameStarter.AddBehavior. Persists the
/// pending hero list via SyncData so the rescue acknowledgement survives
/// save/reload.
/// </summary>
internal class CrestBattleConvergenceDialogueBehavior : CampaignBehaviorBase
{
    private const string Source = nameof(CrestBattleConvergenceDialogueBehavior);

    // Pending heroes who rode to player's rescue and haven't been thanked yet.
    // Stored as Hero references; SyncData handles them across save/load.
    private List<Hero> _pendingRescueHeroes = new();

    public override void RegisterEvents()
    {
        // Nothing to subscribe to here -- battle-end registration happens via
        // direct call from CrestBattleConvergenceLogic.OnMissionResultReady,
        // not from a CampaignEvents subscription.
    }

    public override void SyncData(IDataStore dataStore)
    {
        try
        {
            dataStore.SyncData("_crestPendingRescueHeroes", ref _pendingRescueHeroes);
            if (_pendingRescueHeroes == null) _pendingRescueHeroes = new List<Hero>();
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "SyncData", ex);
            _pendingRescueHeroes = new List<Hero>();
        }
    }

    /// <summary>
    /// Called from CrestBattleConvergenceLogic when a battle ends with the
    /// player on the winning side. Each surviving rescuer hero is queued
    /// for the next time the player meets them.
    /// </summary>
    public void RegisterRescuingHero(Hero hero)
    {
        if (hero == null) return;
        if (!hero.IsAlive) return;
        if (hero == Hero.MainHero) return;
        if (_pendingRescueHeroes.Contains(hero)) return;
        _pendingRescueHeroes.Add(hero);
        CrestDiag.Log(Source, $"queued rescue thanks for {hero.Name}");
    }

    /// <summary>
    /// Hook the dialogue line into the campaign's conversation system.
    /// Called from SubModule.OnGameStart when the campaign starter is
    /// available. Adds a high-priority intercept on the standard
    /// "lord_introduction" / "lord_talk_speak_diplomacy_2" input state
    /// that fires only when the conversation hero is in our pending list.
    /// </summary>
    public void AddDialogs(CampaignGameStarter starter)
    {
        if (starter == null) return;

        try
        {
            // Lord-side line (the rescuer says it to the player).
            starter.AddDialogLine(
                id: "crest_rescue_thanks_line",
                inputToken: "lord_introduction",
                outputToken: "lord_talk_speak_diplomacy_2",
                text: "I am glad I could ride to your aid when you faced your foes. May our friendship deepen with every blade we cross together.",
                conditionDelegate: () => RescueDialogCondition(),
                consequenceDelegate: () => RescueDialogConsequence(),
                priority: 200);

            // Fallback for the recurring greeting state -- in case the player
            // has already met this lord and the introduction line doesn't fire.
            starter.AddDialogLine(
                id: "crest_rescue_thanks_line_recurring",
                inputToken: "lord_talk_speak_diplomacy_2",
                outputToken: "lord_pretalk",
                text: "Word reached me that you fought on alone. I rode hard to find you in time. We carry the day together.",
                conditionDelegate: () => RescueDialogCondition(),
                consequenceDelegate: () => RescueDialogConsequence(),
                priority: 200);

            CrestDiag.Log(Source, "registered rescue-thanks dialogue lines");
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "AddDialogs", ex);
        }
    }

    private bool RescueDialogCondition()
    {
        try
        {
            var other = Hero.OneToOneConversationHero;
            if (other == null) return false;
            return _pendingRescueHeroes.Contains(other);
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "RescueDialogCondition", ex);
            return false;
        }
    }

    private void RescueDialogConsequence()
    {
        try
        {
            var other = Hero.OneToOneConversationHero;
            if (other == null) return;
            _pendingRescueHeroes.Remove(other);
            // Small relation gain for showing up. +3 mirrors typical "favor returned"
            // style bumps elsewhere in vanilla.
            try
            {
                ChangeRelationAction.ApplyPlayerRelation(other, 3, affectRelatives: false, showQuickNotification: true);
            }
            catch
            {
                // ChangeRelationAction may not be available on all game versions;
                // fall back to direct setter.
                try { other.SetPersonalRelation(Hero.MainHero, other.GetRelation(Hero.MainHero) + 3); }
                catch { /* skip relation if both fail */ }
            }
            CrestDiag.Log(Source, $"thanked {other.Name} for rescue, +3 relation, list size now {_pendingRescueHeroes.Count}");
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(Source, "RescueDialogConsequence", ex);
        }
    }

    /// <summary>
    /// Singleton accessor. Returns null if no campaign is active or the
    /// behavior hasn't been added yet (e.g. during main-menu / custom battle).
    /// </summary>
    internal static CrestBattleConvergenceDialogueBehavior? Get()
    {
        try
        {
            return Campaign.Current?.GetCampaignBehavior<CrestBattleConvergenceDialogueBehavior>();
        }
        catch { return null; }
    }
}
