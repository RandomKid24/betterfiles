# Changelog

## [Unreleased]

### Added
- BetterLauncher: menu-bar Cmd+Space launcher for apps, files and folders, ranked by match quality and usage.
- `LauncherCore` library: `Ranker`, `Usage`, `Candidate`, `Selection`, `SpotlightShortcut`, with 16 unit tests.
- Design spec and implementation plan under `docs/superpowers/`.
- `PROGRESS.md` with status and remaining work.

### Fixed (from the pre-release review)
- Panel no longer steals app focus, so Esc returns you to the previous app.
- The "Cmd+Space is taken" notice now appears when Spotlight's shortcut is still enabled.
- Highlighted row no longer jumps to the top when Spotlight sends live updates.
