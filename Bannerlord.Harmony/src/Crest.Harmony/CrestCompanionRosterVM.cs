using System;
using System.Collections.Generic;

using TaleWorlds.Library;
using TaleWorlds.MountAndBlade;

namespace Bannerlord.Harmony;

/// <summary>
/// Phase Y.3 -- the portrait roster shown when the user holds Ctrl during
/// a mission. <see cref="Companions"/> is bound to a ListPanel in
/// CrestCompanionSelect.xml.
/// </summary>
internal sealed class CrestCompanionRosterVM : ViewModel
{
    private MBBindingList<CrestCompanionItemVM> _companions = new();

    [DataSourceProperty]
    public MBBindingList<CrestCompanionItemVM> Companions
    {
        get => _companions;
        set => SetField(ref _companions, value, nameof(Companions));
    }

    public void Refresh(List<Agent> agents, Agent? currentAgent, Action<Agent> swapCallback)
    {
        _companions.Clear();
        for (int i = 0; i < agents.Count; i++)
        {
            var a = agents[i];
            _companions.Add(new CrestCompanionItemVM(a, i, a == currentAgent, i == 0, swapCallback));
        }
    }
}
