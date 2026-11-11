# Project Grove: grove-dotfiles

Project Grove is a personal macOS overhaul built on the [Everforest](https://github.com/sainnhe/everforest) color scheme by sainnhe, in six schemes (dark or light, each hard, medium or soft). Its principal font is JetBrains Mono, with SF Pro as the companion. This folder, `grove-dotfiles`, holds the `grove` installer and the configs it manages. One command sets up a fresh Mac: tools, fonts, shell, git, GitHub, Finder, the terminal, VS Code, the tiling desktop (AeroSpace), the Grove bar (SketchyBar) with the Grove menu, and the Grove Keys and Grove Themes apps. Run it again any time; anything already done is left alone.

How to use the result is in the [manual](../docs/manual/README.md). This page is about the installer.

## Start on a fresh Mac

Open Terminal and paste:

```sh
curl -fsSL https://raw.githubusercontent.com/gmarques-x/project-grove/main/grove-dotfiles/bootstrap.sh | bash
```

It waits for Apple's Command Line Tools (finish the dialog that appears), clones the repo to `~/Developer/project-grove`, and runs `grove install`. If that folder already exists but isn't project-grove, it stops without touching anything; set `GROVE_CLONE_DIR` to clone somewhere else.

`grove install` asks you for:

- your name, email and GitHub username (nothing is suggested; type each one)
- your Mac password, for Homebrew's first install
- an SSH key passphrase, only if you don't have a key yet
- a browser login for GitHub
- permissions in System Settings › Privacy & Security: Accessibility and Input Monitoring for Grove Keys, Accessibility for AeroSpace, and Automation (System Events) for the terminal, which sets the wallpaper
- Always Allow, when macOS asks whether `codesign` may use the Grove Code Signing key

The manual's [Getting started](../docs/manual/01-getting-started.md) lists everything the installer changes and the steps left to do by hand.

## Do not delete the repo

> **`~/.config` IS the folder `project-grove/grove-dotfiles/config`.** It is a link, not a copy.
>
> - Deleting or re-cloning the repo deletes everything in `~/.config`.
> - Never run `git clean` in the repo (`-x` and `-X` both remove ignored files such as `local.env`).

If `~/.config` was already a folder, its contents are moved into `config/`: a name the tracked config doesn't have moves across, two folders merge, and anything else that collides goes to the backup.

Your personal values (name, email, GitHub username) live in `~/.config/grove/local.env`, which git ignores. Anything Grove replaces is moved, never deleted, to `~/.local/state/grove/backup/`.

## Undo

There is no uninstaller. Files are linked or moved aside, never deleted, so the setup can be undone by hand; the manual's [Updates and undo](../docs/manual/07-updates-and-undo.md) has the steps in order. What the modules create:

- **Links:** `~/.config`, `~/.zshenv`, `~/.ssh/config`, `~/.local/bin/grove`, `~/.local/bin/grove-themes`, and VS Code's `~/Library/Application Support/Code/User/settings.json` (`rm` on a link removes only the link).
- **Backups:** what those links and the shell setup replaced (`~/.zshrc`, `~/.zprofile`, `~/.gitconfig`, `~/.zsh_history`, `~/.zsh_sessions`, a Ghostty config in Application Support) is in `~/.local/state/grove/backup/<run>/`. Paths inside a run folder are relative to `$HOME` (`<run>/.zshrc` goes back to `~/.zshrc`).
- **Apps and login items:** `~/Applications/Grove Keys.app` and `Grove Themes.app`, with the LaunchAgents `com.projectgrove.keys` and `com.projectgrove.themes` in `~/Library/LaunchAgents`; AeroSpace starts at login by its own setting; SketchyBar runs as a Homebrew service.
- **Keychain:** the "Grove Code Signing" certificate and key in the login keychain, and the SSH key's passphrase.
- **macOS settings:** the menu bar set to hide (`NSGlobalDomain _HIHideMenuBar`), "Displays have separate Spaces" off (`com.apple.spaces spans-displays`), the Finder settings in `modules/80-macos-finder/settings.txt`, Ghostty's tile in the Dock, the wallpaper, and from the theme switcher the appearance, accent and highlight colours. None of these has a backup.
- **Installed:** Homebrew, the Brewfile's packages and SketchyBar; fonts in `~/Library/Fonts`; two VS Code extensions; an SSH key in `~/.ssh` (if you had none) and its copy on GitHub as a signing key.
- **State:** `~/.local/state/grove/` (logs, backups, the current scheme) and `~/.local/state/zsh/`.

Caps Lock is mapped to Hyper only while Grove Keys runs; quitting it gives Caps Lock back.

Your app settings stay in the repo's `config/` folder; copy them back into a new `~/.config` if you want them.

## The `grove` command

| Command | What it does |
| --- | --- |
| `grove install [module…]` | Sets things up. With no names, runs every module that needs work. |
| `grove check` | Reports each module as ok or not. Changes nothing. |
| `grove update` | Brings an installed setup up to date (`git pull --ff-only`, then install). |
| `grove list` | Lists the modules. |
| `grove about` | The fetch summary, then the version and commit, the current scheme and the date of the last install or update. |
| `grove present [--title T] <command…>` | Runs a command in the Grove window: a floating Ghostty window titled `Grove · T` that ends with `Done` or `Failed (N)` and closes on a key press. The Grove menu uses it. |
| `grove --version` | Prints `grove X.Y.Z (<short commit>)`; the number is in `VERSION`. |

Options: `--yes` asks nothing and skips anything that needs you (including your name and email, until a run that can ask); `--quiet` prints less.

## Modules

| Module | What it does |
| --- | --- |
| `05-config` | Makes `~/.config` a link to the tracked config and renders its generated files (`grove-themes render`) |
| `10-xcode-tools` | Xcode command line tools |
| `20-homebrew` | Homebrew and the Brewfile |
| `30-fonts` | JetBrains Mono, SF Pro and your own fonts (see Fonts) |
| `40-ssh` | ssh config, ed25519 key and agent |
| `50-git` | git identity and commit signing |
| `60-github` | GitHub login and SSH signing key |
| `70-zsh` | zsh config, Starship prompt and the `grove` and `grove-themes` commands |
| `80-macos-finder` | Finder settings (the sidebar is a manual step) |
| `85-macos-wallpaper` | Desktop wallpaper: `grove-wallpapers/wallpaper-<set>-<scheme>.png` for the current scheme on every screen (other Spaces are a manual step); the set is `project-grove`, or `avatar` after `grove-themes wallpaper avatar` |
| `90-terminal` | Ghostty in the Dock (in Terminal's place), its config, and fastfetch |
| `95-vscode` | VS Code: Everforest, Grove Icons and JetBrains Mono, settings linked from the tracked config |
| `96-keys-app` | Grove Keys in the menu bar: Caps Lock as Hyper, the keyboard window, and the AeroSpace config it renders; builds the app, installs it to ~/Applications and starts it at login |
| `97-themes-app` | Grove Themes in the menu bar: builds the app, installs it to ~/Applications and starts it at login |
| `98-aerospace` | AeroSpace tiles the desktop: numbered workspaces, Option shortcuts and JankyBorders in the scheme's colours (Accessibility is a manual step) |
| `99-sketchybar` | The Grove top bar: SketchyBar (trusted felixkratz/formulae tap) as a floating bar on a strip that hides the auto-hidden menu bar; workspaces, the front app and system status in the scheme's colours |

"In the menu bar" in the two app rows means the native menu bar, which sits hidden behind the Grove bar. Both apps are reached from the pine at the left of the bar: Appearance › Grove Themes… and Grove Keys ▸.

**The Grove menu** is `config/grove/menu.toml`: the pine's dropdown and the palette on Hyper + Space. Your own rows go in `config/grove/menu.local.toml`, which git ignores; the format is explained at the top of `menu.toml` and in the manual's [The Grove menu](../docs/manual/03-the-grove-menu.md).

**Chrome** is themed by an unpacked extension that grove-themes renders to `~/.config/chrome-theme`; load it once (see `grove-themes/README.md`).

## Fonts

| Role | Font | Used for | License |
| --- | --- | --- | --- |
| Principal | **JetBrains Mono** and **JetBrains Mono NL** (2.304, 32 static TTFs) | Code and app text: the terminal, the editor, the Grove bar and the Grove apps | SIL Open Font License 1.1 |
| Companion | **SF Pro**, **SF Pro Text**, **SF Pro Display**, **SF Pro Rounded** (47 files) | Where macOS draws it: menus, dialogs and other system text | Apple font license |

`grove install fonts` copies them to `~/Library/Fonts` (no admin password) and registers them with macOS, which this version of macOS needs before apps can use a font. Downloads are cached in `~/Library/Caches/grove/fonts` and fetched again only when the server has a newer file.

- JetBrains Mono is checked against a fixed SHA-256. The variable and web fonts in the release are left out, so font menus don't show duplicates.
- SF Pro is unpacked from Apple's installer without running it, after checking that the package is signed by Apple. Apple updates the download in place, so a fixed checksum wouldn't last.
- Font files are never committed, because of their licenses.

To add a font:

1. **From a download:** add a line to `modules/30-fonts/fonts.txt`: a name, a URL (`.zip`, `.dmg`, `.pkg`, `.ttf` or `.otf`), how to verify it, and which files to take. The comments at the top of the file explain each field. Other Apple fonts work like SF Pro, for example:
   ```
   SF Mono|https://devimages-cdn.apple.com/design/resources/download/SF-Mono.dmg|apple-signed|*.pkg/Payload/Library/Fonts/*
   ```
2. **From files you have:** drop `.ttf` or `.otf` files into `modules/30-fonts/local/`. They aren't committed.

## Terminal and shell

**Ghostty** is the terminal: the current scheme's colours, JetBrains Mono 12, a solid window. Its config is `config/ghostty/config`, rendered from `config/ghostty/config.tmpl` (edit the template). The left Option key is Alt, so ⌥C and ⌥B/⌥F work in the shell; the right one still types the layout's characters. New windows open at 150 × 40 (columns × rows).

- **Quick terminal:** ⌃` drops a terminal down from the top of the screen, from any app. macOS only lets you grant this, so do it once: **System Settings › Privacy & Security › Accessibility**, then turn on Ghostty.
- **Dock:** `grove install` gives Ghostty Terminal's place in the Dock. Terminal.app stays installed.
- **Prompt:** the Starship prompt shows icons in Ghostty. Terminal.app can't draw them, so it gets the same prompt without icons (`config/starship-plain.toml`).
- **Summary:** every new window starts with a fastfetch summary: the Project Grove image beside your Mac's stats in a box. The image needs a Ghostty window at least 140 columns wide (108 for the avatar logo); narrower windows and Terminal.app show a text drawing instead, and windows under 125 columns show just the stats. Shells started from that window stay quiet. Turn it off with `export GROVE_NO_FETCH=1` in `config/zsh/.zshenv`. The config is `config/fastfetch/`.

The shell has completions (menu selection, case-insensitive), suggestions from your history in grey (→ accepts), syntax highlighting, and these replacements:

| Type | Runs | |
| --- | --- | --- |
| `ls` | `eza -l`, folders first, then files, each A→Z; `-t`, `-S` and `-r` sort as in `ls` | the original: `\ls` |
| `ll` | the same, with hidden files | |
| `lt` | a two-level tree | |
| `cat` | `bat` (line numbers, git changes; long files open in a pager) | the original: `\cat` |
| `cd` | zoxide: works like `cd`, and `cd proj` jumps to your most-used match | the original: `builtin cd` |
| `cls` | clears the screen and reloads the shell, like a new window (summary included) | |
| `zalias`, `zedit` | open the aliases file, or the zsh config folder, in `$EDITOR` | |
| `y` or `finder` | yazi, a file manager in the terminal; when you quit, the shell moves to the folder you were in | plain: `yazi` |
| ⌃R / ⌃T / ⌥C | fzf: search history / pick files / jump to a folder | |

`rg` is ripgrep. `grep` is unchanged.

**yazi** lists like `ls` (folders first, A→Z, hidden files off; `.` shows them) in the same colors as eza. Its top bar is drawn like the prompt (`config/yazi/init.lua`), with a line under it, and the hovered row is a rounded pill. Its config is `config/yazi/`. It previews images in Ghostty, plus PDFs, archives and SVGs. Video thumbnails and HEIC/RAW images are left out, since they need ffmpeg and ImageMagick. Terminal.app shows plain previews and can't draw the file icons.

## Adding a module

Make a folder `modules/NN-name/` with a `module.sh` that defines three functions:

- `about` prints a one-line description.
- `check` reports the state and never changes anything. It returns `0` when ok, `3` when it needs work, `4` when it needs you.
- `apply` makes the change. It only runs when `check` didn't return `0`.

The number sets the order modules run in.

## Credits

- [Everforest](https://github.com/sainnhe/everforest) by sainnhe (MIT)
- Prompt colors come from the Everforest zsh port
- [Starship](https://starship.rs) for the prompt
