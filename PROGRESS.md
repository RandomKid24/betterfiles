# betterfiles: progress

Names: the launcher is **Butterlight** (was BetterLauncher), the file manager is **Butterfinder** (was BetterFiles).

Goal: replace the parts of macOS the author dislikes: Spotlight (Cmd+Space) and Finder.
Two pieces, built one at a time, each with its own spec and plan.

## Done

### Part 1: Butterlight (Spotlight replacement), built, awaiting full manual smoke test
- Menu-bar Swift app (no Dock icon). Global **Cmd+Space** opens a floating glass search panel with a pop-in animation.
- Apps come from an in-memory app index (instant). Files come from Spotlight's index using a fast word-prefix query (2+ characters). Things you opened before always appear (usage history).
- Ranking: match quality (prefix > word-prefix > substring) + how often and how recently you open it + a small bonus for apps. Top 8 shown.
- Ignores case and accents. Excludes `~/Library` and hidden paths. Usage history in `~/Library/Application Support/Butterlight/usage.json`.
- Menu-bar menu warns if Spotlight's own Cmd+Space shortcut is still on.
- Specs/plans: `docs/superpowers/specs/2026-10-08-launcher-design.md`, `docs/superpowers/plans/2026-10-08-launcher.md`.

### Part 2, Stage A: Butterfinder core browser (Finder replacement), built, awaiting manual smoke test
- Explorer-style file manager: folder tree sidebar, editable address bar with breadcrumbs, details view with sortable columns, zoomable icon view with thumbnails, in-folder filter.
- **Cut + Paste moves files** (Cut then Paste into another folder). If something else is copied in between, Paste copies instead. Failed items stay on the clipboard for retry.
- Delete goes to the Trash (never permanent). Nothing is ever overwritten (`name 2.ext`, `name copy.ext`).
- Hidden files and extensions are always shown. View mode, sort and zoom are remembered.
- Shortcuts: Cmd+C/X/V/A, Return opens, F2 renames, Cmd+Delete trashes, Cmd+Up parent, Cmd+[ / ] back/forward, Cmd+L address bar, Cmd+F filter, Cmd+1/2 views, Cmd+R reload.
- `FilesCore` library is unit-tested; the AppKit views are checked by build and the manual smoke test (Task 10 of the plan).
- 61 unit tests pass in total (21 launcher + 40 files).
- Spec: `docs/superpowers/specs/2026-10-08-files-stage-a-design.md`. Plan: `docs/superpowers/plans/2026-10-08-files-stage-a.md`.

### Polish round (2026-10-09)
- Launcher: sliding highlight, blur-in open, async icons, debounced search, instant dismiss; folders open in Butterfinder, Cmd+Return shows the item in Files; results ordered by last used; launch at login.
- Files: right-click menu, New Folder, Delete to Trash, preview pane (Quick Look), Space for Quick Look, drag and drop, tabs, folder fade.
- `run.sh` starts dev builds detached; `package.sh` installs both `.app`s into ~/Applications.

### Big feature round (2026-10-09)
- Files: Undo (Cmd+Z), live folder updates, background copy/trash/paste, favorites in the sidebar, dual pane (Cmd+\\, F5/F6), Get Info (Cmd+I), bulk rename, zip/unzip, Copy Path, Open Terminal Here, app icons.
- Launcher: own file index (no 300 cap), calculator and unit conversion, `clip` clipboard history, web search fallback, Option+Return copy path, Shift+Return Terminal, Cmd+Backspace trash.
- Not possible: macOS refuses to let an app become the default for folders.

## Run

Launcher: untick Spotlight's shortcut (System Settings > Keyboard > Keyboard Shortcuts > Spotlight), then `swift run Butterlight`.
Files: `swift run Butterfinder`.

## Remaining

### Stage A manual smoke test (needs a person at the keyboard)
- [ ] The 14-point checklist in Task 10 of the Stage A plan (sorting, address bar, cut/paste, trash, rename, filter, icon zoom, big folders, rapid folder clicking, permissions).
- [ ] Runtime-only unknowns to check: double-click opens in icon view; folder tree reveal on first launch.

### Stage A known follow-ups (from code review, none blocking)
- Switching folders keeps the old rows on screen until the new listing loads; actions in that moment act on stale rows.
- Rename: a reload mid-edit could rename a different file; F2 with several icons selected renames an arbitrary one.
- Status bar shows only the first failure of a multi-file operation.
- Copying over a name clash on an app bundle gives `App.app 2` (breaks the bundle); dangling symlinks at the destination block a paste.
- Sidebar: expanding a huge folder is synchronous; new folders and newly mounted volumes don't appear until relaunch.
- Menu key equivalents Cmd+Delete and Cmd+Up are consumed while a text field is editing.
- Paste/trash of large selections run on the main thread (UI freezes during big copies).
- Thumbnail cache has no size limit.

### Launcher
- [ ] Finish the manual smoke test (Task 5 of the launcher plan) and judge the new animation and glass shape.
- [ ] "Spotlight index unavailable" message (in the spec, not built).
- [ ] Package as a real `.app` and add launch-at-login. Both apps run as bare executables for now.
- [ ] Search is capped at 300 file hits per query, so a very common word can miss the best file. Move to our own index (FSEvents + SQLite FTS) if Spotlight's index is the limit.

### Next stages for Butterfinder
- [ ] Stage B: tabs.
- [ ] Stage C: dual pane.
- [ ] Stage D: make it the default for folders, Dock/login setup, launcher integration (type a folder name to open it in Butterfinder).
- Note: Finder can't be uninstalled (SIP). The plan is an app that opens for folders and gets a shortcut and Dock icon.

### Not planned (add only if wanted)
Calculator, clipboard history, plugins, web search, Quick Look preview pane, folder watching, network drives, tags.
