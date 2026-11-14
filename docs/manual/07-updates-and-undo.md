# 7. Updates and undo

[Contents](README.md) · Previous: [The terminal](06-the-terminal.md) · Next: [Coming from stock macOS](08-coming-from-stock-macos.md)

## Update

Choose Pine › Update › Update Grove, or run:

```sh
grove update
```

It fetches the latest Grove and then runs the installer, which redoes only what changed (for example, rebuilding Grove Keys). If you have edited tracked files in the repo, the fetch may stop and say so; nothing is changed until you sort that out.

## Check

Choose Pine › Update › Check, or run `grove check`. It changes nothing and prints one line for each part:

| Line starts with | Meaning | What to do |
| --- | --- | --- |
| `ok` | Nothing to do | – |
| `needs work` | Grove can fix it by itself | Run `grove install` |
| `needs you` | It needs something only you can give | Run `grove install NAME` and answer what it asks |
| `failed` | The check itself hit a problem | Read the message; it says what to run |

## When a part says "needs you"

Run `grove install` followed by the part's name without its number, for example `grove install aerospace`. The usual reasons:

| Part | What it is waiting for |
| --- | --- |
| `homebrew` | Your Mac password, for Homebrew's first install |
| `ssh` | Where `~/.ssh` should live (when there is a OneDrive folder), or a passphrase for a new SSH key |
| `git` | Your name and email |
| `github` | A sign-in to GitHub in the browser |
| `macos-wallpaper` | Permission for the terminal to control System Events (System Settings › Privacy & Security › Automation) |
| `aerospace` | AeroSpace turned on under Accessibility |
| `claude-mod` | Claude Code installed; then run `grove install claude-mod` |

Grove Keys reports missing permissions in its own way: `grove check` prints `failed` with a line naming Accessibility or Input Monitoring, and the Grove Keys submenu in the pine menu has a row that opens the right pane.

`grove install --yes` asks nothing and skips every part that needs you, then lists what it skipped.

If a step fails, the last lines say how to retry and where the log is (`~/.local/state/grove/logs/`).

## About

Choose Pine › About, or run `grove about`: the summary of your Mac, then Grove's version, the current scheme and the date of the last install or update. `grove --version` prints just the version.

## The `grove` command

| Command | What it does |
| --- | --- |
| `grove install [NAME…]` | Set up everything that needs it, or only the named parts |
| `grove check` | Report each part's state; change nothing |
| `grove update` | Fetch the latest Grove, then install |
| `grove list` | List the parts with a line about each |
| `grove about` | Version, scheme and last update |
| `grove present COMMAND` | Run a command in the Grove window |
| `grove --version` | The version |

## Undo

There is no uninstaller. Grove moves files aside instead of deleting them, so everything can be put back by hand. Do it in this order, and **do not delete the repo first**: `~/.config` points into it.

**1. Stop what runs.**

```sh
launchctl bootout gui/$(id -u)/com.projectgrove.keys
launchctl bootout gui/$(id -u)/com.projectgrove.themes
brew services stop felixkratz/formulae/sketchybar
defaults write NSGlobalDomain _HIHideMenuBar -bool false
```

Then quit AeroSpace (in a terminal: `killall AeroSpace`). Caps Lock is itself again as soon as Grove Keys stops. Log out and in to get the menu bar back.

**2. Remove the apps and their login items.** Delete `Grove Keys.app`, `Grove Themes.app` and `Grove Explorer.app` from `~/Applications`, and `com.projectgrove.keys.plist` and `com.projectgrove.themes.plist` from `~/Library/LaunchAgents`. In Keychain Access, delete the "Grove Code Signing" certificate and its key from the login keychain. Remove Grove Keys, Grove Explorer and AeroSpace from the lists under System Settings › Privacy & Security. If AeroSpace is listed under System Settings › General › Login Items, remove it there too. If you use Claude Code, remove the grove mod: `claude plugin uninstall grove@grove`, then `claude plugin marketplace remove grove` (Claude Code updates `~/.claude/settings.json` itself).

**3. Remove the links.** `rm` on a link removes only the link, never what it points to. If you chose a OneDrive folder for `~/.ssh`, `~/.ssh` is a link too: `rm ~/.ssh` and put the old folder back from the backup (step 4).

```sh
rm ~/.config ~/.zshenv ~/.ssh/config ~/.local/bin/grove ~/.local/bin/grove-themes
rm ~/Library/Application\ Support/Code/User/settings.json
```

**4. Put your files back.** Each install run that moved something has a folder in `~/.local/state/grove/backup/`. Paths inside it mirror your home folder: `<run>/.zshrc` goes back to `~/.zshrc`. The settings of your other apps that were in `~/.config` are now in the repo's `grove-dotfiles/config/` folder; copy what you want into a new `~/.config`.

**5. Set back by hand what has no backup.**

| Changed | Where to set it back |
| --- | --- |
| "Displays have separate Spaces" (off) | System Settings › Desktop & Dock; log out afterwards |
| Light or dark appearance, accent and highlight colour | System Settings › Appearance |
| Wallpaper | System Settings › Wallpaper |
| Finder: list view, path and status bars, extensions shown, folders first | Finder › Settings, and Finder's View menu |
| Ghostty in the Dock | Drag it out; drag Terminal in from Applications › Utilities |
| Fonts | Font Book, or `~/Library/Fonts` |
| VS Code extensions (Everforest, Grove Icons) | VS Code's Extensions view |
| Chrome theme | `chrome://extensions` |
| The signing key on GitHub | GitHub › Settings › SSH and GPG keys |
| Homebrew and what it installed | `brew uninstall NAME`; the list is `grove-dotfiles/Brewfile`, plus `sketchybar` |

Your SSH key in `~/.ssh` and your shell history in `~/.local/state/zsh/history` are left where they are.

**6. Only now** delete `~/Developer/project-grove` and `~/.local/state/grove` if you want them gone.
