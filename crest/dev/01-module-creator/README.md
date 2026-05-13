# 01. HERALD -- Bannerlord Module Creator

Wizard + scaffolder + auto-iterate loop already shipped (Y.70 phase 4-5).
Plus Herald-Dashboard.ps1 (live status GUI). Remaining work to make
HERALD shippable as a product.

- [ ] phase-8-packaging.md     -- single .exe / installer wrapping the whole flow
- [ ] phase-9-monetization.md  -- tier pricing + payment integration
- [ ] tier-2-standalone.md     -- Claude API backend, no Claude desktop required
- [ ] tier-3-daemon.md         -- polling daemon + Windows toasts
- [ ] crest-toast.md           -- toast notifications for chain events
- [ ] crest-autobisect.md      -- auto-bisect on sim regression
- [ ] crest-backup.md          -- pre-postmortem snapshot
- [ ] crest-cleanarchive.md    -- rotate battles older than 30 days, gzip recordings
- [ ] crest-gitautocommit.md   -- daily auto-commit of crest/ + source deltas
- [ ] crest-readyontabback.md  -- detect alt-tab from Bannerlord -> trigger crash check
- [ ] crest-dryrun.md          -- synthesize fake postmortem from archived recording
- [x] live-status-dashboard.md -- Herald-Dashboard.ps1 (shipped this session)
- [ ] mcp-server.md            -- HERALD MCP server for cleaner Claude integration
