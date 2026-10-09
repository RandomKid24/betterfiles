# Changelog

## [Unreleased]

### Added
- Butterlight: **search inside files**. Type `? invoice 2025` to find files by their text (uses Spotlight's content index).
- Butterlight: **web shortcuts**: `g`, `yt`, `gh`, `so`, `mdn`, `npm`, `wiki`, `maps`, `ddg` followed by your words.
- Butterlight: **quick commands**: `lock`, `sleep`, `dark mode`, `uuid`, `timestamp`, `ip`.
- Butterlight: shows a clear message when macOS is hiding Documents, Desktop or Downloads from it, and re-indexes as soon as you allow access.
- Butterfinder: **Share** submenu (AirDrop, Messages, Mail...), **Calculate Size** for folders (shown in the Size column), **Go to Folder** (⇧⌘G).

### Fixed
- Butterfinder: **New Folder now starts renaming right away.** The new folder is selected and its name is editable. The same bug stopped Duplicate, Compress, Make Alias, bulk rename and "Show in Butterfinder" from selecting their result.
- Butterfinder: the sidebar could freeze the app on startup when the current folder was inside a very large folder (it read tags and details for every file just to find sub-folders).
- Butterlight: files in very large home folders could be missing from search. Name search now also asks Spotlight (off the main thread), and the built-in index scans your personal folders first and limits each top-level folder so one huge folder can't use up the whole index.

### Changed
- Butterlight no longer uses a live Spotlight query object; name search runs `mdfind` in the background and cancels itself on the next keystroke.

## [1.0.2] - 2026-10-09

### Fixed
- Butterfinder: sorting by date, size or kind no longer groups folders above files, so the newest item is really at the top. Name sort still keeps folders first.
- Butterfinder: the filter no longer matches Finder tag names by accident (typing "or" showed Orange-tagged files). Use `#red` or `tag:red` to filter by tag.

### Changed
- Butterfinder: the filter tries your exact phrase first, then any-order words; the status bar shows "N of M items match".

## [1.0.1] - 2026-10-09

### Added
- Butterfinder: tagged folders are drawn in their tag's color.
- Butterfinder and Butterlight: icons in the right-click menus.
- Butterlight: type an IP address, `localhost:port`, host:port or a domain to open it directly in the browser.

### Changed
- Butterlight is lighter: it no longer queries Spotlight on every keystroke once its own index is ready, does no disk work when it opens, and draws its shadow more cheaply. The file index is capped at 150,000 entries and skips more developer build folders.
- Butterfinder's thumbnail cache is limited to about 48 MB.

### Fixed
- Butterlight showed two borders around the panel.
- Butterfinder treated command-line flags as folder paths.
- The sidebar could be squeezed off-screen; the path bar now fits the available width.

## [Unreleased]

### Added
- **BetterFiles Stage A**: Explorer-style file manager. Folder tree sidebar, editable address bar with breadcrumbs, details view with sortable columns, zoomable icon view with thumbnails, in-folder filter, Cut+Paste-to-move, Trash-only delete, no-overwrite naming, hidden files and extensions always shown.
- `FilesCore` library (listing, sorting, filtering, address parsing, file operations, clipboard rules) with 40 unit tests.
- BetterLauncher: glass panel with a pop-in animation matching macOS 26's large rounded corners.
- BetterLauncher: in-memory app index, usage-history candidates, and Spotlight word-prefix search with 50 ms result batching.
- Stage A design spec and implementation plan under `docs/superpowers/`.

### Changed
- BetterLauncher search is much faster: one-letter queries no longer scan the whole disk (apps and history answer instantly; file search starts at 2 characters), and the live query stops while the panel is hidden.

### Fixed
- Cut+Paste keeps files that failed to move on the clipboard so they can be retried.
- Address bar Cmd+L no longer risks selecting every file.
- F2 rename edits the Name column even after columns are reordered.
- Icon view zoom no longer flickers; thumbnails match the zoom size; Select All updates the selection.

## [0.1.0] earlier

### Added
- BetterLauncher: menu-bar Cmd+Space launcher for apps, files and folders, ranked by match quality and usage.
- `LauncherCore` library with unit tests.

### Fixed (from the pre-release review)
- Panel no longer steals app focus, so Esc returns you to the previous app.
- The "Cmd+Space is taken" notice appears when Spotlight's shortcut is still enabled.
- Highlighted row no longer jumps to the top when Spotlight sends live updates.
