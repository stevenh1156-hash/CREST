using TaleWorlds.Core.ViewModelCollection.ImageIdentifiers;
using TaleWorlds.Library;

namespace Bannerlord.Harmony;

/// <summary>
/// Phase Y.3 -- screen-space markers above each swappable companion.
/// 8 fixed slots; Gauntlet data binding requires real properties (not
/// indexers) so all 8 slots get a verbose triplet of Visible/PosX/PosY +
/// Current + Portrait properties. Bound to CrestCompanionMarkers.xml.
/// </summary>
internal sealed class CrestCompanionMarkersVM : ViewModel
{
    private struct Slot
    {
        public bool Visible;
        public int PosX;
        public int PosY;
        public bool Current;
        public CharacterImageIdentifierVM? Portrait;
    }

    private readonly Slot[] _slots = new Slot[8];

    [DataSourceProperty] public bool Slot0Visible { get => _slots[0].Visible; set => SetVisible(0, value); }
    [DataSourceProperty] public int Slot0PosX { get => _slots[0].PosX; set { _slots[0].PosX = value; OnPropertyChangedWithValue(value, nameof(Slot0PosX)); } }
    [DataSourceProperty] public int Slot0PosY { get => _slots[0].PosY; set { _slots[0].PosY = value; OnPropertyChangedWithValue(value, nameof(Slot0PosY)); } }
    [DataSourceProperty] public bool Slot0Current { get => _slots[0].Current; set { _slots[0].Current = value; OnPropertyChangedWithValue(value, nameof(Slot0Current)); } }
    [DataSourceProperty] public CharacterImageIdentifierVM? Slot0Portrait { get => _slots[0].Portrait; set { _slots[0].Portrait = value; OnPropertyChangedWithValue(value, nameof(Slot0Portrait)); } }

    [DataSourceProperty] public bool Slot1Visible { get => _slots[1].Visible; set => SetVisible(1, value); }
    [DataSourceProperty] public int Slot1PosX { get => _slots[1].PosX; set { _slots[1].PosX = value; OnPropertyChangedWithValue(value, nameof(Slot1PosX)); } }
    [DataSourceProperty] public int Slot1PosY { get => _slots[1].PosY; set { _slots[1].PosY = value; OnPropertyChangedWithValue(value, nameof(Slot1PosY)); } }
    [DataSourceProperty] public bool Slot1Current { get => _slots[1].Current; set { _slots[1].Current = value; OnPropertyChangedWithValue(value, nameof(Slot1Current)); } }
    [DataSourceProperty] public CharacterImageIdentifierVM? Slot1Portrait { get => _slots[1].Portrait; set { _slots[1].Portrait = value; OnPropertyChangedWithValue(value, nameof(Slot1Portrait)); } }

    [DataSourceProperty] public bool Slot2Visible { get => _slots[2].Visible; set => SetVisible(2, value); }
    [DataSourceProperty] public int Slot2PosX { get => _slots[2].PosX; set { _slots[2].PosX = value; OnPropertyChangedWithValue(value, nameof(Slot2PosX)); } }
    [DataSourceProperty] public int Slot2PosY { get => _slots[2].PosY; set { _slots[2].PosY = value; OnPropertyChangedWithValue(value, nameof(Slot2PosY)); } }
    [DataSourceProperty] public bool Slot2Current { get => _slots[2].Current; set { _slots[2].Current = value; OnPropertyChangedWithValue(value, nameof(Slot2Current)); } }
    [DataSourceProperty] public CharacterImageIdentifierVM? Slot2Portrait { get => _slots[2].Portrait; set { _slots[2].Portrait = value; OnPropertyChangedWithValue(value, nameof(Slot2Portrait)); } }

    [DataSourceProperty] public bool Slot3Visible { get => _slots[3].Visible; set => SetVisible(3, value); }
    [DataSourceProperty] public int Slot3PosX { get => _slots[3].PosX; set { _slots[3].PosX = value; OnPropertyChangedWithValue(value, nameof(Slot3PosX)); } }
    [DataSourceProperty] public int Slot3PosY { get => _slots[3].PosY; set { _slots[3].PosY = value; OnPropertyChangedWithValue(value, nameof(Slot3PosY)); } }
    [DataSourceProperty] public bool Slot3Current { get => _slots[3].Current; set { _slots[3].Current = value; OnPropertyChangedWithValue(value, nameof(Slot3Current)); } }
    [DataSourceProperty] public CharacterImageIdentifierVM? Slot3Portrait { get => _slots[3].Portrait; set { _slots[3].Portrait = value; OnPropertyChangedWithValue(value, nameof(Slot3Portrait)); } }

