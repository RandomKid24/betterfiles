# BetterFiles Stage A: core browser (design)

Part 2 of the betterfiles project (Part 1 is the launcher). Stage A of four:
A core browser (this spec), B tabs, C dual pane, D make it the default for folders. B to D get their own specs.

## Goal
A native macOS file manager that feels like Windows File Explorer: folder tree on the left, editable address bar, details and zoomable icon views, and Cut + Paste that moves files. Hidden files and file extensions are shown by default.

## Non-goals (Stage A)
Tabs, dual pane, being the default app for folders, Quick Look preview pane, network drives, tags, permanent delete, drag-and-drop between windows, a preferences screen.

## Shape
- Same Swift package as the launcher. Two new targets: `FilesCore` (library, Foundation only, unit-tested) and `BetterFiles` (executable, AppKit + SwiftUI). macOS 26, Swift 6.4, no third-party dependencies. `swiftLanguageModes: [.v5]` as in the launcher.
- Regular Dock app (unlike the launcher). Opens at the home folder.
- SwiftUI for the shell (window, toolbar, address bar). AppKit for the lists: `NSOutlineView` (tree), `NSTableView` (details), `NSCollectionView` (icons), because they handle large folders, keyboard navigation and multi-select correctly.

## `FilesCore` units
| Unit | Does | Depends on |
|---|---|---|
| `FileItem` | Value type: `url`, `name` (with extension), `isFolder`, `isHidden`, `size: Int64?`, `modified: Date?`, `kind: String` | none |
| `FolderListing` | `static func list(_ url: URL) throws -> [FileItem]`. One `contentsOfDirectory` call with resource keys prefetched. Includes hidden files. Callers run it off the main thread | FileManager |
| `Sorter` | `sort([FileItem], by: Column, ascending: Bool)`. Columns: name, modified, size, kind. Folders always first. Name sort is case- and accent-insensitive, numeric-aware (`file2` before `file10`) | none |
| `Filter` | `filter([FileItem], text:)`. Case- and accent-insensitive substring on name. Empty or whitespace text returns everything | none |
| `AddressPath` | `resolve(_ text: String, from: URL) -> URL?` expands `~`, accepts absolute paths, relative paths, trailing slashes and surrounding quotes or spaces; returns nil if the folder does not exist. `breadcrumbs(_ url: URL) -> [(name: String, url: URL)]` | FileManager |
| `FileClipboard` | Cut, Copy, Paste semantics (below). Talks to the pasteboard through a small `PasteboardProtocol` (`changeCount`, `urls`, `write(urls:)`) so tests use a fake; `BetterFiles` supplies the real `NSPasteboard` one | `FileOps` |
| `FileOps` | `move`, `copy`, `rename`, `trash`. Never overwrites: name clashes get a unique name (`name 2.ext`, `name 3.ext`). `trash` uses `FileManager.trashItem`. Returns per-file results so one failure does not abort the rest | FileManager |

### Cut / Copy / Paste rules
- **Copy** puts the file URLs on the system pasteboard. Other apps can paste them.
- **Cut** puts the same URLs on the pasteboard and remembers them as "cut", along with the pasteboard `changeCount`.
- **Paste** into a folder: if the pasteboard `changeCount` still equals the remembered one, the files are **moved**; otherwise (something else was copied since) they are **copied**. After a move, the cut state clears.
- Pasting a cut into the folder the files are already in does nothing. Pasting a copy into the same folder creates `name copy.ext`, then `name copy 2.ext`.
- Moving a folder into itself or its own subfolder is refused with a message.
- Delete always means move to Trash. There is no permanent delete in Stage A.

## `BetterFiles` units
| Unit | Does |
|---|---|
| `BrowserModel` | `@Observable`: current URL, back/forward history, items, sort column and direction, filter text, view mode, zoom, selection. Loads listings on a background task and discards stale results if the folder changed meanwhile |
| `Sidebar` | Tree rooted at: Home, Desktop, Documents, Downloads, Applications, then mounted volumes. Folders expand lazily (children loaded on first expand). The current folder is highlighted and its ancestors auto-expand |
| `AddressBar` | Shows breadcrumbs. Click empty space or press Cmd+L to switch to an editable text field with the full path selected; Return resolves via `AddressPath` (invalid path shakes and keeps the old folder); Esc cancels |
| `DetailsView` | Columns Name (with icon), Date modified, Size, Kind. Click a header to sort, click again to reverse. Multi-select, drag to reorder columns |
| `IconView` | Grid of icons with names beneath. Zoom slider from 32 pt to 256 pt (also Cmd + scroll wheel and pinch). Thumbnails from `QLThumbnailGenerator`, falling back to the file-type icon, loaded lazily for visible cells only and cached |
| `FilterField` | Toolbar search field. Filters the current folder as you type (no Spotlight) |

### Behaviours
- View mode (details or icons), sort column and zoom are remembered between launches via `UserDefaults`.
- Hidden files and extensions are always shown in Stage A.
- Return opens the selection (folders navigate, files open in the default app). F2 renames in place. Cmd+Delete moves to Trash. Space does nothing special.
- Shortcuts: Cmd+C, Cmd+X, Cmd+V; Cmd+Up parent folder; Cmd+[ back, Cmd+] forward; Cmd+L address bar; Cmd+F filter; Cmd+1 details, Cmd+2 icons; Cmd+A select all.
- The folder is not watched for changes in Stage A. It reloads after every operation the app performs and on Cmd+R.

## Errors
- Unreadable folder (permissions): the list shows a message ("Can't open this folder. macOS may need you to allow access in System Settings > Privacy & Security > Files and Folders."). The app never changes system settings.
- A failed move, copy, rename or trash lists which files failed and why. Files that succeeded stay done.
- Folder deleted while open: show an empty list with "This folder no longer exists" and enable the parent button.

## Testing
- `swift test` for `FilesCore`, using temporary folders: listing (hidden files included, folders flagged), `Sorter` (folders first, numeric-aware, accent-insensitive, both directions), `Filter` (empty, whitespace, accents), `AddressPath` (`~`, quotes, trailing slash, missing folder, breadcrumbs for `/`), `FileOps` (no overwrite, unique names, partial failure continues, folder-into-itself refused), `FileClipboard` (cut then paste moves; cut, then another copy, then paste copies; same-folder cut is a no-op; same-folder copy makes `name copy`).
- Manual checklist for the views: open a 10,000-file folder and scroll, sort each column, zoom the icons, Cut and Paste across folders, edit the address, filter, resize the window, keyboard shortcuts.

## Known ceilings
- No folder watching, so changes made by other apps appear after Cmd+R or the next navigation.
- Very large folders (100k+ files) load all at once; paging comes if that proves slow.
