# 4. Themes

[Contents](README.md) · Previous: [The Grove menu](03-the-grove-menu.md) · Next: [Hotkeys](05-hotkeys.md)

Grove has six colour schemes, all from Everforest: dark or light, each in hard, medium or soft contrast. Dark Medium is the default.

## Switch scheme

| From | Do this |
| --- | --- |
| The Grove menu | Pine › Appearance, then pick a scheme. The current one has a ✓ |
| The launcher | ⌘Space, type part of the name (`light hard`), ↩ |
| The gallery | Pine › Appearance › Grove Themes…, then click a card |
| A terminal | `grove-themes set dark-soft` |

The scheme names for the terminal are `dark-hard`, `dark-medium`, `dark-soft`, `light-hard`, `light-medium` and `light-soft`.

## The gallery

Pine › Appearance › Grove Themes… opens a window with a preview card for each scheme and two more choices below:

- **Terminal logo:** the picture beside the summary in a new terminal window, either the Project Grove lockup or the tree-ring avatar.
- **Wallpaper:** the Project Grove lockup or the avatar drawing, on the scheme's background colour.

Both choices stay as you switch schemes; each scheme has its own version of each picture.

## What follows the scheme

| Changes at once | Changes the next time it starts |
| --- | --- |
| Ghostty, including open windows | Chrome (once its theme is loaded, see [Getting started](01-getting-started.md#finish-by-hand)) |
| The prompt and shell colours, at the next prompt | Yazi |
| The bar and window borders | |
| The wallpaper, on every screen and Space | |
| macOS light or dark appearance, accent and highlight colour | |
| VS Code | |
| Grove Keys and Grove Themes | |

The first switch may bring up a macOS prompt asking whether Grove may control System Events. Allow it: that is how the appearance and the wallpaper are set.

The light schemes are newer and less polished: lines and quiet text are darkened so they can be read, but Everforest's light accent colours are low in contrast on a pale background, and apps Grove does not theme simply follow macOS's light appearance.

## From the terminal

| Command | What it does |
| --- | --- |
| `grove-themes list` | The six schemes, the current one marked |
| `grove-themes current` | The current scheme's name |
| `grove-themes set SCHEME` | Switch to a scheme |
| `grove-themes logo grove` or `avatar` | Choose the terminal logo |
| `grove-themes wallpaper grove` or `avatar` | Choose the wallpaper |
| `grove-themes log` | The last five switches, newest first |

After a switch, the command lists each part with its result. `needs-you` means macOS wants a permission from you; the line says which.
