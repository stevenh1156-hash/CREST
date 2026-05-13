using System;
using System.Reflection;

using TaleWorlds.Core;
using TaleWorlds.Core.ViewModelCollection.ImageIdentifiers;
using TaleWorlds.Library;
using TaleWorlds.MountAndBlade;

namespace Bannerlord.Harmony;

/// <summary>
/// Phase Y.3 -- single-companion entry in the portrait roster. Bound to a
/// <c>CompanionItem</c> widget in CrestCompanionSelect.xml.
///
/// Phase Y.3-polish-2: snapshot health + ammo at construction so the prefab
/// can render two status bars below the name. Refresh-on-open is fine for
/// this v1 -- bars don't tick during the menu.
/// </summary>
internal sealed class CrestCompanionItemVM : ViewModel
{
    private readonly Agent _agent;
    private readonly Action<Agent> _swapCallback;

    private string _name = string.Empty;
    private string _keyLabel = string.Empty;
    private CharacterImageIdentifierVM? _portrait;
    private bool _isCurrentlyControlled;
    private bool _isPlayerHero;
    private bool _isDead;
    private float _healthRatio;
    private bool _hasAmmo;
    private float _ammoRatio;

    [DataSourceProperty]
    public string Name { get => _name; set => SetField(ref _name, value, nameof(Name)); }

    [DataSourceProperty]
    public string KeyLabel { get => _keyLabel; set => SetField(ref _keyLabel, value, nameof(KeyLabel)); }

    [DataSourceProperty]
    public CharacterImageIdentifierVM? Portrait { get => _portrait; set => SetField(ref _portrait, value, nameof(Portrait)); }

    [DataSourceProperty]
    public bool IsCurrentlyControlled { get => _isCurrentlyControlled; set => SetField(ref _isCurrentlyControlled, value, nameof(IsCurrentlyControlled)); }

    [DataSourceProperty]
    public bool IsPlayerHero { get => _isPlayerHero; set => SetField(ref _isPlayerHero, value, nameof(IsPlayerHero)); }

    [DataSourceProperty]
    public bool IsDead { get => _isDead; set => SetField(ref _isDead, value, nameof(IsDead)); }

    /// <summary>0..1 fraction of current health. Bound to bar fill width.</summary>
    [DataSourceProperty]
    public float HealthRatio { get => _healthRatio; set => SetField(ref _healthRatio, value, nameof(HealthRatio)); }

    /// <summary>True when the companion has any ranged weapon equipped.</summary>
    [DataSourceProperty]
    public bool HasAmmo { get => _hasAmmo; set => SetField(ref _hasAmmo, value, nameof(HasAmmo)); }

    /// <summary>0..1 fraction of remaining ammo across all ranged slots.</summary>
    [DataSourceProperty]
    public float AmmoRatio { get => _ammoRatio; set => SetField(ref _ammoRatio, value, nameof(AmmoRatio)); }

    // Gauntlet doesn't bind float→pixel directly; expose precomputed integer widths.
    // Bar reserves 70px of the 75px portrait width. Min 1px so a non-zero value is visible.
    private const int BarFullWidth = 70;
    [DataSourceProperty]
    public int HealthBarWidth => _healthRatio <= 0f ? 0 : Math.Max(1, (int)(_healthRatio * BarFullWidth));
    [DataSourceProperty]
    public int AmmoBarWidth   => _ammoRatio   <= 0f ? 0 : Math.Max(1, (int)(_ammoRatio   * BarFullWidth));

    public CrestCompanionItemVM(Agent agent, int index, bool isCurrentlyControlled, bool isPlayerHero, Action<Agent> swapCallback)
    {
        _agent = agent;
        _swapCallback = swapCallback;
        _name = agent.Name;
        _keyLabel = $"[{index + 1}]";
        _isCurrentlyControlled = isCurrentlyControlled;
        _isPlayerHero = isPlayerHero;
        _isDead = !agent.IsActive();

        if (agent.Character != null)
            _portrait = new CharacterImageIdentifierVM(CharacterCode.CreateFrom(agent.Character));

        // Health snapshot
        try
        {
            var max = agent.HealthLimit;
            _healthRatio = max > 0f ? Math.Min(1f, Math.Max(0f, agent.Health / max)) : 0f;
        }
        catch { _healthRatio = _isDead ? 0f : 1f; }

        // Ammo snapshot. Sum Amount + ModifiedMaxAmount across all weapon slots
        // that count as projectiles -- both ammo slots (arrows in quiver, bolts)
        // AND throwing-weapon slots themselves (javelins, throwing axes, etc).
        // BTH does the equivalent via GatherInformationFromWeapon's isThrown out
        // param; we use IsConsumable on the slot's CurrentUsageItem which covers
        // both cases without the awkward 5-out-param call.
        try
        {
            if (agent.IsRangedCached || agent.HasThrownCached)
            {
                int totalCur = 0, totalMax = 0;
                for (var idx = EquipmentIndex.WeaponItemBeginSlot; idx < EquipmentIndex.NumAllWeaponSlots; idx++)
                {
                    var w = agent.Equipment[idx];
                    if (w.IsEmpty) continue;

                    // Include if either the slot is ammo (arrows in a quiver),
                    // or the slot's weapon is itself consumable (throwing weapons).
                    bool include = w.IsAnyAmmo();
                    if (!include)
                    {
                        var cur = w.CurrentUsageItem;
                        if (cur != null && cur.IsConsumable) include = true;
                    }
                    if (!include) continue;
                    totalCur += w.Amount;
                    totalMax += w.ModifiedMaxAmount;
                }
                if (totalMax > 0)
                {
                    _hasAmmo = true;
                    _ammoRatio = Math.Min(1f, Math.Max(0f, (float)totalCur / totalMax));
                }
            }
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(nameof(CrestCompanionItemVM), "Ammo snapshot", ex);
            _hasAmmo = false;
            _ammoRatio = 0f;
        }
    }

    public void ExecuteSwap() => _swapCallback?.Invoke(_agent);
}
