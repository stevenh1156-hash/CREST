# Debounce CrestBattleEndSignal double-fire
Status: known issue, low priority.
Two battle archives 4 seconds apart per real battle (e.g. 085813 +
085817). OnEndMission fires twice during teardown.
Fix: static "lastWriteTime" check in DropSentinel -- skip if previous
write < 5 seconds ago. Idempotent at the postmortem level so cosmetic
only, but worth fixing for cleaner archives.
