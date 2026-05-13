using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Xml;

namespace Bannerlord.Harmony;

/// <summary>
/// Phase N runtime self-heal: ensures the four Bannerlord.X stub module
/// folders exist on disk and are enabled in the user's load order. Pairs
/// with <see cref="HideCrestStubsPatch"/> in the BLSE fork (which hides the
/// stubs from the launcher UI) and the install-time stub materialization in
/// <c>Unblock-CrestInstall.ps1</c>.
///
/// Why we still ship stubs at all: Bannerlord's engine and launcher both
/// resolve <c>&lt;DependedModule Id="X"/&gt;</c> by walking <c>Modules\</c>
/// and matching against folder names. To make community mods that depend on
/// <c>Bannerlord.Harmony</c> / <c>.ButterLib</c> / <c>.UIExtenderEx</c> /
/// <c>.MBOptionScreen</c> pass that check, the four named folders need to
/// exist. They are otherwise empty: no DLLs, no SubModule classes, just a
/// 1-KB metadata file.
///
/// What this self-heal does at <c>OnSubModuleLoad</c>:
///   1. Walks <c>Modules\&lt;StubId&gt;\SubModule.xml</c> for each of the
///      four stub IDs. If any folder or its SubModule.xml is missing,
///      recreates the directory and writes a default SubModule.xml from the
///      embedded template constants below.
///   2. Reads the user's <c>Configs\LauncherData.xml</c>; if any stub is
///      not present in the singleplayer mod-data list (or is present but
///      <c>IsSelected=false</c>), promotes it to selected. Saves the file.
///
/// Both steps are idempotent. If everything is already correct, the method
/// returns silently after a few file existence checks.
///
/// Failure mode: any exception during stub recreation or LauncherData edit
/// is swallowed and logged via <see cref="CrestDiag"/>. Phase N's stub-fix
/// path is best-effort -- a broken self-heal must not block game startup.
/// </summary>
internal static class CrestEnsureStubs
{
    // Stub IDs matched in <DependedModule>/folder name. Order is irrelevant.
    private static readonly StubInfo[] Stubs =
    {
        new("Bannerlord.Harmony",        "Harmony (CREST stub)",      "v2.4.2.135"),
        new("Bannerlord.ButterLib",      "ButterLib (CREST stub)",    "v2.10.4"),
        new("Bannerlord.UIExtenderEx",   "UIExtenderEx (CREST stub)", "v2.13.2"),
        new("Bannerlord.MBOptionScreen", "MCMv5 (CREST stub)",        "v5.11.4"),
    };

    public static void Run()
    {
        try
        {
            var modulesRoot = ResolveModulesRoot();
            if (modulesRoot == null)
            {
                CrestDiag.Log(nameof(CrestEnsureStubs), "could not resolve Modules\\ root -- self-heal skipped");
                return;
            }

            var created = EnsureFolders(modulesRoot);
            var enabled = EnsureEnabledInLauncherData(modulesRoot);

            if (created > 0 || enabled > 0)
            {
                CrestDiag.Log(nameof(CrestEnsureStubs),
                    $"self-heal: recreated {created} stub folder(s), re-enabled {enabled} in LauncherData.xml");
            }
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(nameof(CrestEnsureStubs), nameof(Run), ex);
        }
    }

