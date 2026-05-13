# Green ready banner at bottom of menu
Crest.ps1 menu should print a big green "READY FOR BATTLE" block
when these are all true:
  - record.on present
  - dev-mode.on present
  - watcher alive (heartbeat < 90s AND process exists)
  - DLL deployed matches dev hash
  - no pending deploy
Otherwise print yellow "NOT READY -- <reason>" with the first failing
condition.
