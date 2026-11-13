# Grove Explorer · a file browser with two panes and tabs, in the Grove look

**Status:** design for review, 2026-11-12
**Builds on:** [2026-11-10-grove-themes-gui-design.md](2026-11-10-grove-themes-gui-design.md) (the app pattern), the shared `GroveUI` library, [2026-11-11-grove-menu-design.md](2026-11-11-grove-menu-design.md) (its row in the Grove menu)
**Comes before:** stages 3 to 5 of Grove Explorer (§3), each with its own spec
**Mock-ups:** `artifacts/grove-explorer/mockups/` (private), dark-medium and light-medium; the owner chose from them on 2026-11-12 (§2)

## 1. Goal

Grove Explorer is the app for looking after files in Project Grove: what Finder's windows do, with two panes side by side, tabs in each, the keyboard first, and the Grove look in all six schemes. Finder stays installed and keeps the desktop and the Trash.

This spec is the first build: the browser, the two panes and the tabs. It is usable every day on its own.

**Success looks like this:**
- After `grove install`, Grove Explorer is in `~/Applications`, in the Grove Launcher and in the Grove menu, and opens on the Home folder in a tiled window.
- Everything in §7's key table works without the mouse, and a person who knows Finder's keys needs to learn only the ones for panes and tabs.
- Copying a folder of several GB from one pane to the other shows progress, can be cancelled, asks once about a name that already exists, and ⌘Z puts everything back.
- A folder with 50,000 items opens, scrolls and sorts without a visible pause.
- A file created, renamed or removed by another program appears, changes or goes within a second.
- Quitting and reopening brings back the same panes, tabs and folders.
- It looks right in a dark and a light scheme, and follows a scheme switch while open.
- `grove check` reports `94-explorer-app` ok.

## 2. Decisions

All chosen by the owner on 2026-11-12, from options put to him.

| Topic | Decision | Why |
| --- | --- | --- |
| First build | The browser plus two panes and tabs | Panes and tabs shape the window; designing it without them means redoing it. |
| Panes and tabs | One or two panes; each pane has its own tabs | One side can stay put while the other moves through its tabs; copy and move go from the active pane to the other. |
| Keyboard | Finder's keys, plus Grove's for panes and tabs. No modes | Nothing to unlearn; typing a letter still jumps to a file. |
| Views | List view only: Name, Size, Date Modified, Kind | The owner's Finder is set to list view everywhere. One view done well. |
| File operations | Background queue with progress and cancel; a prompt for name conflicts with "apply to all"; undo; drag and drop between panes and with other apps | Chosen as "full and safe". |
| Deleting | Always the system Trash, never a direct delete | Anything removed can be put back from Finder. |
| Icons | Grove Icons where the set has one; one Grove-drawn folder; the real macOS icon for apps, disks and unknown types | An app should still look like itself. |
| Window | Tiled like any other app; no AeroSpace float rule | Two panes want the width. |
| Window edges | The sidebar and panes run to the window's edge, 1 pt lines between; no `GroveWindow.margin` | From the mock-ups: a margin costs 48 pt of width and frames the panes inside the frame. The one Grove window without the margin. |
| Tabs and path | Two rows of 32 pt: the tab strip, then the path bar | In one row the tabs are cut in a narrow pane. |
| Active pane | The 1 pt line over its tab strip is green; the other pane's selection is quieter | One line, no new shape. A green outline round the pane would read as the focus box. |
| Sidebar | Sections with fine-print captions (Favourites, iCloud, Locations); folders in one colour | Colour per place would be colour without a meaning. |
| Rows | 24 pt, as a sidebar row and a tab; name at 12 pt, the other columns at 11 pt in the quiet colour | One rhythm in the window (drawn as the recommended option; not picked apart from the others). |
| Folder icon | Solid, in the palette's blue | The colour a terminal lists directories in (drawn as the recommended option). |
| Kind of app | An ordinary app that is opened and quit, in ⌘Tab like any other; no menu-bar item, no login agent | It has nothing to do while closed. |

Taken from the owner's recorded Finder setup (`artifacts/finder-changes.md`) as the defaults: new windows on Home; folders on top; all extensions shown; folder sizes calculated; path bar and status bar always there; the filter looks in the current folder; sidebar favourites Applications, Home, Developer, Documents, Downloads; iCloud Drive; disks.