    /// <summary>
    /// Walks up from this assembly's location to find <c>...\Modules\</c>.
    /// Layout: <c>Modules\CREST\bin\Win64_Shipping_Client\Crest.Harmony.dll</c>
    /// → three parents up.
    /// </summary>
    private static string? ResolveModulesRoot()
    {
        try
        {
            var asmLoc = typeof(CrestEnsureStubs).Assembly.Location;
            if (string.IsNullOrEmpty(asmLoc)) return null;
            var binDir = Path.GetDirectoryName(asmLoc);                                 // ...\bin\Win64_Shipping_Client
            var binParent = Directory.GetParent(binDir ?? string.Empty);                // ...\bin
            var crestDir = binParent?.Parent;                                           // ...\CREST
            var modulesDir = crestDir?.Parent;                                          // ...\Modules
            if (modulesDir == null) return null;
            return modulesDir.FullName;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Recreates any missing stub folder + SubModule.xml. Returns the number
    /// of stubs that were created.
    /// </summary>
    private static int EnsureFolders(string modulesRoot)
    {
        var created = 0;
        foreach (var stub in Stubs)
        {
            var dir = Path.Combine(modulesRoot, stub.Id);
            var xmlPath = Path.Combine(dir, "SubModule.xml");
            // ALSO ensure the stub has a bin\Win64_Shipping_Client folder.
            // BLSE's HarmonyFinder probes for that folder's existence as a
            // sanity check ("the Harmony module is corrupted") before letting
            // the launcher proceed -- even though the stub itself ships zero
            // DLLs and the actual Harmony binaries live in CREST/bin. Without
            // this folder BLSE refuses to launch with a hard error dialog.
            var binDir = Path.Combine(dir, "bin", "Win64_Shipping_Client");
            try
            {
                if (!Directory.Exists(binDir)) Directory.CreateDirectory(binDir);
            }
            catch (Exception ex)
            {
                CrestDiag.LogCaught(nameof(CrestEnsureStubs), $"create bin dir for {stub.Id}", ex);
            }

            if (File.Exists(xmlPath)) continue;
            try
            {
                Directory.CreateDirectory(dir);
                File.WriteAllText(xmlPath, BuildStubXml(stub), Encoding.UTF8);
                created++;
            }
            catch (Exception ex)
            {
                CrestDiag.LogCaught(nameof(CrestEnsureStubs), $"create stub {stub.Id}", ex);
            }
        }
        return created;
    }

    /// <summary>
    /// Reads <c>&lt;GameRoot&gt;/../../../Documents/Mount and Blade II Bannerlord/Configs/LauncherData.xml</c>
    /// (or the platform equivalent), and forces each of our four stubs to
    /// have <c>IsSelected="true"</c> in the singleplayer mod list. Returns
    /// the number of stub entries that were inserted or flipped from
    /// disabled to enabled. Idempotent: zero return when everything is
    /// already correct.
    /// </summary>
    private static int EnsureEnabledInLauncherData(string modulesRoot)
    {
        var launcherDataPath = ResolveLauncherDataPath();
        if (launcherDataPath == null || !File.Exists(launcherDataPath))
        {
            // No LauncherData yet -- e.g. first launch ever. The DefaultModule=true
            // flag in our stub SubModule.xml will cause the launcher to add them
            // when it generates the file. Nothing to do here.
            return 0;
        }

        var changed = 0;
        try
        {
            var doc = new XmlDocument { PreserveWhitespace = true };
            doc.Load(launcherDataPath);

            // Two possible shapes -- TaleWorlds renamed the schema in past patches.
            // Both have a sequence of UserModData / ModDatas elements with
            // child Id and IsSelected (or named-attribute equivalents).
            // We tolerantly walk every UserModData element regardless of nesting.
            var modDataNodes = doc.GetElementsByTagName("UserModData");
            if (modDataNodes.Count == 0)
            {
                // Older schema variant: <UserGameTypeData> -> <ModDatas> -> <ModData>
                modDataNodes = doc.GetElementsByTagName("ModData");
            }

            // Collect existing stub entries for fast lookup.
            var existing = new Dictionary<string, XmlElement>(StringComparer.OrdinalIgnoreCase);
            foreach (XmlNode node in modDataNodes)
            {
                if (node is not XmlElement elt) continue;
                var idElt = FindChildByTagName(elt, "Id");
                var id = idElt?.InnerText?.Trim();
                if (!string.IsNullOrEmpty(id)) existing[id!] = elt;
            }

            foreach (var stub in Stubs)
            {
                if (existing.TryGetValue(stub.Id, out var elt))
                {
                    var sel = FindChildByTagName(elt, "IsSelected");
                    if (sel != null && !string.Equals(sel.InnerText?.Trim(), "true", StringComparison.OrdinalIgnoreCase))
                    {
                        sel.InnerText = "true";
                        changed++;
                    }
                }
                else
                {
                    // Stub is missing from LauncherData entirely. Inserting a new
                    // entry safely requires knowing the parent collection's shape;
                    // skip rather than guess. The launcher will pick up the stub on
                    // its next refresh because DefaultModule=true is set in the
                    // stub's SubModule.xml.
                    CrestDiag.Log(nameof(CrestEnsureStubs),
                        $"stub {stub.Id} not yet in LauncherData.xml -- launcher will add it on next refresh");
                }
            }

            if (changed > 0) doc.Save(launcherDataPath);
        }
        catch (Exception ex)
        {
            CrestDiag.LogCaught(nameof(CrestEnsureStubs), nameof(EnsureEnabledInLauncherData), ex);
        }
        return changed;
    }

    private static XmlElement? FindChildByTagName(XmlElement parent, string tagName)
    {
        foreach (XmlNode child in parent.ChildNodes)
        {
            if (child is XmlElement elt && string.Equals(elt.LocalName, tagName, StringComparison.OrdinalIgnoreCase))
                return elt;
        }
        return null;
    }

    private static string? ResolveLauncherDataPath()
    {
        try
        {
            // Resolves to "Documents\Mount and Blade II Bannerlord\Configs\LauncherData.xml"
            // on Windows. Bannerlord uses Environment.SpecialFolder.MyDocuments. We
            // accept either MyDocuments-relative or any explicit override the engine
            // sets via TaleWorlds.Library.PathHelpers (out of scope here -- those
            // overrides are rare).
            var docs = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            if (string.IsNullOrEmpty(docs)) return null;
            return Path.Combine(docs, "Mount and Blade II Bannerlord", "Configs", "LauncherData.xml");
        }
        catch
        {
            return null;
        }
    }

    private static string BuildStubXml(StubInfo s) =>
        $@"<?xml version=""1.0"" encoding=""UTF-8""?>
<!--
  CREST stub module for {s.Id}. Auto-generated by Crest.Harmony's runtime
  self-heal because the original stub folder was missing.

  Empty placeholder that satisfies <DependedModule Id=""{s.Id}"" /> in
  community mods' SubModule.xml. Runtime functionality is provided by CREST's
  bundled Crest.* DLLs behind TypeForwardedTo shims.

  Auto-enabled by default; CREST's BLSE launcher patch hides this from the
  launcher UI.
-->
<Module xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance""
        xsi:noNamespaceSchemaLocation=""https://raw.githubusercontent.com/BUTR/Bannerlord.XmlSchemas/master/SubModule.xsd"">
  <Id value=""{s.Id}"" />
  <Name value=""{s.Name}"" />
  <Version value=""{s.Version}"" />
  <DefaultModule value=""true"" />
  <ModuleCategory value=""Singleplayer"" />
  <ModuleType value=""Community"" />
  <Url value=""https://github.com/trashpanda/CREST"" />
  <DependedModules />
  <SubModules />
</Module>
";

    private readonly struct StubInfo
    {
        public string Id { get; }
        public string Name { get; }
        public string Version { get; }
        public StubInfo(string id, string name, string version) { Id = id; Name = name; Version = version; }
    }
}