    [DataSourceProperty] public bool Slot4Visible { get => _slots[4].Visible; set => SetVisible(4, value); }
    [DataSourceProperty] public int Slot4PosX { get => _slots[4].PosX; set { _slots[4].PosX = value; OnPropertyChangedWithValue(value, nameof(Slot4PosX)); } }
    [DataSourceProperty] public int Slot4PosY { get => _slots[4].PosY; set { _slots[4].PosY = value; OnPropertyChangedWithValue(value, nameof(Slot4PosY)); } }
    [DataSourceProperty] public bool Slot4Current { get => _slots[4].Current; set { _slots[4].Current = value; OnPropertyChangedWithValue(value, nameof(Slot4Current)); } }
    [DataSourceProperty] public CharacterImageIdentifierVM? Slot4Portrait { get => _slots[4].Portrait; set { _slots[4].Portrait = value; OnPropertyChangedWithValue(value, nameof(Slot4Portrait)); } }

    [DataSourceProperty] public bool Slot5Visible { get => _slots[5].Visible; set => SetVisible(5, value); }
    [DataSourceProperty] public int Slot5PosX { get => _slots[5].PosX; set { _slots[5].PosX = value; OnPropertyChangedWithValue(value, nameof(Slot5PosX)); } }
    [DataSourceProperty] public int Slot5PosY { get => _slots[5].PosY; set { _slots[5].PosY = value; OnPropertyChangedWithValue(value, nameof(Slot5PosY)); } }
    [DataSourceProperty] public bool Slot5Current { get => _slots[5].Current; set { _slots[5].Current = value; OnPropertyChangedWithValue(value, nameof(Slot5Current)); } }
    [DataSourceProperty] public CharacterImageIdentifierVM? Slot5Portrait { get => _slots[5].Portrait; set { _slots[5].Portrait = value; OnPropertyChangedWithValue(value, nameof(Slot5Portrait)); } }

    [DataSourceProperty] public bool Slot6Visible { get => _slots[6].Visible; set => SetVisible(6, value); }
    [DataSourceProperty] public int Slot6PosX { get => _slots[6].PosX; set { _slots[6].PosX = value; OnPropertyChangedWithValue(value, nameof(Slot6PosX)); } }
    [DataSourceProperty] public int Slot6PosY { get => _slots[6].PosY; set { _slots[6].PosY = value; OnPropertyChangedWithValue(value, nameof(Slot6PosY)); } }
    [DataSourceProperty] public bool Slot6Current { get => _slots[6].Current; set { _slots[6].Current = value; OnPropertyChangedWithValue(value, nameof(Slot6Current)); } }
    [DataSourceProperty] public CharacterImageIdentifierVM? Slot6Portrait { get => _slots[6].Portrait; set { _slots[6].Portrait = value; OnPropertyChangedWithValue(value, nameof(Slot6Portrait)); } }

    [DataSourceProperty] public bool Slot7Visible { get => _slots[7].Visible; set => SetVisible(7, value); }
    [DataSourceProperty] public int Slot7PosX { get => _slots[7].PosX; set { _slots[7].PosX = value; OnPropertyChangedWithValue(value, nameof(Slot7PosX)); } }
    [DataSourceProperty] public int Slot7PosY { get => _slots[7].PosY; set { _slots[7].PosY = value; OnPropertyChangedWithValue(value, nameof(Slot7PosY)); } }
    [DataSourceProperty] public bool Slot7Current { get => _slots[7].Current; set { _slots[7].Current = value; OnPropertyChangedWithValue(value, nameof(Slot7Current)); } }
    [DataSourceProperty] public CharacterImageIdentifierVM? Slot7Portrait { get => _slots[7].Portrait; set { _slots[7].Portrait = value; OnPropertyChangedWithValue(value, nameof(Slot7Portrait)); } }

    public void ClearSlots()
    {
        for (int i = 0; i < _slots.Length; i++) SetVisible(i, false);
    }

    public void HideSlot(int index) => SetVisible(index, false);

    public void SetPortrait(int index, CharacterImageIdentifierVM portrait)
    {
        if (!IsValid(index)) return;
        _slots[index].Portrait = portrait;
        OnPropertyChangedWithValue(portrait, $"Slot{index}Portrait");
    }

    public void SetSlot(int index, int x, int y, bool isCurrent)
    {
        if (!IsValid(index)) return;
        _slots[index].PosX = x;
        _slots[index].PosY = y;
        _slots[index].Current = isCurrent;
        _slots[index].Visible = true;
        OnPropertyChangedWithValue(x, $"Slot{index}PosX");
        OnPropertyChangedWithValue(y, $"Slot{index}PosY");
        OnPropertyChangedWithValue(isCurrent, $"Slot{index}Current");
        OnPropertyChangedWithValue(true, $"Slot{index}Visible");
    }

    private void SetVisible(int index, bool value)
    {
        if (!IsValid(index)) return;
        _slots[index].Visible = value;
        OnPropertyChangedWithValue(value, $"Slot{index}Visible");
    }

    private static bool IsValid(int index) => index >= 0 && index < 8;
}