## 3. Out of scope

Later stages, each its own spec:

- **Stage 3:** search beyond the current folder, a preview pane, an icon grid, tags, batch rename, compress and expand.
- **Stage 4:** SSH, a remote machine browsed like a folder.
- **Stage 5:** becoming the default file viewer (so "Show in Finder" in other apps opens Grove Explorer), "Open With" defaults.

Not planned: browsing the Trash (the sidebar's Trash row opens Finder's), the desktop's icons, AirDrop, a Yazi-style key map, a floating quick window, several windows (one window in this build; ⌘N is not bound).

## 4. Pieces

```
grove-explorer/
  deps/grove-themes -> ../../grove-themes/app      (symlink, as grove-keys has)
  app/
    Package.swift
    Sources/
      GroveExplorerCore/     pure logic, no AppKit
      GroveExplorer/         the app: window, panes, list, operations' UI
    Tests/GroveExplorerCoreTests/
grove-dotfiles/
  modules/94-explorer-app/module.sh
  config/grove-explorer/explorer.toml               (tracked defaults)
  tests/modules_explorer_app.bats
```

`GroveExplorerCore` holds everything that can be tested without a window:

| Unit | Does | Depends on |
| --- | --- | --- |
| `Entry` | One item of a folder: name, kind, size, dates, flags (folder, package, hidden, alias) | – |
| `FolderReader` | Lists a folder into entries, in batches, off the main thread | Foundation |
| `FolderWatcher` | Tells when a folder's contents changed (FSEvents), coalesced | CoreServices |
| `Sorting` | Orders entries by a column and direction, folders on top, names compared as Finder does (numbers by value, case and accents ignored) | – |
| `Filter` | The ⌘F filter and type-to-jump matching | – |
| `SizeCalculator` | A folder's total size, cancellable, cached per folder until it changes | Foundation |
| `PathBar` | A path as clickable parts; a typed path with `~` and relative parts resolved | – |
| `Tabs`, `Panes` | The window's state: panes, their tabs, each tab's folder, history, selection, sort; which is active | – |
| `Session` | That state to and from a file | – |
| `Operation`, `OperationQueue` | Copy, move, duplicate, rename, new folder, trash as values; run one after the other with progress; cancellable | Foundation |
| `Conflict` | What to do when the name exists: replace, keep both (the next free "name 2.ext"), skip; "apply to all" | – |
| `Undo` | The inverse of each finished operation, and whether it can still be undone | – |
| `Favourites`, `ExplorerConfig` | `explorer.toml` and the user's `explorer.local.toml` | the TOML reader in `GroveThemesCore`/`GroveKeysCore` (moved to a shared target if needed) |
| `IconKind` | Which icon an entry gets: a Grove Icons glyph and colour, the Grove folder (and which variant), or "ask macOS" | the Grove Icons map |

The app target draws and wires: the window (`GroveWindowHeader`), the sidebar, the panes, the list, the status bar, the prompts, Quick Look, drag and drop, the menus.

## 5. The window

One window, tiled by AeroSpace. From left to right: the sidebar, then one pane or two.

**Header** (`GroveWindowHeader`): the name on the window buttons' line; in the middle back and forward for the active pane; trailing, the one-pane/two-pane switch (two icon segments). Below it the sidebar and the panes fill the window to its edges, divided by 1 pt lines.

**Sidebar** (fixed width; it becomes a 48 pt rail of icons when the panes would otherwise be under 430 pt each, and ⌘⌥S hides or shows it):
- *Favourites:* from the config (§9). Drag a folder onto the sidebar to add one; drag a row out to remove it. Both write `explorer.local.toml`.
- *iCloud:* iCloud Drive when it exists.
- *Cloud providers* (added 2026-11-13): below iCloud, one section per provider in `~/Library/CloudStorage` (Apple's File Provider), under the provider's name ("OneDrive"), a row per account: `OneDrive-Personal` reads "OneDrive", `OneDrive-Contoso` "OneDrive - Contoso"; `GoogleDrive-…`, `Dropbox`, `Box-Box` get their own headers. The names are worked out from the folder's name (the system's display name says "OneDrive-Personal"); the icon is the plain cloud. CloudStorage is watched, so a provider installed or removed appears or goes without a relaunch; a provider's folder not yet readable still has its row.
- The lit row is the deepest place above the active pane's folder: iCloud Drive and a provider's folder win over Home.
- *Locations:* mounted volumes, each with an eject button where it can be ejected; they come and go live.
- *Trash* at the bottom: opens Finder's Trash.
- A click opens the place in the active pane's current tab; ⌘-click in a new tab; a drop on a row copies or moves there.

