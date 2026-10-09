# Changelog

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
