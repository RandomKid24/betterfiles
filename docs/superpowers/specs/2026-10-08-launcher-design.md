# BetterLauncher: Spotlight replacement (design)

Part 1 of 2. Part 2 (the Explorer-style file manager) gets its own spec after this ships.

## Goal
Cmd+Space opens a fast launcher. It works like Spotlight but ranks by what you actually use and shows only apps, files and folders. No web suggestions, no Mail/Messages junk.

## Non-goals (add later, each as its own piece)
Calculator, clipboard history, plugins, web search, own file index, previews.

## Shape
- Swift Package, an executable target plus a small `LauncherCore` library (pure logic: `Ranker`, `Usage`) so it can be unit-tested; no Xcode project. `NSApplication` with `.accessory` activation policy (no Dock icon). Menu-bar item with Quit only.
- macOS 26, Swift 6.4 (installed toolchain).

## Components
| Unit | Does | Depends on |
|---|---|---|
| `Hotkey` | Global Cmd+Space via Carbon `RegisterEventHotKey` (needs no permissions) | none |
| `Panel` | Borderless floating `NSPanel` with a SwiftUI search field and results list. Return opens, Esc hides, up/down moves. Hides on focus loss | `Search` |
| `Search` | Live `NSMetadataQuery` over `~`, `/Applications`, `/System/Applications`. Matches display name. Excludes `~/Library` and hidden paths. Returns `[Candidate]` | system Spotlight index |
| `Ranker` | Pure function: `(query, [Candidate], usage) -> [Candidate]`. Score = match quality (prefix > word-prefix > substring) + frecency (open count, decayed by recency). Apps get a small bonus | none |
| `Usage` | Stores open counts and last-open time in `~/Library/Application Support/BetterLauncher/usage.json`. Written on every open | filesystem |

## Data flow
Hotkey -> show Panel -> keystroke updates query -> Search streams candidates -> Ranker orders them (top 8) -> Return calls `NSWorkspace.open` and `Usage.record`.

## Errors
- Hotkey registration fails (Spotlight still owns Cmd+Space): show a one-line notice in the menu-bar menu telling you to disable Spotlight's shortcut in System Settings > Keyboard > Keyboard Shortcuts > Spotlight. The app never edits system settings.
- Missing or corrupt `usage.json`: start empty.
- Spotlight indexing disabled: panel shows "Spotlight index unavailable".

## Known ceiling
Result quality depends on Spotlight's index. If it proves the limit, swap `Search` for our own FSEvents + SQLite FTS index. `Ranker` and `Panel` stay unchanged.

## Testing
- `swift test`: `Ranker` (prefix beats substring, frecency breaks ties, decay) and `Usage` round-trip (pure logic).
- Manual smoke test: hotkey opens panel, typing finds an app, Return launches it, Esc closes it.

## One-time user step
Disable Spotlight's Cmd+Space shortcut in System Settings, then launch BetterLauncher.
