# 1. Getting started

[Contents](README.md) · Next: [The desktop](02-the-desktop.md)

## Before you install: what Grove does to your Mac

Grove is a personal setup, not an app you can drag to the Bin. Read this list first.

- **`~/.config` becomes a link** to the `grove-dotfiles/config` folder inside the repo. If you already have a `~/.config`, its contents are moved into that folder; anything that clashes with a file Grove ships is moved to a backup folder instead. Nothing is deleted. From then on, deleting the repo deletes your `~/.config`.
- **Your shell files are replaced.** `~/.zshrc`, `~/.zprofile` and `~/.gitconfig` are moved to the backup folder, and `~/.zshenv` and `~/.ssh/config` become links into the repo. Your shell history is carried over.
- **Software is installed** with Homebrew (Homebrew itself if missing): Ghostty, VS Code, Chrome, AeroSpace, JankyBorders, SketchyBar and a set of command-line tools. JetBrains Mono and SF Pro are copied to `~/Library/Fonts`.
- **Two apps are built and start at login:** Grove Keys and Grove Themes, in `~/Applications`. A third, Grove Explorer (the file browser), is built there too and opens only when you open it. A self-signed certificate, "Grove Code Signing", is added to your login keychain to sign Grove Keys and Grove Explorer.
- **The desktop changes.** The menu bar is set to hide and a Grove bar sits in its place. AeroSpace tiles your windows. "Displays have separate Spaces" is turned off. Caps Lock becomes the Hyper key while Grove Keys runs.
- **Smaller changes:** Finder settings (list view, path bar, extensions shown), Ghostty takes Terminal's place in the Dock, the wallpaper, macOS's appearance, accent and highlight colours, and VS Code's settings and theme.
- **Accounts:** it makes an SSH key if you have none, signs you in to GitHub in the browser, and uploads the key to GitHub as a signing key.

Backups go to `~/.local/state/grove/backup/<date-time>/`. To take any of this back, see [Updates and undo](07-updates-and-undo.md).

## Install

Open Terminal and paste:

```sh
curl -fsSL https://raw.githubusercontent.com/gmarques-x/project-grove/main/grove-dotfiles/bootstrap.sh | bash
```

It waits for Apple's Command Line Tools (finish the dialog that appears), puts the repo in `~/Developer/project-grove` and runs `grove install`. It is safe to run again: steps already done are left alone.

## What it asks for

| When | What to do |
| --- | --- |
| At the start | Type your name, email and GitHub username |
| Homebrew's first install | Type your Mac password |
| No SSH key yet | Choose a passphrase for the new key |
| GitHub | Sign in in the browser window that opens |
| "codesign wants to use a key" | Choose **Always Allow** |
| Grove Keys | Turn it on under **Accessibility** and **Input Monitoring** (the installer opens both panes in System Settings › Privacy & Security) |
| AeroSpace | Turn it on under **Accessibility**; the installer waits until you do |
| "Terminal wants to control System Events" | Allow it: it sets the wallpaper and the light or dark appearance |

## Finish by hand

A few things macOS does not let an installer do:

1. **Log out and back in once**, to finish the Spaces change.
2. **Ghostty's quick terminal:** turn Ghostty on under System Settings › Privacy & Security › Accessibility, so ⌃` works from any app.
3. **Chrome's theme:** open `chrome://extensions`, turn on Developer mode, choose Load unpacked and pick `~/.config/chrome-theme` (⌘⇧. shows hidden folders).
4. **Finder's sidebar:** set it in Finder › Settings › Sidebar. The installer prints the suggested list.

## The first five minutes

| Try this | What happens |
| --- | --- |
| Click the pine at the left of the bar | The [Grove menu](03-the-grove-menu.md) opens |
| ⌘Space | The Grove Launcher: type to open an app or find any Grove action |
| Hold Caps Lock for half a second | The [cheat sheet](05-hotkeys.md#the-cheat-sheet) |
| ⌥1 … ⌥9 | Go to a [workspace](02-the-desktop.md) |
| ⌥H ⌥J ⌥K ⌥L | Move focus between windows |
| Open Ghostty | The [terminal](06-the-terminal.md), with a summary of your Mac |

If something looks half done, run `grove check` in a terminal. It lists each part as `ok`, `needs work` or `needs you` and changes nothing.
