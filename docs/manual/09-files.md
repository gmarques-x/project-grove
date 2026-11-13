# 9. Files

[Contents](README.md) · Previous: [Coming from stock macOS](08-coming-from-stock-macos.md)

Grove Explorer is Grove's file browser: a list of a folder with one pane or two, tabs in each, Finder's keys, and copying and moving that can be undone. Finder is still there and unchanged; use whichever suits the job.

## Open it

| Do this | To |
| --- | --- |
| Pine › Files | Open Grove Explorer, or bring its window forward |
| ⌘Space, type `files` or `explorer`, ↩ | The same, from the Grove Launcher (the menu's row, or the app itself) |
| `open -a 'Grove Explorer'` | The same, from a terminal |

It is an ordinary app: it is in ⌘Tab, it does not start at login, and closing its window quits it. Its window is tiled like any other (Finder's float). When you open it again, the panes, tabs, folders and sort orders are as you left them.

A link opens a folder too: `groveexplorer://open?path=` followed by the path (percent-encoded: a space is `%20`) opens that folder in a new tab and brings the window forward; a file's path opens its folder with the file selected. From a terminal: `open 'groveexplorer://open?path=/Users/you/Documents'`.

## The window

From left to right: the sidebar, then one pane or two.

| Part | What it is | Click |
| --- | --- | --- |
| Header | The app's name, back and forward arrows for the active pane, and the one-pane / two-pane switch at the right | The arrows go back and forward; the switch shows or hides the second pane |
| Sidebar | **Favourites** (your folders), **iCloud Drive** when you use it, **Locations** (every disk, with an eject button where it can be ejected), and **Trash** at the bottom | Opens the place in the current tab; ⌘-click opens it in a new tab. Trash opens Finder's Trash |
| Tab strip | One tab for each folder you have open in the pane; the active pane's strip has a green line | A tab shows it; "+" adds a tab on the same folder; the mark that appears under the pointer closes it |
| Path bar | The folders from the disk (or Home) down to the one you are in | A part goes to that folder |
| The list | Name, Size, Date Modified and Kind. Folders stay on top. A folder shows `···` until its total size is known, and `--` if it can't be read. A folder with something in it has an arrow before its icon | A column's title sorts by it; again reverses. A double-click opens. The arrow opens the folder in place (see below) |
| Status bar | "212 items" ("212 items · 3 folders open" with folders open in place), or "3 of 212 selected · 48.2 MB", and the disk's free space at the right. While a copy runs: its words, a meter and Cancel | Cancel stops the copy after the file it is on |

In a narrow pane the Kind column goes first, then the date; in a narrow window the sidebar becomes a rail of icons. Drag the line between two panes to resize them; double-click it to make them even.

## Finder's keys

These do what they do in Finder.

| Press | To |
| --- | --- |
| ↑ ↓, ⇧↑ ⇧↓ | Move and extend the selection |
| Home, End, Page Up, Page Down | Scroll the list; the selection stays where it is |
| ⌘↓ or ⌘O | Open: a folder in this tab, a file in its app |
| ⌘↑ | Go to the enclosing folder |
| ⌘[ and ⌘] | Back and forward (each tab has its own history) |
| ↩ | Rename |
| Space | Quick Look (the arrows move through the selection while it is up) |
| ⌘C, ⌘V | Copy the selection; paste copies it here |
| ⌥⌘V | Paste moves it here |
| ⌘D | Duplicate |
| ⌘⌫ | Move to the Trash |
| ⌘⇧N | New folder, named in place |
| ⌘⇧. | Show or hide hidden items |
| ⌘Z, ⌘⇧Z | Undo, redo |
| ⌘A | Select all |
| ⌘⇧G or ⌘L | Go to a path |
| ⌘⇧H, ⌘⇧D, ⌘⇧O, ⌘⌥L, ⌘⇧A | Home, Desktop, Documents, Downloads, Applications |
| ⌘I | Finder's Get Info for the selection (macOS asks once to let Grove Explorer control Finder) |
| ⌃⌥⌘1, ⌃⌥⌘2, ⌃⌥⌘5, ⌃⌥⌘6 | Sort by Name, Kind, Date Modified, Size, like a click on the column's title (again: the other way round) |
| Letters | Jump to the first name that starts with them |

## Grove's keys

| Press | To |
| --- | --- |
| Tab or ⇧Tab | Go to the other pane (it opens the second pane if there is only one) |
| ⌘\ | Switch between one pane and two |
| ⌘T, ⌘W | New tab, close tab (a pane's last tab stays) |
| ⌃Tab, ⌃⇧Tab, ⌘1 … ⌘9 | The next tab, the previous one, the nth tab of the active pane |
| F5 | Copy the selection to the other pane's folder. On a laptop keyboard press fn with it (fn F5), unless System Settings › Keyboard has the F keys set as standard function keys |
| F6 | Move it there (fn F6 on a laptop keyboard, in the same way) |
| ⌘F | Filter this folder |
| ⌘⌥S | Show or hide the sidebar |
| ⌥⌘← | Take the keyboard to the sidebar: ↑ ↓ move, ↩ opens the place, → or Esc returns to the list |
| → | Open the selected folder in place (this key and the next three work with the keyboard in a list and no field open) |
| ← | Close the selected folder in place; on a file or a closed folder, go to the row of the folder it is in |
| ⌥→ | Open the selected folder and everything inside it, up to 10,000 rows |
| ⌥← | Close the selected folder and everything inside it |
| ⌘⌥T | Open this folder in Ghostty |
| ⌘⌥C | Copy the selection's paths |
| ⌃↩ or ⇧F10 | The right-click menu, by keyboard: of the selection, at its row; while the keyboard is in the sidebar, of the row it is on (Open in New Tab, Remove from Sidebar, Eject) |
| ⌘E | Eject the disk the keyboard is on, with the keyboard in the sidebar (⌥⌘←). With the keyboard in a list it does nothing |
| ⌘. | Cancel the copy or move that is running. In the path or the filter field it does what Esc does there; in the "name is taken" prompt it is Cancel |
| ⌘⇧F | Show or hide the items the last operation could not do (↑ ↓ scroll a long list, Esc closes it) |
| ↩ | In a folder macOS won't let the app read: Open Privacy Settings |

Everything in the window has a key except dragging the line between the panes. Tab never walks through the window's buttons; it always means "the other pane".

The same commands are in the app's menus (click the app's name in the bar, or Pine › Global Menu) and in the right-click menu: Open, Open With, Quick Look, Rename, Duplicate, Copy Path, Move to Trash, Show in Finder and Open in Ghostty on an item; New Folder, Paste and Show Hidden Items on empty space.

## Opening folders in place

A folder with something in it has an arrow before its icon. Click the arrow, or select the folder and press →, and its contents are listed beneath it, indented, without leaving the folder you are in; click it again, or press ←, to close it. Folders open inside open folders as deep as you like, and each folder's contents are sorted among themselves by the tab's column.

| Do this | To |
| --- | --- |
| Click the arrow, or → | Open the folder in place. While it is being read, one quiet `···` line shows beneath it |
| → on an open folder | Go to its first row |
| Click it again, or ← | Close it. What was open inside it is remembered for when you open it again |
| ← on a file or a closed folder | Go to the row of the folder it is in |
| ⌥-click the arrow, or ⌥→ | Open the folder and everything inside it. It stops at 10,000 rows, and the status bar says "Stopped at 10,000 rows" |
| ⌥-click an open arrow, or ⌥← | Close the folder and everything inside it, forgetting what was open there |
| ⌘↓, ⌘O or a double-click | Still go into the folder: the tab moves to it, as before |

An empty folder has no arrow and gets one when something arrives in it; files, apps and other packages, links to folders and folders the app can't read have none. A folder that turns out empty when opened closes again.

The open folders are watched like the one you are in: what another app adds, renames or deletes inside them shows within a second, and an open folder that is deleted closes. One you rename in Grove Explorer stays open. Each tab remembers which folders are open, also when you go elsewhere and come back, and after you quit.

**The filter** (⌘F) looks through every row that shows, open folders' contents included. A folder that holds a match stays as a row, its name in the quiet colour; it is there for context and is not counted ("5 of 33" counts the matches). Close it and it stays, closed, until you change or clear the filter; open it again and the matches inside come back. ⌘A selects only the matches, and a range you select across such a folder gives the commands the matches inside it, never the folder with everything else in it; a folder like that selected on its own is acted on as a folder. The filter never opens a folder by itself.

**Commands** act on the rows you can see, at any depth: ⌘A selects them all, and a folder selected together with something inside it is copied, moved or trashed once. **Where things go:** paste, ⌘⇧N, F5 and F6 and a drop on a pane's empty space go to the tab's folder, as in Finder; a drop on a folder's row, open or closed, goes into that folder. A new folder or a renamed item appears where it belongs in the tree.

**VoiceOver** reads a row inside an open folder with its level ("level 2"), and a folder as "open" or "closed"; VoiceOver's own open and close commands open and close it in place.

## Go to a path

Press ⌘L (or ⌘⇧G). The path bar becomes a text field with the full path selected. Type a path (`~` is your home folder), press Tab to complete a name, then ↩ to go; a file's path goes to its folder and selects the file. A path that does not exist turns the line red and stays so you can fix it. Esc cancels.

## Copy and move between panes

1. Press ⌘\ for two panes (or Tab, which opens the second one).
2. Go to the source folder in one pane and the target folder in the other. Tab switches between them.
3. Select the items and press **F5** to copy them to the other pane's folder, or **F6** to move them.

The other pane's status bar shows the progress and then what was done, with "⌘Z to undo" for a few seconds. A second command given meanwhile waits its turn. ⌘C and ⌘V (or ⌥⌘V to move) do the same job with one pane, and work to and from Finder and other apps.

Quitting waits for the file in hand: if you press ⌘Q or the red button while a copy or a move is running, it stops after the file it is on, the window stays with "Finishing the current file before quitting…" in the status bar, and the app quits when that file is done. What was still waiting is not done.

A copy is written under a temporary name and given its real name only when it is whole, so a cancelled or failed copy leaves nothing half-written. One item that fails does not stop the rest: the status bar says how many could not be done, in red; click it, or press ⌘⇧F, to see which and why.

## When a name is taken

If something with the same name is already at the target, one prompt appears before anything is written. It shows the size and date of the item there and of the one arriving.

| Choose | To |
| --- | --- |
| **Keep Both** (↩) | Keep the one there and give the new one the next free name (`notes 2.md`). Nothing is lost |
| **Replace** | Put the new one in its place. The old one goes to the Trash, so ⌘Z brings it back. A folder is replaced whole, not merged |
| **Skip** | Leave this one out and go on with the rest |
| **Cancel** (Esc or ⌘.) | Do none of it |

Tick "Apply to all" to answer once for every name that is taken.

## Undo

⌘Z undoes the last file command and ⌘⇧Z redoes it: a copy's copies go to the Trash, a move goes back, a rename gets its old name, a new folder goes to the Trash if it is still empty, a trashed item returns to where it was, and a replaced item comes back.

Moving to the Trash (⌘⌫) asks nothing, as in Finder; ⌘Z is the way back. In Grove Explorer nothing is deleted without a copy or a way back.

If an undo can no longer be done (the item has changed or gone since, the Trash was emptied, the disk was ejected), the status bar says so and nothing is touched. The undo list belongs to the window and is forgotten when you quit.

## Drag and drop

Drag items onto a folder's row, onto a pane's empty space, onto a tab, or onto a place in the sidebar. The target is marked with a green line while you are over it.

| Drag | Does |
| --- | --- |
| To a folder on the same disk | Moves |
| To a folder on another disk | Copies |
| Holding ⌥ | Always copies |
| Holding ⌘ | Always moves |

These are Finder's rules, and drags to and from Finder and other apps work the same way. Hold a drag over a background tab for a second and it comes forward. A drop goes through the same prompt and can be undone like any other command. Two exceptions: a drop from another app onto a sidebar row or a tab always copies, and nothing can be dropped on the Trash row (use ⌘⌫).

## Quick Look

Select a file and press Space. Space or Esc closes it. While it is up, ↑ and ↓ change the selection and the preview follows; with several items selected, the panel's own arrows step through them.

## Filter a folder

Press ⌘F and type. The list shows only the names that contain every word you typed, in any order; case and accents do not matter. The status bar says "4 of 212". ↑ and ↓ move through what is left, ↩ opens the selected item, and Esc clears the filter. While a filter is on, ⌘A and the file commands act only on the rows you can see. Each tab keeps its own filter, and going to another folder clears it.

To jump rather than filter, just type the first letters of a name.

## Favourites and the config file

- **Add a favourite:** drag a folder onto the sidebar.
- **Remove one:** drag its row out of the sidebar, or right-click it (or ⌥⌘←, then ⌃↩) and choose Remove from Sidebar.

The settings are two text files. `~/.config/grove-explorer/explorer.toml` holds Grove's defaults; leave it alone, since updates replace it. Yours go in `~/.config/grove-explorer/explorer.local.toml` beside it, which is never published; adding or removing a favourite in the sidebar writes that file for you.

```toml
[general]
start = "~"            # where a new window opens
show_hidden = false
two_panes = false

[favourites.home]      # one table for each favourite, in the order shown
path = "~"
title = "Home"

[favourites.projects]
path = "~/Developer"
```

If the local file has any `[favourites.…]` table, its list replaces the default one. A favourite whose folder does not exist is left out. If a file has a mistake, an orange line at the top of the window says where.

## What macOS will ask

The first time you open each of these, macOS asks whether Grove Explorer may read it: **Desktop**, **Documents**, **Downloads**, **iCloud Drive**, **a disk you plugged in**, and **a network disk**. Allow each one you want to browse; each is asked once. The first ⌘I asks whether Grove Explorer may control Finder, which is how Get Info is shown.

If you refuse, that folder says which permission is missing; press ↩ there (or click the button) for Privacy Settings, where you can change your mind under Privacy & Security › Files and Folders. Grove Explorer does not ask for Full Disk Access; without it, a few protected folders (Mail, Safari, the Trash) cannot be read.

## USB sticks and other disks

Disks appear under Locations when they are plugged in and go when they are removed. Eject one with the button on its row, or ⌥⌘← to the row and ⌘E. A disk that a copy or a move is using is not ejected: its row says why, and it can be ejected once the copy has finished or been cancelled. If you eject the disk a tab is showing, the tab moves to Home.

Sticks are usually formatted ExFAT or FAT, and everything above works on them. One thing differs: such a disk cannot hold a file's extra attributes (tags, a custom icon), so macOS keeps them in a hidden companion named `._` plus the file's name (`._notes.md` beside `notes.md`). A real file of yours with such a name cannot share a folder there with the file it would be mistaken for: copying that pair to the stick, or copying `notes.md` next to a `._notes.md` already there, is refused for that item with a sentence saying why, and nothing is overwritten.

## What stays in Finder

- **The Trash's contents.** The Trash row opens Finder's Trash; empty it and put things back from there.
- **The desktop.** The icons on the desktop are Finder's. (The Desktop folder itself opens like any other: ⌘⇧D.)
- **AirDrop**, and Finder's own sharing and network browsing.
- **Get Info.** ⌘I asks Finder to show its window.

## Not there yet

Said plainly, these are not built:

- **Search across folders.** ⌘F filters the folder you are in. To search the whole disk, use Finder's search field.
- **A preview pane.** Space (Quick Look) is the preview.
- **Icon, column and gallery views.** There is the list.
- **Tags.** Copies keep a file's tags, but they are not shown and cannot be set.
- **Remote folders over SSH.** Network disks that macOS has mounted work; connecting to a server is Finder's job (⌘K there).
- **Being the default file viewer.** "Show in Finder" in other apps, and folders opened from them, still open Finder.
