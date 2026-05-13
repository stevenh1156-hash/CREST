# Watcher dev-mode auto-ready chain -- verification
Status: code present in tools/crest-dev.ps1 (grep -c=1), but no
agent-ready-auto-*.ps1 has shown up in done/ across multiple battles.
Suspect: watcher's seenResults dict gets preloaded with existing
result files at startup; postmortem-result-detection branch only fires
on FILES NOT IN seenResults. Need to add a separate "fresh post-startup"
detection or fire the chain on first new battle-end-sentinel instead.
