// Bisect test 1 (Y.75c): CrestAgentTickFinalizer removed to test
// whether it's the source of the world-map CTD. Class definition
// stubbed; the SubModule.cs TryApply call below has been commented
// out for the same reason. Restore the body if Test 1 proves Y.74
// finalizer is innocent.
namespace Bannerlord.Harmony;

internal static class CrestAgentTickFinalizer
{
    public static void TryApply(HarmonyLib.Harmony harmony) { /* dormant */ }
}
