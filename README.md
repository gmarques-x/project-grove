<p align="center">
  <img src="assets/project-grove-banner.png" width="100%" alt="Project Grove: a complete macOS desktop overhaul. Beautiful terminal, powerful apps, seamless theming, a more focused Mac.">
</p>

# Project Grove

A personal macOS overhaul in the [Everforest](https://github.com/sainnhe/everforest) colours by sainnhe: a tiling desktop with its own top bar, a keyboard layer on Caps Lock, a themed terminal and editor, and one menu that reaches all of it. An installer sets the whole thing up on a fresh Mac, and a switcher moves everything between six schemes (dark or light, each in hard, medium or soft contrast).

<!-- Screenshots go here: the desktop with the bar and tiled windows, the Grove menu or the launcher, and the theme gallery. -->

## What's inside

| Folder | What it is |
| --- | --- |
| [`grove-dotfiles/`](grove-dotfiles/) | The `grove` installer and every config it manages: the tiling desktop (AeroSpace, with JankyBorders), the Grove bar (SketchyBar, in place of the menu bar), the Grove menu, the terminal (Ghostty, zsh, Starship, Yazi, fastfetch), VS Code and Chrome themes, git and SSH, fonts and Finder settings. It also builds and installs the two apps below. |
| [`grove-keys/`](grove-keys/) | Grove Keys, the keyboard app: Caps Lock as a Hyper key, app launchers, the window-manager shortcuts, a cheat sheet, and the menus behind the bar (the Grove menu, the Grove Launcher on ⌘Space and each app's own menus). |
| [`grove-themes/`](grove-themes/) | The `grove-themes` command and the Grove Themes app: switch the desktop between the six Everforest schemes, and choose the terminal logo and wallpaper. |
| [`grove-wallpapers/`](grove-wallpapers/) | Two wallpapers for each scheme, 2880 × 1864: the Project Grove lockup and the avatar drawing. |
| [`assets/`](assets/) | Images for this page. |

## The manual

[**docs/manual**](docs/manual/README.md) says what to press: the desktop and the bar, the Grove menu, themes, hotkeys, the terminal, updating and undoing, and a table for people [coming from stock macOS](docs/manual/08-coming-from-stock-macos.md).

## What it changes on your Mac

Read this before you paste anything. Grove is a whole setup, and it is not undone with one command.

- **`~/.config` becomes a link into this repo** (`grove-dotfiles/config`). An existing `~/.config` is not thrown away: its contents are moved into that folder, and any file that clashes with one Grove ships is moved to `~/.local/state/grove/backup/` instead. Afterwards, deleting the repo deletes your `~/.config`.
- `~/.zshrc`, `~/.zprofile` and `~/.gitconfig` are moved to the same backup folder; `~/.zshenv` and `~/.ssh/config` become links.
- The macOS menu bar is hidden behind the Grove bar, windows are tiled, and Caps Lock becomes a Hyper key. Menu-bar icons from other apps are not reachable for now.
- Homebrew packages, fonts, two apps that start at login, a code-signing certificate in your keychain, an SSH key and a GitHub sign-in, and Finder, Dock and appearance settings.

The full list, what the installer asks for, and how to take it all back are in the manual: [Getting started](docs/manual/01-getting-started.md) and [Updates and undo](docs/manual/07-updates-and-undo.md).

## Start on a fresh Mac

Open Terminal and paste:

```sh
curl -fsSL https://raw.githubusercontent.com/gmarques-x/project-grove/main/grove-dotfiles/bootstrap.sh | bash
```

It clones this repo to `~/Developer/project-grove` and runs `grove install`.

## Credits

The colors are [Everforest](https://github.com/sainnhe/everforest) by sainnhe. Every color in the configs comes from its palette, and the tests check it.

## License

[MIT](LICENSE).
