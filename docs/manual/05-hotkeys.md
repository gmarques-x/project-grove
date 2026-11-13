# 5. Hotkeys

[Contents](README.md) · Previous: [Themes](04-themes.md) · Next: [The terminal](06-the-terminal.md)

## The Hyper key

Caps Lock is the Hyper key.

- **Tap it** and it sends Escape.
- **Hold it** and press another key for a Grove shortcut. Nothing else on a Mac uses Hyper, so these never clash with an app's own shortcuts.
- **Hold it alone** for half a second and the cheat sheet appears until you let go.

Caps Lock no longer types capitals. To have it back for a while, choose Pine › Grove Keys › Pause Hyper.

## Hyper bindings

| Press | To |
| --- | --- |
| Hyper + K | Open the searchable cheat sheet |

**⌘Space** opens the [Grove Launcher](03-the-grove-menu.md#the-grove-launcher), in Spotlight's place: type to open an app or run a Grove menu row.

Hyper plus a key can also launch an app. Add launchers in the Grove Keys window; for example, Hyper + ↩ for Ghostty.

## Workspaces and windows (⌥)

| Press | To |
| --- | --- |
| ⌥1 … ⌥9 | Go to workspace 1 … 9 |
| ⌥⇧1 … ⌥⇧9 | Send the window to workspace 1 … 9 |
| ⌥Tab | Go back to the previous workspace |
| ⌥⇧Tab | Move the workspace to the next monitor |
| ⌥H ⌥J ⌥K ⌥L | Focus left, down, up, right |
| ⌥⇧H ⌥⇧J ⌥⇧K ⌥⇧L | Move the window left, down, up, right |
| ⌥- | Make the window smaller |
| ⌥= | Make the window larger |
| ⌥/ | Tiles layout (again: switch between columns and rows) |
| ⌥, | Accordion layout (again: turn it) |
| ⌥⇧; | Enter service mode |

## Service mode (after ⌥⇧;)

| Press | To |
| --- | --- |
| F | Float the window, or tile it again |
| R | Reset the workspace's layout |
| ⌫ | Close every other window on the workspace |
| ⌥⇧H ⌥⇧J ⌥⇧K ⌥⇧L | Join the window with the one on that side |
| Esc | Reload the configuration and leave service mode |

Each of these returns you to the normal mode.

These shortcuts are for the **left ⌥**, and they work in every app.

## Special characters (the right ⌥)

The **right ⌥** types the characters your keyboard layout has on ⌥, in every app, and never runs a shortcut: on a Portuguese keyboard right ⌥2 is `@`, right ⌥3 is `€`, and right ⌥⇧8 is `{`. Keys that type nothing (the arrows, ⌫, Tab) still work with it as usual, so right ⌥← moves back a word.

A key that normally waits for a letter (⌥´ for `¨`, ⌥~ for `˜`) types its accent at once with the right ⌥. To put that accent on a letter, use the left ⌥ or the keyboard's own accent keys.

Grove Keys does this, so it works while Grove Keys is running (also with Hyper off or paused); password fields, where macOS hides the keys from every app, are the exception. To have both ⌥ keys run shortcuts, turn off "Right ⌥ types characters" in the Bindings tab's Hyper key group, or set `right_option = "shortcuts"` under `[hyper]` in `keys.toml`.

## Elsewhere

| Press | To |
| --- | --- |
| ⌃` | Drop a terminal down from the top of the screen, from any app (on an ISO keyboard, ⌃ and the key beside the left Shift) |
| ⌃R ⌃T ⌥C | In the shell: search history, pick a file, jump to a folder |

More in [The terminal](06-the-terminal.md).

## Change a binding

**In the Grove Keys window:** Pine › Grove Keys › Open Grove Keys. It has two tabs. **Keyboard** draws the keyboard with what each key does in the chosen layer; click a key to edit it. **Bindings** lists everything in groups: Hyper key, Launchers, one group for each AeroSpace mode, and Monitors; click a row to edit it, or use Add launcher or Add binding for a new one. Changes apply as soon as they are saved.

**In the file:** edit `~/.config/grove-keys/keys.toml`. The window and the file are the same thing; use whichever you prefer.

```toml
[launch]                       # Hyper + key opens an app, by bundle ID
enter = "com.mitchellh.ghostty"

[aerospace.main]               # AeroSpace's own syntax
alt-h = "focus left"
hyper-k = "exec-and-forget open grovekeys://cheatsheet"
```

In the file, `alt` is ⌥ and `hyper-` means Caps Lock held. The right-hand side is an AeroSpace command; the Learn submenu has a link to AeroSpace's guide, which lists them.

If the file has a mistake, the Grove Keys window shows it as `keys.toml line N: …` and the last good set of bindings keeps working.

## The keyboard you type on

The Keyboard tab draws your Mac's keyboard: the ISO shape (a short left Shift with a key beside it, a tall Return, `§` at the top left) or the ANSI shape, whichever macOS reports. Each key shows what it types with your current input source, its Shift character above, so on a Portuguese keyboard you see `Ç`, `º` and `<` where they are on the keys; choose another input source in the menu bar and the drawing, the cheat sheets and every shortcut Grove Keys writes (`⌃⌥⇧⌘ Ç`, `⌥⇧ Ç`) change with it. If the shape is wrong, pick ISO or ANSI under Keyboard in the tab, or set `shape = "iso"` (or `"ansi"`, or `"auto"`) under `[keyboard]` in `keys.toml`. The file keeps naming keys by their place on a US keyboard, so it works on any Mac: the key that types `Ç` on a Portuguese keyboard is `semicolon`, the `§` key is `section`, and pressing a key to record a shortcut saves that name.

## The cheat sheet

| Do this | To |
| --- | --- |
| Hold Caps Lock for half a second | See the Hyper layer; it goes when you let go |
| Hyper + K, or Pine › Learn › Keybindings | Open the searchable sheet |

In the searchable sheet, type to filter. It lists the Hyper bindings, every AeroSpace mode, and the keys Grove relies on elsewhere: Ghostty's, the shell's and a few of macOS's own. Press ↩ on a row to run it where that is possible, or Esc to close.