**A pane**, top to bottom:
1. *Tab strip* (32 pt). The current tab is a pill in the selected fill. The tab's title is the folder's name. "+" adds a tab on the same folder. A tab closes with its hover button or ⌘W; the last tab of a pane doesn't close. The active pane's strip carries a 1 pt green line; the other pane's does not, and its selection is drawn in the inactive-selection fill (§6).
2. *Path bar* (32 pt). The folders from the volume (or Home, shown as "Home") down to the current one, each a click. Inside a cloud place it starts there, with the sidebar's icon and name ("iCloud Drive › Notes", "OneDrive › Documents"); a tab on iCloud Drive's folder is titled "iCloud Drive". One rule in Core (`FolderName`) names folders for tabs, the path bar, VoiceOver and the status bar. ⌘L turns it into a text field with the full path selected; Tab completes the folder's name being typed (as far as the names that begin so agree), Return goes, Escape cancels, a path that doesn't exist marks the field red and stays.
3. *The list* (§6).
4. *Status bar.* "212 items" or "3 of 212 selected · 48.2 MB"; the volume's free space at the right (left out under 640 pt). While operations run, in the target pane's bar: the current one's words ("Copying 1,204 items to Downloads"), a meter, and a cancel button. After one finishes: what it did and "⌘Z to undo", for a few seconds.

With two panes the split is even; the divider can be dragged, and a double-click evens it.

## 6. The list

An AppKit table (`NSTableView` through `NSViewRepresentable`) under the Grove skin: the `Table` of SwiftUI is not used because of very large folders, type-to-jump, inline rename and drag and drop of files. Its header, rows, selection and focus are drawn with the tokens; the table gives scrolling, selection maths, column resizing and reuse of rows.

