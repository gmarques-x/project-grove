# 6. The terminal

[Contents](README.md) · Previous: [Hotkeys](05-hotkeys.md) · Next: [Updates and undo](07-updates-and-undo.md)

## Ghostty

Ghostty is the terminal. It sits in the Dock where Terminal used to be; Terminal is still installed.

| Press | To |
| --- | --- |
| ⌃` | Drop a terminal down from the top of the screen, from any app; press again to put it away |
| ⌘N, ⌘T | New window, new tab |
| ⌘D, ⌘⇧D | Split to the right, split downwards |
| ⌘⇧, | Reload Ghostty's settings |

⌃` needs Ghostty turned on under System Settings › Privacy & Security › Accessibility.

Every new window starts with a summary of your Mac beside the Grove logo. Narrow windows show a text drawing or just the figures. To turn the summary off, add `export GROVE_NO_FETCH=1` to `~/.config/zsh/.zshenv`.

In Ghostty the **left ⌥ is Alt**, which the shell shortcuts below need. The right ⌥ still types your keyboard layout's special characters.

## The prompt

The prompt is one line of coloured blocks, then `❯`:

| Block | Shows |
| --- | --- |
| Aqua | Your user name |
| Green | The folder you are in |
| Yellow | In a git repository: the branch, and `?` untracked, `!` modified, `+` staged |
| Orange | The time |

`❯` turns red when the last command failed.

## What you type

| Type | You get |
| --- | --- |
| `ls` | A long listing, folders first, with icons and git status. `-t`, `-S` and `-r` sort as they do in `ls` (`ls -ltr`) |
| `ll` | The same, with hidden files |
| `lt` | A two-level tree |
| `cat FILE` | The file with line numbers and colours; long files open in a pager |
| `cd NAME` | Works like `cd`, and also jumps to the folder you visit most whose name matches |
| `y` or `finder` | Yazi, the file manager (below) |
| `cls` | Clear the screen and reload the shell, like a new window |
| `zalias` | Edit the aliases file |
| `zedit` | Open the shell's settings folder in your editor |
| `rg TEXT` | Search file contents (ripgrep) |

The originals are still there: `\ls`, `\cat`, `builtin cd`. `grep` is unchanged.

## Shortcuts in the shell

| Press | To |
| --- | --- |
| ⌃R | Search your command history |
| ⌃T | Pick a file and insert its path |
| ⌥C | Pick a folder and go to it (left ⌥) |
| → | Accept the grey suggestion from your history |
| Tab | Complete; press again to choose from a menu |

Commands are coloured as you type: green when the command exists, red when it does not.

## Yazi

Type `y`. Yazi shows three columns: the parent folder, the current one, and a preview of whatever is selected (text, images, PDFs, archives).

| Press | To |
| --- | --- |
| ↑ ↓ or K J | Move through the list |
| → or L, ↩ | Enter a folder, or open a file |
| ← or H | Go up a folder |
| . | Show or hide hidden files |
| / | Find in the list |
| Space | Select |
| Q | Quit |

When you quit, the shell moves to the folder you were in. Plain `yazi` leaves the shell where it was. Yazi's own guide is under Pine › Learn › Yazi.
