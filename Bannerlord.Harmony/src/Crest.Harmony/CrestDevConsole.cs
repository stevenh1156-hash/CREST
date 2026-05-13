using HarmonyLib.BUTR.Extensions;

using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Text;

namespace Bannerlord.Harmony;

/// <summary>
/// Phase Y.6 + Y.8 + Y.9 dev console -- the modder rapid-iteration toolkit.
///
/// Registered via TaleWorlds' <c>CommandLineFunctionality.CommandLineArgumentFunction</c>
/// attribute, which is the same mechanism vanilla cheat commands use. To
/// access: enable cheats in <c>engine_config.txt</c> (or pass <c>-cheat</c>
/// on the launcher), in-game press <c>Alt + ~</c> to open the cheat console,
/// then type <c>crest.help</c> for a list of every command.
///
/// All commands are gated on cheats being enabled, so users can't trigger
/// them by accident.
///
/// Why text commands instead of a Gauntlet UI: zero UI work, fully
/// scriptable (paste a sequence of commands), discoverable via <c>crest.help</c>,
/// and the cheat console is already a familiar workflow for modders.
/// A future <c>crest-gui</c> overlay can wrap these same operations.
/// </summary>
internal static class CrestDevConsole
{
    private const string Source = nameof(CrestDevConsole);

    // Reflection cache for commonly-accessed types. Resolved lazily.
    private static Type?     _campaignType;
    private static Type?     _heroType;
    private static Type?     _mobilePartyType;
    private static Type?     _itemObjectType;
    private static Type?     _characterObjectType;
    private static Type?     _factionManagerType;
    private static Type?     _equipmentIndexType;
    private static Type?     _troopRosterType;
    private static Type?     _equipmentType;
    private static Type?     _equipmentElementType;
    private static bool      _typesResolved;