- **Columns:** Name (icon and name), Size, Date Modified, Kind. Sizes are right-aligned in tabular figures. Name takes the width up to 560 pt; beyond that the other columns follow it and the rest of the row is empty, so a wide single pane doesn't put a screen's width between a name and its size. By the pane's own width: under 640 pt Kind goes and dates shorten ("Today 09:41", "9 Nov 2026"); under 430 pt the date goes too. A long name is cut in the middle, keeping its extension. A symbolic link's name is followed, 8 pt on, by "→" and its target as the link stores it (`readlink`, home written `~` when absolute and inside it; relative stays relative), in the quiet colour, or orange ink after an orange warning mark (`GroveIcon.warning`, the mark carrying the colour in light) with Kind "Broken link" when it leads nowhere (Kind "Symbolic link" otherwise, never "Alias"); the target is cut in its middle, then dropped, before the name is cut, and sorting, the filter and rename use the name only.
- **Rows:** 24 pt. Selected rows that touch are drawn as one shape.
- **Fills:** a list has the pointer and a selection at once, in two panes, so it needs three fills that can be told apart in every scheme, in this order of strength: the active pane's selection, the inactive pane's selection, the row under the pointer. The mock-ups showed today's roles don't give that (in dark the hover and the inactive selection are one colour; in light the hover is stronger than the selection). `GroveUI` gains list roles for the three (`listSelected`, `listSelectedInactive`, `listHover`), picked from each palette and checked in renders of all six schemes, with the selection always the strongest; hidden items get a `hiddenInk` role instead of an opacity.
- **Sorting:** a click on a header sorts by it, a second click reverses; folders stay on top in either direction (Finder's "keep folders on top"). Each tab remembers its sort. Sorting and filtering run off the main thread. When a tab comes to show a folder another tab or pane already lists, a folder of up to 10,000 entries is arranged for it at once; a larger one keeps its rows in the old order (or shows none, when the items themselves differ) until its own order is ready, so the window never waits for a sort.
- **Between two folders:** from the moment a tab goes to another folder until that folder is read, the list is blank (not "empty") and nothing is selected: no command acts on rows of the folder just left.
- **Sizes:** files show their size; folders show a quiet "···" until `SizeCalculator` has the total, then the total. Totals are calculated for the folders in view first, a few at a time, and kept until the folder changes. Packages (apps, bundles) count as files.
- **Dates:** as Finder writes them: "Today at 09:41", "Yesterday at 18:02", then the date and time, in the user's locale.
- **Names:** extensions always shown. Hidden items are left out until ⌘⇧. shows them, with the name in the quiet colour and the icon dimmed. The setting is per window and remembered.
- **Selection:** click, ⇧-click, ⌘-click, ⇧-arrows, ⌘A. Typing letters selects the first name that starts with them (a second's pause starts again).
- **Opening:** Return renames (Finder's rule); ⌘↓ or ⌘O or a double-click opens: a folder in this tab, a file in its default app, a package as its app. ⌘-double-click a folder: a new tab.
- **Rename:** in place, the name without its extension selected. The field takes a 1 pt green line (as the path and filter fields do), not the focus box. Return commits, Escape cancels; an empty name, a "/" or a name that exists marks the field red with one line of reason beneath.
- **Filter (⌘F):** a `FilterField` above the list; the list shows the names containing every typed word; the status bar says "4 of 212". In the field ↑ and ↓ move the list's selection and Return opens what is selected (it does not rename: the keyboard is in the field to find a thing and go to it). Escape clears the filter and gives the focus back to the list, from the field and from the filtered list alike.
- **Live:** `FolderWatcher` keeps the list current. The selection and scroll position survive a refresh.
- **Empty and unreadable:** an empty folder says so. A folder macOS won't let the app read says which permission is missing and has a button for Privacy Settings.

## 7. Keys

Finder's, unchanged:

| Key | Does |
| --- | --- |
| ↑ ↓, ⇧↑ ⇧↓, Home, End, Page Up/Down | The arrows move and extend the selection; Home, End, Page Up and Page Down scroll the list and leave the selection where it is (Finder's rule) |
| ⌘↓, ⌘O | Open |
| ⌘↑ | The enclosing folder |
| ⌘[ , ⌘] | Back, forward (per tab) |
| Return | Rename |
| Space | Quick Look (arrows move through the selection while it is up) |
| ⌘C, ⌘V | Copy the selection; paste copies here |
| ⌥⌘V | Paste moves here |
| ⌘D | Duplicate |
| ⌘⌫ | Move to Trash |
| ⌘⇧N | New folder, named in place |
| ⌘⇧. | Show or hide hidden items |
| ⌘Z, ⌘⇧Z | Undo, redo |
| ⌘A | Select all |
| ⌘⇧G, ⌘L | Go to a path |
| ⌘⇧H, ⌘⇧D, ⌘⇧O, ⌘⌥L, ⌘⇧A | Home, Desktop, Documents, Downloads, Applications |
| ⌘I | Finder's Get Info for the selection, or for the folder itself when nothing is selected; ten items at most at a time, more is refused with a sentence (macOS asks once to let Grove Explorer control Finder) |
| ⌃⌥⌘1, ⌃⌥⌘2, ⌃⌥⌘5, ⌃⌥⌘6 | Sort by Name, Kind, Date Modified, Size, as a click on the column's title (again: the other way round) |
| Letters | Jump to a name |

Grove's:

| Key | Does |
| --- | --- |
| Tab | The other pane (opens it if there is one pane) |
| ⌘\ | One pane / two panes |
| ⌘T, ⌘W | New tab, close tab |
| ⌃Tab, ⌃⇧Tab, ⌘1…⌘9 | Next, previous, the nth tab of the active pane |
| F5 | Copy the selection to the other pane's folder |
| F6 | Move it there |
| ⌘F | Filter this folder |
| ⌘⌥S | Show or hide the sidebar |
| ⌥⌘← | The keyboard to the sidebar: ↑ ↓ move, Return opens the place, → or Esc returns to the list |
| → | Open the selected folder in place (§16; this key and the next three act with the keyboard in a list and no field up) |
| ← | Close the selected folder in place, or, on a file or a closed folder, go to its parent row (§16) |
| ⌥→ | Open the selected folder and everything inside it, up to 10,000 rows (§16) |
| ⌥← | Close the selected folder and everything inside it (§16) |
| ⌘⌥T | Open this folder in Ghostty |
| ⌘⌥C | Copy the selection's paths |
| ⌃Return, ⇧F10 | The right-click menu, by keyboard: of the selection, at its row; while the keyboard is in the sidebar, of the row it is on (Open in New Tab, Remove from Sidebar, Eject) |
| ⌘E | Eject the disk the keyboard is on, with the keyboard in the sidebar (⌥⌘←); with the keyboard in a list it does nothing. A disk a copy or a move is using is not ejected, by key or by pointer: its row says why. The other way round, while a disk is being ejected no command onto it is begun (nor an undo or a redo): the status bar says so |
| ⌘. | Cancel the operation that is running, with the keyboard in a list or the sidebar; in the path or the filter field it does what Esc does there; in the conflict prompt it is Cancel |
| ⌘⇧F | Show or hide the items the last operation could not do (↑ ↓ scroll a long list, Esc closes it) |
| Return | In a folder macOS won't let the app read (nothing to rename there): Open Privacy Settings |

Everything in the window but dragging the line between the panes has a key: the tabs' "+" and close marks are ⌘T and ⌘W, the path bar's parts ⌘↑ and ⌘L, the header's arrows ⌘[ and ⌘], its pane switch ⌘\, the columns' titles ⌃⌥⌘1, 2, 5 and 6. Tab and ⇧Tab stay the lists' ("the other pane") and never walk the window's controls.

The right-click menu is the system's (`.contextMenu`): its own font and the Mac's accent colour, as every native menu in Grove. Rows: Open, Open With ▸, Quick Look, Rename, Duplicate, Copy Path, Move to Trash, Show in Finder, Open in Ghostty; on empty space: New Folder, Paste, Show Hidden Items. The app's menu bar menus (reached through Grove's Global Menu) carry the same commands with their keys.

## 8. File operations

- **A value, then a run.** Each command makes an `Operation` (what, which items, where to). `OperationQueue` runs them one after the other on its own queue, with progress by bytes for copies and by items otherwise.
- **Copy and move.** A move on the same volume is a rename (instant); across volumes it is a copy then a removal of the source once the copy is whole. A copy is written to a temporary name beside the target and renamed when complete, so a cancelled or failed copy leaves nothing half-written. Copies keep dates, permissions, extended attributes and tags (`FileManager`/`copyfile`).
- **Conflicts.** Before anything is written, the names that already exist at the target are found. If there are any, one prompt: the first name, the size and date of the item there and of the one coming, **Skip**, **Replace**, **Keep Both** (the default button: it loses nothing), a box "Apply to all (N more)", and Cancel (the whole operation). It is a card over the scrimmed window: an opaque fill, radius 10, a 1 pt line, no shadow. Replacing a folder replaces it whole, as Finder does; it does not merge. A replaced item goes to the Trash, so the replace can be undone.
- **Cancel.** Stops after the current file; what was already copied stays and the status bar says how much.
- **Errors.** One failed item doesn't stop the rest. At the end the status bar says "3 items could not be copied" in the marked style, with a click showing which and why.
- **Trash.** `FileManager.trashItem`; the status bar says what went. No confirmation, as in Finder.
- **Undo.** Every finished operation records its inverse: copies → the copies go to the Trash; moves → moved back; rename → the old name; new folder → to the Trash if still empty; trash → put back from the Trash to where it was; a replace → the replaced item returns. ⌘Z undoes the latest, ⌘⇧Z redoes. An undo that can no longer be done (the item changed or went since) says so and does nothing. The stack is per window and is not kept across launches.
- **Drag and drop.** Within and between panes: a drop on a folder row (marked with the hover fill and a 1 pt green line) or on a pane's empty space moves on the same volume and copies across volumes; ⌥ forces copy, ⌘ forces move (Finder's rules). A drop on a tab goes to that tab's folder, and a drag held over a tab that is not showing for a moment brings it forward (spring-loading), so the drop can go on to a row of it. To and from other apps through the file pasteboard types. A drag shows the system's drag image with a count. Drops go through the same queue, prompt and undo.
- **Quitting waits for the file in hand.** ⌘Q, or the window's red button, while a command is in hand: the run is cancelled and stops after the file it is on (its partial copy is removed), an open prompt is answered with Cancel, the commands still waiting are dropped, and the app quits when the one in hand has ended. The window stays meanwhile, and its status bar says "Finishing the current file before quitting…" from the first moment to the last.
- **ExFAT and FAT.** Such a volume has no extended attributes: macOS keeps a file's in a hidden companion beside it, `._name` for `name`, which it writes (over whatever has that name) whenever `name` is made, renamed or copied there, and carries along with it. So there: a companion (a `._name` beside its `name` that begins as macOS's attribute files do) is not listed as an item of a folder being copied or moved, since it travels with its file. A file of the user's own that is named `._x` is not copied or moved to where an `x` is, or arrives with it: that item fails with "it can't be kept beside “x” on this disk", and of such a pair inside a folder the `._x` is the one left out. And a name `x` is not given (by a copy, a move, a rename or a new folder) where a `._x` of the user's own already is: "“._x” is in the way on this disk". Names are compared there as the volume does ("X.TXT" is "x.txt"). Nothing is written over in any of these cases.
- **The clipboard.** ⌘C puts file URLs on the general pasteboard, so paste works to and from Finder and other apps.

## 9. Config and state

`~/.config/grove-explorer/explorer.toml` (tracked defaults, linked like the other configs), then `explorer.local.toml` beside it (the user's, not tracked; the app writes only this one):

```toml
[general]
start = "~"                 # where a new window opens
show_hidden = false
two_panes = false

[favourites.applications]
path = "/Applications"

[favourites.home]
path = "~"
title = "Home"

[favourites.developer]
path = "~/Developer"

[favourites.documents]
path = "~/Documents"

[favourites.downloads]
path = "~/Downloads"
```

Favourites are tables in file order, as the Grove menu's rows are (Grove's TOML reader has no arrays of tables).

A favourite whose folder doesn't exist is left out. Any `[favourites.*]` table in the local file replaces the tracked list.

The session (panes, tabs, each tab's folder and sort, the sidebar's and divider's widths) is saved to `$GROVE_STATE/explorer-session.json` when it changes and at quit, and read at launch. A folder that no longer exists falls back to its nearest existing parent.

Links: `groveexplorer://open?path=<percent-encoded path>` opens that folder in a new tab of the active pane (and selects the item when the path is a file) and brings the window forward. The Grove menu gains a row "Files" that opens the app.

## 10. Icons

`IconKind` decides, in this order:
1. A folder: the Grove folder, one solid shape in the palette's blue (a `Shape`, as `PineShape` is), with a small mark cut out of it for the known ones (Home, Developer, Documents, Downloads, Applications, Desktop). In the mock-ups the marks for Developer and Documents were blobs at 16 pt: each mark is redrawn as a few strokes on the pixel grid and accepted only when it reads at list size in a render. A package is not a folder.
2. An app, a volume, an alias to one, or a file with its own custom icon: the macOS icon (`NSWorkspace.icon(forFile:)`), cached per path.
3. A name or extension Grove Icons knows: its glyph in its colour, dark or light set by the scheme. One rule of Grove Explorer's own on top of the set: a file's extension wins over its name, so README.md, CHANGELOG.md and notes.md all get the Markdown glyph (the set gives each a different one by name, which reads as noise in a list). A disk image keeps its macOS icon. The map and the font are the ones the VS Code theme uses (`grove-dotfiles/config/vscode/grove-icons/`); the module copies them into the app's resources, and the font is registered for the process only.
4. Anything else: the macOS icon for its type, cached per extension.

Icons are 16 pt in the list and the sidebar.

## 11. Permissions

Not sandboxed. macOS asks once each for Desktop, Documents, Downloads, iCloud Drive, removable and network volumes the first time a folder there is read; the usage strings in `Info.plist` say why in a sentence. Refused, that folder shows the "needs permission" state (§6). Full Disk Access is not asked for; with it, protected folders (Mail, Safari, the Trash) can be read like any other.

The bundle is signed with the "Grove Code Signing" certificate, as the other apps are, so the permissions survive rebuilds.

## 12. grove module `94-explorer-app`

As `96-keys-app` and `97-themes-app`, without the login agent:
- **check:** the app is in `~/Applications/Grove Explorer.app`, built from the current sources (a stamp of the source tree's hash in the bundle), signed, its config linked.
- **apply:** `swift build -c release`, assemble the bundle (Info.plist with the bundle id `com.projectgrove.explorer`, the URL scheme, the usage strings; no `LSUIElement`, so it is in ⌘Tab), copy the Grove Icons font and map, sign, install; if the app is running, tell the user to reopen it rather than killing it.
- **remove:** grove has no uninstaller. To remove the app, delete `~/Applications/Grove Explorer.app` by hand (manual chapter 7); the config and the session stay. The module keeps a tested `remove` function that does this, for a later command; nothing calls it yet.

## 13. Errors

| Situation | What happens |
| --- | --- |
| A folder can't be read (permission) | The "needs permission" state with the Privacy Settings button |
| A folder went away while shown | The tab moves to the nearest existing parent; the status bar says so |
| A volume is ejected | Its tabs move to Home; an eject that fails (files in use) says which app holds it when macOS tells |
| The target disk is full | The operation stops; what was copied stays; the status bar says how much room was missing |
| A name can't be used | The rename field turns red with the reason; nothing is changed |
| `explorer.toml` can't be parsed | The built-in defaults are used and a tinted banner at the top of the window names the line |
| The session file is damaged | Ignored; the window opens on Home |
| An undo is no longer possible | "Can't undo: <name> has changed", nothing is touched |

## 14. Testing

- **Core, unit tests** (Swift Testing): sorting against Finder's order for a fixture of awkward names; filter and type-to-jump; path parsing; tabs and panes state changes; session round-trip; conflict naming ("name 2.ext", "name 3.ext"); undo's inverses; config merge; `IconKind` for a table of names.
- **Core, against real temporary folders:** reading (10 and 50,000 items, hidden files, packages, aliases, unreadable folders); the watcher (create, rename, delete seen within a second); every operation, its cancel, its failure in the middle, its conflict choices and its undo and redo; copy across two disk images for the cross-volume paths; attributes and tags preserved.
- **Performance, as tests with a limit:** list and sort 50,000 entries; size of a tree of 20,000 files.
- **Views:** a `--render <state> <out.png> [scheme]` one-shot, as Grove Keys has for its panels, drawing the window from sample data in dark-medium and light-medium; compared with the mock-ups by eye.
- **Installer:** bats for the module's check, apply (with fakes) and remove.
- **By hand, listed in the plan:** the keys, drag and drop with Finder and other apps, Quick Look, the permission prompts, ejecting, a scheme switch while open, tiling beside another window.

## 15. Build order

For the plan: (1) Core reading, sorting and the list in one pane, read-only; (2) navigation, path bar, sidebar, tabs, the second pane, the session; (3) operations, conflicts, undo, the clipboard; (4) drag and drop, Quick Look, the context menu; (5) icons; (6) the module, the Grove menu row, the manual chapter. Each step ends installable.

## 16. Folders that open in place (added 2026-11-13)

Asked for by the owner after the first live run, and chosen from options put to him: folders expand in place in the list, as in Finder's list view, and the arrows are always there (no mode, no switch). Mock-ups: `artifacts/grove-explorer/mockups/tree-*.png`.

**Look** (chosen by the owner from the mock-ups, 2026-11-13). A folder that has something in it has a chevron before its icon (`GroveIcon`: chevron.right closed, chevron.down open; 12 pt, quiet colour, the text colour while the pointer is on it). The chevron sits in a gutter of its own, 16 pt wide (a 12 pt box and 4 pt), which every row keeps, so all icons are in one column and all names in another; the header's "Name" stays at the pane's edge. The chevron's hit area is the whole gutter cell (16 × 24 pt). A folder's contents are listed beneath it, the name indented 16 pt per level (the gutter's width, so a child's chevron sits under its parent's icon); the indent is never capped: a deep name in a narrow pane is cut in the middle like any long name. Size, Date Modified and Kind stay in their columns. Rows stay 24 pt; fills and the drop line run the row's whole width at every level.

**Which folders have a chevron.** Only a folder with at least one item that would show (hidden items count only while hidden items are shown). An empty folder has none, and gains one when something arrives in it. No chevron on files, on packages (apps, bundles), on links to folders, or on a folder the app can't read (its size reads "--"). Whether a folder has something in it is found by looking into it, off the main thread, for the folders in view first; until that is known the row has no chevron. Looking into Desktop, Documents, Downloads and the like is what makes macOS ask its permission questions; the owner chose to allow those prompts (2026-11-13), cloud folders included, and protected folders are not skipped.

**Opening and closing.** A click on the arrow; → on the selected folder opens it, ← closes it; ← on a file or a closed folder selects its parent row; ⌥→ or ⌥-click on the arrow opens a folder and everything inside it, ⌥← closes it and everything inside. ⌘↓, ⌘O and a double-click still go INTO the folder (the tab navigates), as before. An opened folder that is still being read shows one quiet "···" row beneath it, at the child's icon position, the other columns empty; it is not selectable, not counted in the status bar, and the arrow keys pass over it. A folder that turns out empty when opened closes again and loses its chevron.

**Order.** Each folder's contents are sorted among themselves by the tab's column and direction, folders on top at every level; a child never leaves its parent.

**Filter (⌘F).** It looks through every row that is showing, opened folders' contents included. A row that matches keeps its ancestors showing, their names in the quiet colour and their icons and chevrons unchanged (they are context, not matches; dimming the icon would make them look hidden). An ancestor kept as context can be selected and acted on like any row, and its chevron still closes it (which hides the matches inside). Closed, it stays as a closed context row until the filter's words change or it is cleared (the owner, 2026-11-13), so its chevron opens it again and the matches inside come back; the audit closes and reopens one under the filter. A context row is never taken for what it hides: ⌘A selects the matches only; a context folder selected together with rows inside it (a ⇧-range) gives those rows to an operation, not itself (selected alone, it is a folder like any); closing one does not select it in place of what was selected inside; and the status bar counts the selection as the operations take it. The status bar counts matches against the rows that would show without the filter ("5 of 33"). The filter never opens a folder by itself.

**Selection and commands.** They act on the rows that are showing, at any depth; ⌘A selects all showing rows. When a folder and items inside it are both selected, an operation takes the folder once (items whose ancestor is also selected are left out, so nothing is copied twice or moved out from under itself). Type-to-jump looks through all showing rows.

**Where things go.** Paste, new folder, F5/F6's target and a drop on a pane's empty space go to the tab's folder, as in Finder. A drop on an opened or closed folder's row goes into that folder. New folder and rename-in-place then show the row where it belongs in the tree.

**Live.** Each opened folder is watched like the tab's own folder; a change inside appears within a second. An opened folder that goes away closes (its rows go); one that is renamed keeps its place and its opened state when the rename was made in the app.

**Sizes.** As before, for every showing folder and package. "--" is only for a folder that can't be read: a walk cancelled by a change in the folder keeps the quiet "···" until the folder is quiet and the total comes.

**Remembered.** Which folders are open is kept per tab, survives a refresh and a sort, is kept when the tab navigates away and back (per folder visited, bounded), and is saved in the session.

**Limits.** ⌥→ stops opening when the tab would show more than 10,000 rows and says so in the status bar. A link loop can't be opened (links to folders have no arrow).

**Status bar.** "212 items" counts showing rows; with folders open: "212 items · 3 folders open" (a folder still being read counts as open). With a selection: "2 of 19 selected · 350 KB", without the folders-open count; a folder and items inside it selected together count the folder's size once.

**VoiceOver.** A row says its level and, for a folder, "open" or "closed"; the arrow is the row's expand/collapse action (disclosure), not a separate element. As built: the list is an outline to VoiceOver, as an `NSOutlineView` is (`AXOutline`; each row `AXOutlineRow` with its `AXDisclosureLevel` from 0, `AXDisclosing` for an open folder, settable on a folder with an arrow alone, which is how VoiceOver opens and closes it, `AXDisclosedByRow` and `AXDisclosedRows`); a loading line is no row, and the rows are numbered without it. A row inside a folder that is closed keeps its element while the folder is a row, so opened again it is the same row. `--audit-accessibility` checks all of it through the accessibility server, in the `tree` state with a folder closed and opened again.

**Safety rules that carry over unchanged.** Commands act only on rows the user can see; a pane or an opened folder whose contents have not arrived has no rows; operations are values captured at the keypress; every change to files goes through the single run path.

**Keys, in §7's Grove table** (the Core test that parses §7 pins its rows, so they were added together with the code): → open the selected folder in place · ← close it, or go to its parent row · ⌥→ open it and everything inside · ⌥← close it and everything inside.

**In the code.** The rows a tab shows (which entries, at what depth, in what order, under which filter, with which ancestors kept) are one pure function in Core over the folders' listings and the set of open folders, with tests; the rows-state machine (§6, `Arrangement`) decides over that result as it does today over a flat list.
