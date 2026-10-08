# betterfiles: progress

Goal: replace the parts of macOS the author dislikes: Spotlight (Cmd+Space) and Finder.
Two pieces, built one at a time, each with its own spec and plan.

## Done

### Part 1: BetterLauncher (Spotlight replacement), built, awaiting full manual smoke test
- Menu-bar Swift app (no Dock icon). Global **Cmd+Space** opens a floating search panel.
- Searches apps, files and folders using Spotlight's index (`NSMetadataQuery`). No web, Mail or Messages results.
- Ranks results by match quality (prefix > word-prefix > substring), plus how often and how recently you open them, plus a small bonus for apps. Top 8 shown.
- Ignores case and accents (`cafe` finds `Café`). Excludes `~/Library` and hidden paths.
- Usage history is stored in `~/Library/Application Support/BetterLauncher/usage.json`. A corrupt file starts empty.
- If a result can't be opened (moved or deleted), nothing is recorded and the panel stays open.
- Menu-bar menu warns if Spotlight's own Cmd+Space shortcut is still on.
- 16 unit tests pass (`swift test`).
- Reviewed by a fresh reviewer. 3 Important findings fixed (focus after close, shortcut-taken notice, selection jumping on live updates).

Design: [docs/superpowers/specs/2026-10-08-launcher-design.md](docs/superpowers/specs/2026-10-08-launcher-design.md)
Plan: [docs/superpowers/plans/2026-10-08-launcher.md](docs/superpowers/plans/2026-10-08-launcher.md)

## Run it

1. System Settings > Keyboard > Keyboard Shortcuts > Spotlight > untick "Show Spotlight search" (shortcut only; keep the Spotlight index on, the app uses it).
2. `swift run BetterLauncher`, then press Cmd+Space. Ctrl+C in the terminal quits it.

## Remaining

### Launcher
- [ ] Finish the manual smoke test (Task 5 of the plan): hotkey toggle, typing, Return, Esc returns to the previous app, odd characters, deleted file.
- [ ] Deferred minor: stop the live search while the panel is hidden.
- [ ] Deferred minor: give feedback (beep, drop the row) when opening a result fails.
- [ ] "Spotlight index unavailable" message (in the spec, not built).
- [ ] Package as a real `.app` and add launch-at-login. It currently runs as a bare executable.
- [ ] Panel is a fixed height; resize to fit the results if it looks wrong.
- [ ] Search caps at 1000 hits, so one-letter queries can miss the best match. Move to our own index (FSEvents + SQLite FTS) if Spotlight's index is the limit.

### Part 2: file manager (Finder replacement), not started
- [ ] Brainstorm and write its own spec, then a plan.
- [ ] Direction so far: native macOS app, Explorer-style (folder tree sidebar, tabs, address bar, cut/paste that moves files, sortable details view).
- [ ] Note: Finder can't be uninstalled (SIP). The plan is an app that opens for folders and gets a shortcut and Dock icon.
- [ ] Launcher integration: typing a folder name opens it in the new file manager.

### Not planned (add only if wanted)
Calculator, clipboard history, plugins, web search, file previews.