    private static void EnsureTypes()
    {
        if (_typesResolved) return;
        _typesResolved = true;
        try
        {
            _campaignType        = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.Campaign");
            _heroType            = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.Hero");
            _mobilePartyType     = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.Party.MobileParty");
            _itemObjectType      = AccessTools2.TypeByName("TaleWorlds.Core.ItemObject");
            _characterObjectType = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.CharacterObject");
            _factionManagerType  = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.FactionManager");
            _equipmentIndexType  = AccessTools2.TypeByName("TaleWorlds.Core.EquipmentIndex");
            _troopRosterType     = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.Roster.TroopRoster");
            _equipmentType       = AccessTools2.TypeByName("TaleWorlds.Core.Equipment");
            _equipmentElementType = AccessTools2.TypeByName("TaleWorlds.Core.EquipmentElement");
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "EnsureTypes", ex); }
    }

    // -------------------------------------------------------------
    // Help command -- lists every crest.* command with one-line summary.
    // -------------------------------------------------------------
    private const string HelpText =
        "CREST Dev Console -- modder rapid-iteration commands\n" +
        "                    Open with Alt + ~ when cheats are enabled.\n" +
        "\n" +
        "  GENERAL\n" +
        "    crest.help                                Show this list\n" +
        "    crest.version                             Show CREST version + bound patch count\n" +
        "    crest.config_get <key>                    Read a key from crest.json\n" +
        "    crest.config_set <key> <value>            Write a key (live; saves on next MCM tick)\n" +
        "\n" +
        "  PARTY / TROOPS\n" +
        "    crest.party_info                          Dump main party state (members, position)\n" +
        "    crest.spawn_troop <troopId> <count>       Add troops to player roster\n" +
        "    crest.spawn_party <troopId> <count>       Spawn wandering party of <count> <troopId>\n" +
        "    crest.find_troop <substring>              List troop IDs matching substring (max 30)\n" +
        "    crest.heal_party                          Heal all troops in main party to full\n" +
        "\n" +
        "  EQUIPMENT\n" +
        "    crest.equip_main <slot> <itemId>          Equip MainHero (slot: head|body|leg|gloves|cape|horse|harness|wpn0..3)\n" +
        "    crest.equip_clear <slot>                  Clear MainHero slot\n" +
        "    crest.find_item <substring>               List item IDs matching substring (max 30)\n" +
        "    crest.give_item <itemId> [count]          Add item to player's inventory (default count 1)\n" +
        "\n" +
        "  HERO / CAMPAIGN\n" +
        "    crest.hero_info                           Dump MainHero stats (skills, traits, gold)\n" +
        "    crest.gold <amount>                       Add gold to player\n" +
        "    crest.influence <amount>                  Add influence to player clan\n" +
        "    crest.relation <heroId> <delta>           Change relation between MainHero and named hero\n" +
        "    crest.faction_relations <a> <b>           Show war / peace state between two factions\n" +
        "\n" +
        "  PATCH INSPECTOR\n" +
        "    crest.patches                             List CrestSafeBind-registered patches\n" +
        "    crest.patches_filter <substring>          Filter patches by label/type substring\n" +
        "\n" +
        "  ENCOUNTER / MISSION\n" +
        "    crest.encounter_info                      Dump current encounter state\n" +
        "    crest.mission_info                        Dump current mission state\n" +
        "    crest.kill_attackers                      Kill every enemy in current battle (instant win)\n" +
        "    crest.heal_main                           Heal MainHero in current mission\n" +
        "\n" +
        "  Examples:\n" +
        "    crest.find_troop battanian            -> lists battanian_recruit, battanian_clansman, ...\n" +
        "    crest.spawn_troop battanian_picked_warrior 20\n" +
        "    crest.find_item morningstar           -> lists every morningstar variant\n" +
        "    crest.equip_main wpn0 northern_throwing_spear\n" +
        "    crest.spawn_party imperial_legionary 50\n";

    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("help", "crest")]
    public static string CmdHelp(List<string> args) => HelpText;

    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("version", "crest")]
    public static string CmdVersion(List<string> args)
    {
        try
        {
            var asm = typeof(CrestDevConsole).Assembly;
            var ver = asm.GetName().Version?.ToString() ?? "unknown";
            var patches = CrestSafeBind.GetRegisteredPatches().Count;
            return "CREST " + ver + ", " + patches + " patches registered via CrestSafeBind";
        }
        catch (Exception ex) { return "version: " + ex.Message; }
    }

    // -------------------------------------------------------------
    // Config get/set
    // -------------------------------------------------------------
    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("config_get", "crest")]
    public static string CmdConfigGet(List<string> args)
    {
        if (args.Count < 1) return "usage: crest.config_get <key>";
        var key = args[0];
        var b = CrestConfig.IsEnabled(key, false);
        var s = CrestConfig.GetString(key, "<unset>");
        var f = CrestConfig.GetFloat(key, float.NaN);
        var sb = new StringBuilder();
        sb.Append(key).Append(" -> bool=").Append(b).Append("  string=").Append(s);
        if (!float.IsNaN(f)) sb.Append("  float=").Append(f);
        return sb.ToString();
    }

    // -------------------------------------------------------------
    // Party / troops
    // -------------------------------------------------------------
    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("party_info", "crest")]
    public static string CmdPartyInfo(List<string> args)
    {
        try
        {
            EnsureTypes();
            var mainHero = _heroType?.GetProperty("MainHero", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
            if (mainHero == null) return "no main hero (not in campaign)";
            var party = mainHero.GetType().GetProperty("PartyBelongedTo")?.GetValue(mainHero);
            if (party == null) return "main hero has no party";
            var name  = party.GetType().GetProperty("Name")?.GetValue(party)?.ToString() ?? "?";
            var count = party.GetType().GetProperty("MemberRoster")?.GetValue(party)
                ?.GetType().GetProperty("TotalManCount")?.GetValue(party.GetType().GetProperty("MemberRoster")!.GetValue(party))?.ToString() ?? "?";
            var pos   = party.GetType().GetProperty("Position2D")?.GetValue(party)?.ToString() ?? "?";
            return "Party: " + name + "  members=" + count + "  pos=" + pos;
        }
        catch (Exception ex) { return "party_info error: " + ex.Message; }
    }

    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("spawn_troop", "crest")]
    public static string CmdSpawnTroop(List<string> args)
    {
        if (args.Count < 2) return "usage: crest.spawn_troop <troopId> <count>";
        var troopId = args[0];
        if (!int.TryParse(args[1], out var count) || count < 1 || count > 1000) return "count must be 1..1000";
        try
        {
            EnsureTypes();
            var mbObjMgr = _campaignType?.GetProperty("Current", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
            if (mbObjMgr == null) return "Campaign.Current is null";
            // Look up CharacterObject by stringId via Game.Current.ObjectManager
            var gameType = AccessTools2.TypeByName("TaleWorlds.Core.Game");
            var game = gameType?.GetProperty("Current", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
            var objMgr = game?.GetType().GetProperty("ObjectManager")?.GetValue(game);
            if (objMgr == null || _characterObjectType == null) return "ObjectManager unavailable";
            var getObj = objMgr.GetType().GetMethod("GetObject", new[] { typeof(string) })?.MakeGenericMethod(_characterObjectType);
            var character = getObj?.Invoke(objMgr, new object[] { troopId });
            if (character == null) return "troop '" + troopId + "' not found. Try crest.find_troop <substring>";

            var mainHero = _heroType?.GetProperty("MainHero", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
            var party = mainHero?.GetType().GetProperty("PartyBelongedTo")?.GetValue(mainHero);
            if (party == null) return "no main party";
            var roster = party.GetType().GetProperty("MemberRoster")?.GetValue(party);
            if (roster == null) return "no member roster";
            var addToCounts = roster.GetType().GetMethod("AddToCounts", new[] { _characterObjectType, typeof(int), typeof(bool), typeof(int), typeof(int), typeof(bool), typeof(int) });
            if (addToCounts != null)
            {
                addToCounts.Invoke(roster, new object[] { character, count, false, 0, 0, true, -1 });
                return "Spawned " + count + " " + troopId + " into player roster";
            }
            // Older signature: AddToCounts(character, count)
            var addSimple = roster.GetType().GetMethods().FirstOrDefault(mm => mm.Name == "AddToCounts" && mm.GetParameters().Length == 2);
            if (addSimple != null)
            {
                addSimple.Invoke(roster, new object[] { character, count });
                return "Spawned " + count + " " + troopId + " into player roster";
            }
            return "AddToCounts method shape unknown";
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "spawn_troop", ex); return "error: " + ex.Message; }
    }

    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("find_troop", "crest")]
    public static string CmdFindTroop(List<string> args)
    {
        if (args.Count < 1) return "usage: crest.find_troop <substring>";
        var pat = args[0].ToLowerInvariant();
        try
        {
            EnsureTypes();
            if (_characterObjectType == null) return "CharacterObject type unavailable";
            var allChars = _characterObjectType.GetProperty("All", BindingFlags.Static | BindingFlags.Public)?.GetValue(null) as System.Collections.IEnumerable;
            if (allChars == null) return "CharacterObject.All unavailable";
            var matches = new List<string>();
            foreach (var c in allChars)
            {
                if (c == null) continue;
                var sid = c.GetType().GetProperty("StringId")?.GetValue(c)?.ToString();
                if (sid == null) continue;
                if (sid.IndexOf(pat, StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    matches.Add(sid);
                    if (matches.Count >= 30) break;
                }
            }
            return matches.Count == 0 ? "no matches" : string.Join(", ", matches);
        }
        catch (Exception ex) { return "error: " + ex.Message; }
    }

    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("heal_party", "crest")]
    public static string CmdHealParty(List<string> args)
    {
        try
        {
            EnsureTypes();
            var mainHero = _heroType?.GetProperty("MainHero", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
            var party = mainHero?.GetType().GetProperty("PartyBelongedTo")?.GetValue(mainHero);
            var roster = party?.GetType().GetProperty("MemberRoster")?.GetValue(party);
            if (roster == null) return "no roster";
            var healAll = roster.GetType().GetMethods().FirstOrDefault(m => m.Name == "HealAllTroops" || m.Name == "HealAll");
            if (healAll != null) { healAll.Invoke(roster, null); return "healed party"; }
            return "heal method not found on this game version";
        }
        catch (Exception ex) { return "error: " + ex.Message; }
    }

    // -------------------------------------------------------------
    // Equipment
    // -------------------------------------------------------------
    private static int ResolveSlotName(string name)
    {
        // EquipmentIndex enum positions: Weapon0..3 = 0..3, Head=5, Body=6, Leg=7, Gloves=8, Horse=9, HorseHarness=10, Cape=4
        switch (name.ToLowerInvariant())
        {
            case "wpn0": case "weapon0": return 0;
            case "wpn1": case "weapon1": return 1;
            case "wpn2": case "weapon2": return 2;
            case "wpn3": case "weapon3": return 3;
            case "cape":     return 4;
            case "head":     return 5;
            case "body":     return 6;
            case "leg":      return 7;
            case "gloves":   return 8;
            case "horse":    return 9;
            case "harness":  return 10;
            default:         return -1;
        }
    }

    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("equip_main", "crest")]
    public static string CmdEquipMain(List<string> args)
    {
        if (args.Count < 2) return "usage: crest.equip_main <slot> <itemId>  (slot: head|body|leg|gloves|cape|horse|harness|wpn0..3)";
        var slotIdx = ResolveSlotName(args[0]);
        if (slotIdx < 0) return "unknown slot '" + args[0] + "'";
        var itemId = args[1];
        try
        {
            EnsureTypes();
            // Resolve ItemObject
            var gameType = AccessTools2.TypeByName("TaleWorlds.Core.Game");
            var game = gameType?.GetProperty("Current", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
            var objMgr = game?.GetType().GetProperty("ObjectManager")?.GetValue(game);
            if (objMgr == null || _itemObjectType == null) return "ObjectManager unavailable";
            var getObj = objMgr.GetType().GetMethod("GetObject", new[] { typeof(string) })?.MakeGenericMethod(_itemObjectType);
            var item = getObj?.Invoke(objMgr, new object[] { itemId });
            if (item == null) return "item '" + itemId + "' not found. Try crest.find_item <substring>";

            var mainHero = _heroType?.GetProperty("MainHero", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
            if (mainHero == null) return "no main hero";

            // Get BattleEquipment and set the slot
            var battleEq = mainHero.GetType().GetProperty("BattleEquipment")?.GetValue(mainHero);
            if (battleEq == null || _equipmentElementType == null || _equipmentIndexType == null) return "equipment props unavailable";

            // Construct EquipmentElement(item)
            var eeCtor = _equipmentElementType.GetConstructor(new[] { _itemObjectType });
            if (eeCtor == null) return "EquipmentElement(ItemObject) ctor missing";
            var ee = eeCtor.Invoke(new[] { item });

            // Find Equipment indexer setter via ItemValue/Item / EquipmentSetter.
            // Equipment has AddEquipmentToSlotWithoutAgent or similar. Use indexer set.
            var eqType = battleEq.GetType();
            var idxer = eqType.GetMethods().FirstOrDefault(m => m.Name == "set_Item" && m.GetParameters().Length == 2);
            if (idxer == null) return "Equipment indexer setter missing";
            // Parameter [0] is EquipmentIndex enum value
            var eIdxValue = Enum.ToObject(_equipmentIndexType, slotIdx);
            idxer.Invoke(battleEq, new[] { eIdxValue, ee });
            return "Equipped " + itemId + " in slot " + args[0];
        }
        catch (Exception ex) { CrestDiag.LogCaught(Source, "equip_main", ex); return "error: " + ex.Message; }
    }

    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("equip_clear", "crest")]
    public static string CmdEquipClear(List<string> args)
    {
        if (args.Count < 1) return "usage: crest.equip_clear <slot>";
        var slotIdx = ResolveSlotName(args[0]);
        if (slotIdx < 0) return "unknown slot '" + args[0] + "'";
        try
        {
            EnsureTypes();
            var mainHero = _heroType?.GetProperty("MainHero", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
            var battleEq = mainHero?.GetType().GetProperty("BattleEquipment")?.GetValue(mainHero);
            if (battleEq == null || _equipmentElementType == null || _equipmentIndexType == null) return "no equipment";
            var ee = Activator.CreateInstance(_equipmentElementType);  // default = empty
            var idxer = battleEq.GetType().GetMethods().FirstOrDefault(m => m.Name == "set_Item" && m.GetParameters().Length == 2);
            if (idxer == null) return "indexer missing";
            var eIdxValue = Enum.ToObject(_equipmentIndexType, slotIdx);
            idxer.Invoke(battleEq, new[] { eIdxValue, ee });
            return "Cleared slot " + args[0];
        }
        catch (Exception ex) { return "error: " + ex.Message; }
    }

    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("find_item", "crest")]
    public static string CmdFindItem(List<string> args)
    {
        if (args.Count < 1) return "usage: crest.find_item <substring>";
        var pat = args[0].ToLowerInvariant();
        try
        {
            EnsureTypes();
            if (_itemObjectType == null) return "ItemObject type unavailable";
            // ItemObject.AllItems via Items.AllItems or directly off ItemObject.All
            var allField = _itemObjectType.GetProperty("All", BindingFlags.Static | BindingFlags.Public);
            var allItems = allField?.GetValue(null) as System.Collections.IEnumerable;
            if (allItems == null)
            {
                // Try alternative name
                var itemsType = AccessTools2.TypeByName("TaleWorlds.Core.Items");
                if (itemsType != null)
                {
                    var itemsAll = itemsType.GetProperty("All", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
                    allItems = itemsAll as System.Collections.IEnumerable;
                }
            }
            if (allItems == null) return "no item enumeration available";
            var matches = new List<string>();
            foreach (var it in allItems)
            {
                if (it == null) continue;
                var sid = it.GetType().GetProperty("StringId")?.GetValue(it)?.ToString();
                if (sid == null) continue;
                if (sid.IndexOf(pat, StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    matches.Add(sid);
                    if (matches.Count >= 30) break;
                }
            }
            return matches.Count == 0 ? "no matches" : string.Join(", ", matches);
        }
        catch (Exception ex) { return "error: " + ex.Message; }
    }

    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("give_item", "crest")]
    public static string CmdGiveItem(List<string> args)
    {
        if (args.Count < 1) return "usage: crest.give_item <itemId> [count]";
        var itemId = args[0];
        var count = 1;
        if (args.Count > 1) int.TryParse(args[1], out count);
        if (count < 1) count = 1;
        try
        {
            EnsureTypes();
            var gameType = AccessTools2.TypeByName("TaleWorlds.Core.Game");
            var game = gameType?.GetProperty("Current", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
            var objMgr = game?.GetType().GetProperty("ObjectManager")?.GetValue(game);
            var getObj = objMgr?.GetType().GetMethod("GetObject", new[] { typeof(string) })?.MakeGenericMethod(_itemObjectType!);
            var item = getObj?.Invoke(objMgr, new object[] { itemId });
            if (item == null) return "item '" + itemId + "' not found";

            var mainHero = _heroType!.GetProperty("MainHero", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
            var party = mainHero?.GetType().GetProperty("PartyBelongedTo")?.GetValue(mainHero);
            var inv = party?.GetType().GetProperty("ItemRoster")?.GetValue(party);
            if (inv == null) return "no inventory";
            var addToCounts = inv.GetType().GetMethods().FirstOrDefault(m => m.Name == "AddToCounts" && m.GetParameters().Length >= 2);
            if (addToCounts == null) return "AddToCounts missing";
            var pcount = addToCounts.GetParameters().Length;
            object[] callArgs = pcount == 2 ? new object[] { item, count } : new object[pcount];
            if (pcount > 2) { callArgs[0] = item; callArgs[1] = count; for (int i = 2; i < pcount; i++) callArgs[i] = (object)Type.Missing; }
            try { addToCounts.Invoke(inv, callArgs); }
            catch
            {
                // Some signatures take ItemRosterElement instead of ItemObject. Try construct.
                var ireType = AccessTools2.TypeByName("TaleWorlds.Core.ItemRosterElement");
                var ireCtor = ireType?.GetConstructor(new[] { _itemObjectType, typeof(int) });
                if (ireCtor != null)
                {
                    var ire = ireCtor.Invoke(new[] { item, (object)count });
                    var addRoster = inv.GetType().GetMethods().FirstOrDefault(m => m.Name == "Add" && m.GetParameters().Length == 1 && m.GetParameters()[0].ParameterType == ireType);
                    addRoster?.Invoke(inv, new[] { ire });
                }
            }
            return "Added " + count + " " + itemId + " to inventory";
        }
        catch (Exception ex) { return "error: " + ex.Message; }
    }

    // -------------------------------------------------------------
    // Hero
    // -------------------------------------------------------------
    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("hero_info", "crest")]
    public static string CmdHeroInfo(List<string> args)
    {
        try
        {
            EnsureTypes();
            var mainHero = _heroType?.GetProperty("MainHero", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
            if (mainHero == null) return "no main hero";
            var name = mainHero.GetType().GetProperty("Name")?.GetValue(mainHero)?.ToString() ?? "?";
            var gold = mainHero.GetType().GetProperty("Gold")?.GetValue(mainHero)?.ToString() ?? "?";
            var clan = mainHero.GetType().GetProperty("Clan")?.GetValue(mainHero);
            var clanName = clan?.GetType().GetProperty("Name")?.GetValue(clan)?.ToString() ?? "?";
            var lv = mainHero.GetType().GetProperty("Level")?.GetValue(mainHero)?.ToString() ?? "?";
            return "Hero: " + name + "  level=" + lv + "  gold=" + gold + "  clan=" + clanName;
        }
        catch (Exception ex) { return "error: " + ex.Message; }
    }

    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("gold", "crest")]
    public static string CmdGold(List<string> args)
    {
        if (args.Count < 1 || !int.TryParse(args[0], out var amt)) return "usage: crest.gold <amount>";
        try
        {
            EnsureTypes();
            var mainHero = _heroType?.GetProperty("MainHero", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
            if (mainHero == null) return "no main hero";
            var heroType = mainHero.GetType();
            var current = (int)(heroType.GetProperty("Gold")?.GetValue(mainHero) ?? 0);
            var setter = heroType.GetProperty("Gold")?.GetSetMethod();
            if (setter == null) return "Gold setter not accessible";
            setter.Invoke(mainHero, new object[] { current + amt });
            return "Gold: " + current + " -> " + (current + amt);
        }
        catch (Exception ex) { return "error: " + ex.Message; }
    }

    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("faction_relations", "crest")]
    public static string CmdFactionRelations(List<string> args)
    {
        if (args.Count < 2) return "usage: crest.faction_relations <factionA> <factionB>";
        try
        {
            EnsureTypes();
            // Resolve factions by stringId
            var gameType = AccessTools2.TypeByName("TaleWorlds.Core.Game");
            var game = gameType?.GetProperty("Current", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
            var objMgr = game?.GetType().GetProperty("ObjectManager")?.GetValue(game);
            // Try Kingdom first then Clan
            var kType = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.Kingdom");
            var cType = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.Clan");
            object? Resolve(string id)
            {
                if (objMgr == null) return null;
                if (kType != null)
                {
                    var getK = objMgr.GetType().GetMethod("GetObject", new[] { typeof(string) })?.MakeGenericMethod(kType);
                    var k = getK?.Invoke(objMgr, new object[] { id });
                    if (k != null) return k;
                }
                if (cType != null)
                {
                    var getC = objMgr.GetType().GetMethod("GetObject", new[] { typeof(string) })?.MakeGenericMethod(cType);
                    return getC?.Invoke(objMgr, new object[] { id });
                }
                return null;
            }
            var a = Resolve(args[0]);
            var b = Resolve(args[1]);
            if (a == null || b == null) return "couldn't resolve one or both factions";
            var atWar = _factionManagerType?.GetMethod("IsAtWarAgainstFaction")?.Invoke(null, new[] { a, b }) as bool?;
            return args[0] + " vs " + args[1] + " : atWar=" + atWar;
        }
        catch (Exception ex) { return "error: " + ex.Message; }
    }

    // -------------------------------------------------------------
    // Patch inspector
    // -------------------------------------------------------------
    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("patches", "crest")]
    public static string CmdPatches(List<string> args)
    {
        var patches = CrestSafeBind.GetRegisteredPatches();
        if (patches.Count == 0) return "no patches registered via CrestSafeBind";
        var sb = new StringBuilder();
        sb.Append("CrestSafeBind registry: ").Append(patches.Count).Append(" patches\n");
        foreach (var p in patches.OrderBy(x => x.OwnerAssembly).ThenBy(x => x.Label))
        {
            sb.AppendFormat("  {0,-20} {1,-30} {2,-9} {3}.{4}\n",
                p.OwnerAssembly, p.Label, p.PatchKind, p.TargetType, p.TargetMethod);
        }
        return sb.ToString();
    }

    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("patches_filter", "crest")]
    public static string CmdPatchesFilter(List<string> args)
    {
        if (args.Count < 1) return "usage: crest.patches_filter <substring>";
        var pat = args[0];
        var patches = CrestSafeBind.GetRegisteredPatches()
            .Where(p => p.Label.IndexOf(pat, StringComparison.OrdinalIgnoreCase) >= 0
                     || p.TargetType.IndexOf(pat, StringComparison.OrdinalIgnoreCase) >= 0
                     || p.OwnerAssembly.IndexOf(pat, StringComparison.OrdinalIgnoreCase) >= 0)
            .ToList();
        if (patches.Count == 0) return "no matches for '" + pat + "'";
        var sb = new StringBuilder();
        sb.Append(patches.Count).Append(" patches matching '").Append(pat).Append("':\n");
        foreach (var p in patches.OrderBy(x => x.OwnerAssembly).ThenBy(x => x.Label))
            sb.AppendFormat("  {0,-20} {1,-30} {2,-9} {3}.{4}\n", p.OwnerAssembly, p.Label, p.PatchKind, p.TargetType, p.TargetMethod);
        return sb.ToString();
    }

    // -------------------------------------------------------------
    // Encounter / mission
    // -------------------------------------------------------------
    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("encounter_info", "crest")]
    public static string CmdEncounterInfo(List<string> args)
    {
        try
        {
            var peType = AccessTools2.TypeByName("TaleWorlds.CampaignSystem.Encounters.PlayerEncounter");
            var current = peType?.GetProperty("Current", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
            if (current == null) return "no active PlayerEncounter";
            var meField = peType.GetField("_mapEvent", BindingFlags.Instance | BindingFlags.NonPublic);
            var me = meField?.GetValue(current);
            if (me == null) return "encounter active but no MapEvent";
            var meType = me.GetType();
            var defenders = meType.GetMethod("PartiesOnSide")?.Invoke(me, new object[] { 0 });
            var attackers = meType.GetMethod("PartiesOnSide")?.Invoke(me, new object[] { 1 });
            int dCount = 0, aCount = 0;
            if (defenders is System.Collections.IEnumerable dE) foreach (var _ in dE) dCount++;
            if (attackers is System.Collections.IEnumerable aE) foreach (var _ in aE) aCount++;
            return "MapEvent: defenders=" + dCount + " attackers=" + aCount;
        }
        catch (Exception ex) { return "error: " + ex.Message; }
    }

    [TaleWorlds.Library.CommandLineFunctionality.CommandLineArgumentFunction("kill_attackers", "crest")]
    public static string CmdKillAttackers(List<string> args)
    {
        try
        {
            var missionType = AccessTools2.TypeByName("TaleWorlds.MountAndBlade.Mission");
            var current = missionType?.GetProperty("Current", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
            if (current == null) return "no active Mission";
            var teamsProp = missionType.GetProperty("Teams")?.GetValue(current) as System.Collections.IEnumerable;
            if (teamsProp == null) return "no Teams";
            var mainAgent = missionType.GetProperty("MainAgent")?.GetValue(current);
            if (mainAgent == null) return "no MainAgent";
            var playerTeam = mainAgent.GetType().GetProperty("Team")?.GetValue(mainAgent);
            int killed = 0;
            foreach (var team in teamsProp)
            {
                if (team == null || ReferenceEquals(team, playerTeam)) continue;
                var activeAgents = team.GetType().GetProperty("ActiveAgents")?.GetValue(team) as System.Collections.IEnumerable;
                if (activeAgents == null) continue;
                var agents = new List<object>();
                foreach (var a in activeAgents) if (a != null) agents.Add(a);
                foreach (var a in agents)
                {
                    var die = a.GetType().GetMethods().FirstOrDefault(m => m.Name == "Die" || m.Name == "FadeOut");
                    if (die == null) continue;
                    try { die.Invoke(a, die.GetParameters().Length == 0 ? null : new object[die.GetParameters().Length]); killed++; }
                    catch { }
                }
            }
            return "killed " + killed + " enemy agents";
        }
        catch (Exception ex) { return "error: " + ex.Message; }
    }
}
