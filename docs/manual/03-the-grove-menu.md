# 3. The Grove menu

[Contents](README.md) · Previous: [The desktop](02-the-desktop.md) · Next: [Themes](04-themes.md)

One menu reaches everything Grove can do. Open it two ways:

- **With the mouse:** click the pine at the left of the bar. The menu opens under it; a row with an arrow opens its submenu beside it when the pointer rests there. The arrow keys, Return and Esc work too, and typing a letter jumps to the next row that starts with it.
- **With the keyboard:** press ⌘Space for the Grove Launcher.

## The tree

| Row | What is inside |
| --- | --- |
| **Appearance** | Grove Themes… (the gallery), then the six schemes; the current one has a ✓. See [Themes](04-themes.md) |
| **Files** | Opens Grove Explorer, the file browser. See [Files](09-files.md) |
| **Grove Keys** | Open Grove Keys (the keyboard window), Show cheat sheet, Pause Hyper / Resume Hyper. If Grove Keys is missing a permission, a line here says so and opens the right pane in System Settings |
| **Update** | Check, Update Grove, Run the Installer. See [Updates and undo](07-updates-and-undo.md) |
| **Learn** | Keybindings (the cheat sheet), The Grove Manual, and the AeroSpace, Ghostty and Yazi documentation |
| **About** | Grove's version, the current scheme and the date of the last update |
| **System** | System Settings… (macOS's own settings), then Lock, Sleep Display, Sleep, Log Out…, Restart…, Shut Down… |
| **Global Menu** | The menus of the app in front, starting with the Apple menu |

Log Out, Restart and Shut Down show macOS's usual confirmation before anything happens. Lock, Sleep Display and Sleep act at once.

Rows that print something (Check, Update Grove, Run the Installer, About) open **the Grove window**: a small floating terminal titled `Grove · …` that runs the command, ends with `Done` or `Failed`, and closes when you press a key.

## The Grove Launcher

Press ⌘Space. A panel opens in the middle of the screen with a text field and every action in the menu, written as a path: `Appearance › Dark Medium`, `System › Lock`. Start typing and the apps on this Mac join the list, each with its icon. The launcher has ⌘Space in Spotlight's place.

| Press | To |
| --- | --- |
| Any text | Find apps and rows. Case and accents do not matter; every word you type must appear in the app's name or the row's path |
| ↑ ↓ | Move through the list |
| ↩ | Open the app (or bring it forward if it is running), or run the row; then close |
| Esc, ⌘Space again, or a click outside | Close |

The best match is first: a name that starts with what you typed, then a name with a word that starts with it, then the rest. An app comes before a menu row, and a shorter name before a longer one.

So `⌘Space`, `saf`, `↩` opens Safari; `⌘Space`, `dark soft`, `↩` switches to the Dark Soft scheme; and `⌘Space`, `lock`, `↩` locks the screen. The launcher has every app in the Applications folders (yours, the system's, their Utilities, and the web apps Chrome installed) and everything in the tree except Global Menu.

Grove Keys takes ⌘Space before macOS sees it, so Spotlight's own setting is untouched. If Spotlight opens as well, turn its shortcut off: System Settings › Keyboard › Keyboard Shortcuts… › Spotlight, and untick "Show Spotlight search". To give ⌘Space back to Spotlight, turn off "⌘Space opens the launcher" in the Grove Keys window (Bindings tab, Hyper key group), or set `launcher = "none"` under `[hyper]` in `keys.toml`; the launcher then opens with `open grovekeys://launcher`, which you can bind to a key of your own. The launcher's key needs Grove Keys running with its two permissions; pausing Hyper does not turn it off.

## Adding your own rows

The menu is a text file, `~/.config/grove/menu.toml`. Leave that one alone, since updates replace it. Put your changes in a file beside it, `~/.config/grove/menu.local.toml`, which is yours and is never published.

In either file, each `[name]` block is a row. A dot in the name places the row inside another: `[learn.starship]` sits under `[learn]`.

| Key | Meaning |
| --- | --- |
| `title` | The row's text |
| `run` | A shell command, run quietly |
| `present` | A shell command, run in the Grove window so you see its output |
| `open` | A link or a path to open |
| `checked` | A shell test; the row gets a ✓ when it succeeds |
| `separator = true` | Draw a line above this row |
| `hidden = true` | Leave this row (and anything inside it) out |
| `icon` | A symbol before the row, for a row at the top of the pine's menu: an SF Symbol's name from Grove's set, such as `book`, `keyboard`, `wifi`, `calendar` or `display` (`GroveKeys --check-menu` lists them all). A top row without one keeps the same indent |

A row takes one of `run`, `present` or `open`. A row with rows inside it is a submenu.

In `menu.local.toml`:

- a block with a **name the menu already has** changes that row, key by key;
- a block with a **new name** adds a row at the end of its submenu;
- `hidden = true` removes a row.

### A worked example

```toml
# ~/.config/grove/menu.local.toml

# 1. Add a link to the Learn submenu.
[learn.starship]
title = "Starship"
open = "https://starship.rs/config/"

# 2. Add a submenu of your own, with two rows.
[tools]
title = "Tools"

[tools.disk]
title = "Disk Space"
present = "df -h /"

[tools.caffeinate]
title = "Stay Awake for an Hour"
separator = true
run = "caffeinate -d -t 3600"

# 3. Rename a row Grove ships.
[system.display-sleep]
title = "Screen Off"

# 4. Remove one you never use.
[learn.yazi]
hidden = true
```

Save the file and open the menu again. Learn now ends with Starship and has no Yazi row, a Tools submenu sits at the end of the menu, and both new Tools rows are in the launcher as `Tools › Disk Space` and `Tools › Stay Awake for an Hour`.

If the file has a mistake, the menu still opens: your file is ignored and the first row of the menu says what is wrong.

Commands run in your login shell, so anything you can type in a terminal works, including `grove` and `grove-themes`.
