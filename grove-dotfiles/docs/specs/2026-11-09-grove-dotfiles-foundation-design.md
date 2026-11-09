# grove-dotfiles · Spec 1: framework, foundation and macOS settings

- Date: 9 November 2026
- Status: draft for review
- Part of: Project Grove (`gmarques-x/project-grove`)

## 1. Goal

One command sets up a Mac the Project Grove way. On a freshly reset Mac you paste one line into Terminal, answer a few prompts, and end up where this Mac is today. On a Mac that is already set up, running it again asks nothing and changes nothing.

This spec covers the framework (the `grove` command, the module system, file layout), the foundation modules (everything set up by hand so far) and the first macOS settings module (Finder). Later specs add the Shell, Terminal and Editor modules on top of the same framework.

## 2. Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Audience | Public repo, built for this one person | Shows Project Grove on the GitHub profile. Personal values are asked at install time and never committed. |
| Location | `project-grove/grove-dotfiles/` inside the existing repo; `project-grove` becomes public | One clone installs everything; the installer calls `../grove-fonts` directly. |
| File management | Grove's own symlink script | No dependencies before Homebrew, edits in place show up in `git diff`, backups before replacing anything. |
| Interface | A `grove` command | `grove install`, `grove check`, `grove update`, `grove list`. |
| Config home | `~/.config` is one symlink to `grove-dotfiles/config/` | Everything an app reads from `~/.config` lives in the repo folder. |
| zsh | Fully in `~/.config/zsh/` via `ZDOTDIR` | Only `~/.zshenv` stays in the home folder, as a link. |
| Prompt | Starship, styled after the Everforest zsh port | The port (sainnhe/dotfiles `.zsh-theme`, MIT) needs Powerlevel10k, which now has very limited support. Starship is maintained and configured by one file in `~/.config`. |
| Language | bash 3.2 (built into macOS) | Runs before Homebrew exists. Same as grove-fonts. |
| Order | Framework first, then modules | Shell, Terminal and Editor need their own design rounds. |

## 3. Scope

**In this spec**

- `bootstrap.sh`, the `grove` command, shared helpers in `lib/`
- Modules: config link, Xcode Command Line Tools, Homebrew and Brewfile, fonts, git, SSH signing key, GitHub, zsh base with Starship prompt, Finder settings
- Migrating this Mac from today's hand-made files
- Tests and a fresh-install test on a new macOS user account
- Making `project-grove` public with a README

**Not in this spec**

- The Finder sidebar. macOS has no supported command for it; the Finder module prints a checklist instead.
- The full Shell module (aliases, plugins, completions), Terminal and Editor modules. They plug into this framework later.
- A light-mode prompt and automatic switching with macOS Appearance (design study decision D2).
- Other macOS settings (Dock, keyboard, …). The settings format supports them; they are added as they get recorded.

## 4. Layout

```
project-grove/
├── artifacts/                      design work for review (unchanged)
├── grove-fonts/                    font installer (unchanged)
└── grove-dotfiles/
    ├── README.md                   what it is, the bootstrap line, safety notes
    ├── bootstrap.sh                entry point for a fresh Mac
    ├── Brewfile                    git, python, gh, starship, bats-core, shellcheck
    ├── bin/grove                   the grove command
    ├── lib/
    │   ├── ui.sh                   Everforest output, prompts, step headers
    │   ├── link.sh                 link with backup; link check
    │   ├── defaults.sh             apply and check macOS settings from data files
    │   └── local.sh                read and write personal values
    ├── modules/
    │   ├── 05-config/module.sh
    │   ├── 10-xcode-tools/module.sh
    │   ├── 20-homebrew/module.sh
    │   ├── 30-fonts/module.sh
    │   ├── 40-ssh/module.sh
    │   ├── 50-git/module.sh
    │   ├── 60-github/module.sh
    │   ├── 70-zsh/module.sh
    │   └── 80-macos-finder/
    │       ├── module.sh
    │       ├── settings.txt
    │       └── StandardViewSettings.plist
    ├── config/                     linked as ~/.config
    │   ├── .gitignore              allowlist (see 6)
    │   ├── git/config
    │   ├── ssh/config
    │   ├── zsh/  .zshenv .zprofile .zshrc  conf.d/*.zsh
    │   └── starship.toml
    ├── tests/                      bats tests
    └── docs/specs/                 this file
```

## 5. Module contract

Each module is a folder in `modules/` with a `module.sh` that defines three functions:

| Function | Does | Returns |
|----------|------|---------|
| `about` | Prints one line describing the module | |
| `check` | Inspects the Mac. Changes nothing. Prints what it found. | `0` ok · `3` needs work · `4` needs you (a password, passphrase or browser step) |
| `apply` | Makes the change. Safe to run again. | `0` success · non-zero failure |

The exit codes match grove-fonts (`0` ok, `3` missing). `grove` sources one module at a time in a subshell, so modules can't leak variables into each other. Modules run in number order. A later module (Shell, Terminal, Editor) is a new folder, for example `90-terminal/`. The framework doesn't change.

Modules get these variables from `grove`: `GROVE_ROOT` (the grove-dotfiles folder), `GROVE_CONFIG` (`$GROVE_ROOT/config`), `GROVE_STATE` (`~/.local/state/grove`), `GROVE_LOCAL` (`~/.config/grove/local.env`), `GROVE_YES` (1 when running unattended). Tests set them to point into a throwaway folder.

## 6. Where files live

**`~/.config` is a symlink to `grove-dotfiles/config/`.**

- `config/.gitignore` ignores everything (`/*`) and lists the tracked entries explicitly (`!/git/`, `!/ssh/`, `!/zsh/`, `!/starship.toml`, `!/.gitignore`). Files that apps create in `~/.config` stay untracked unless added to the allowlist on purpose.
- Inside tracked folders, generated personal files are ignored too: `git/local` and `git/allowed_signers`.
- Deleting or re-cloning the repo folder deletes everything in `~/.config`. The README says so; `grove` never runs `git clean`.

**Files that have to stay in the home folder become links:**

| Home path | Points to | Why it can't move |
|-----------|-----------|-------------------|
| `~/.config` | `grove-dotfiles/config` | |
| `~/.zshenv` | `~/.config/zsh/.zshenv` | zsh reads it before it knows `ZDOTDIR` |
| `~/.ssh/config` | `~/.config/ssh/config` | SSH only looks in `~/.ssh` |
| `~/.local/bin/grove` | `grove-dotfiles/bin/grove` | puts `grove` on the PATH |

`~/.gitconfig`, `~/.zprofile` and `~/.zshrc` are retired: git reads `~/.config/git/config`, and zsh reads `~/.config/zsh/` through `ZDOTDIR`. SSH keys stay in `~/.ssh` and are never in the repo.

**Private and changing data lives in `~/.local/state/`:** zsh history (`zsh/history`), Grove logs (`grove/logs/`) and backups (`grove/backup/`).

**Personal values** live in `~/.config/grove/local.env` (ignored by git):

```sh
GROVE_NAME="gmarques-x"
GROVE_EMAIL="gustavo.marques@outlook.com"
GROVE_GITHUB_USER="gmarques-x"
```

They are asked once, pre-filled from the current git config when one exists. Modules generate personal files from them: `config/git/local` (identity) and `config/git/allowed_signers`.

## 7. The `grove` command

| Command | Does |
|---------|------|
| `grove install [module…]` | Runs `check` for each module (all, or the ones named) and `apply` where needed. Asks for personal values first if `local.env` is missing. |
| `grove check` | Prints a status line per module and changes nothing. Exits `0` when all are ok, `3` otherwise. |
| `grove update` | `git pull --ff-only` in project-grove, then `grove install`. |
| `grove list` | Lists modules with their `about` line. |

Options: `--yes` runs unattended. Modules that need you are skipped and listed at the end, with exit code `3`. `--quiet` prints only problems and the summary.

Output uses Everforest Dark colors (green ok, yellow needs work, aqua needs you, red failed), and turns colors off when the output isn't a terminal or `NO_COLOR` is set. Every run writes a full log to `~/.local/state/grove/logs/<date-time>.log`.

When `apply` fails, `grove` stops, shows the error, the log path and the exact command to retry (`grove install <module>`). Modules applied before it stay applied.

## 8. Bootstrap

```sh
curl -fsSL https://raw.githubusercontent.com/gmarques-x/project-grove/main/grove-dotfiles/bootstrap.sh | bash
```

`bootstrap.sh` uses only built-in macOS tools:

1. If the Command Line Tools are missing, it runs `xcode-select --install` and waits (polling `xcode-select -p`) until you finish Apple's dialog.
2. If `~/Developer/project-grove` doesn't exist, it clones the repo there with git (HTTPS). If it exists, it uses it as is.
3. It runs `grove-dotfiles/bin/grove install`. The `grove` link in `~/.local/bin` is created by the zsh module.

The repo must be public for the curl line to work.

## 9. Modules

| # | Module | `check` looks at | `apply` does | Needs you |
|---|--------|------------------|--------------|-----------|
| 05 | config | `~/.config` is a link to `config/` | Moves an existing `~/.config` folder's contents into `config/` (untracked files stay untracked), backs up anything that would be overwritten, creates the link | |
| 10 | xcode-tools | `xcode-select -p` succeeds | Starts `xcode-select --install` | Apple's dialog |
| 20 | homebrew | `brew` exists; `brew bundle check` passes | Starts the official Homebrew installer if missing; `brew bundle install` | Mac password (first install only) |
| 30 | fonts | `grove-fonts/install-fonts.sh --check` exits 0 | `install-fonts.sh --quiet` | |
| 40 | ssh | `~/.ssh/config` is the right link; `~/.ssh/id_ed25519` exists and is loaded in the agent | Links `~/.ssh/config`; if there is no key, runs `ssh-keygen` (ed25519) and `ssh-add --apple-use-keychain` | The passphrase, when creating a key |
| 50 | git | `local.env` values match `git config user.name/email`; signing settings present; `~/.gitconfig` retired | Writes `config/git/local` and `allowed_signers`; backs up and removes `~/.gitconfig` | |
| 60 | github | `gh auth status` is signed in with `admin:ssh_signing_key`; the key's fingerprint is in `gh ssh-key list` as a signing key | `gh auth login` / `gh auth refresh -s admin:ssh_signing_key`; `gh ssh-key add --type signing` | Browser login |
| 70 | zsh | `~/.zshenv` link; `~/.local/bin/grove` link; `~/.zprofile` and `~/.zshrc` retired; `starship` installed | Creates the links; moves the old files to the backup folder after carrying their content over | |
| 80 | macos-finder | Every line in `settings.txt` matches the live value; the List view block matches | Writes the settings that differ, imports the block, restarts Finder only if something changed; prints the sidebar checklist | |

**git config** (tracked, `config/git/config`):

```ini
[include]
    path = ~/.config/git/local          # generated: [user] name, email, signingkey
[init]
    defaultBranch = main
[gpg]
    format = ssh
[gpg "ssh"]
    allowedSignersFile = ~/.config/git/allowed_signers
[commit]
    gpgsign = true
[tag]
    gpgsign = true
[credential "https://github.com"]
    helper =
    helper = !/opt/homebrew/bin/gh auth git-credential
[credential "https://gist.github.com"]
    helper =
    helper = !/opt/homebrew/bin/gh auth git-credential
```

**zsh** (`config/zsh/`):

- `.zshenv`: `ZDOTDIR`, the XDG variables (`XDG_CONFIG_HOME`, `XDG_STATE_HOME`), and `~/.local/bin` on the PATH
- `.zprofile`: `brew shellenv`; `ssh-add --apple-load-keychain -q`
- `.zshrc`: loads `conf.d/*.zsh` in order: `history.zsh` (history in `~/.local/state/zsh/history`) and `prompt.zsh` (`eval "$(starship init zsh)"`). The Shell module adds more files later.

**Starship prompt** (`config/starship.toml`): the Everforest port's layout and colors.

| Element | Port's color | Starship |
|---------|--------------|----------|
| Ruler line above the prompt | `#596763` | `fill` with `─` |
| Folder | green `#A7C080` | `directory.style` |
| Folder path above a repo root | aqua `#83C092` | `directory.before_repo_root_style` (the port colors folders outside home aqua; Starship can't tell those apart, so aqua marks the path leading to a repo instead) |
| Read-only folder | red `#E67E80` | `directory.read_only_style` |
| Git branch, clean | blue `#7FBBB3` | `git_branch` |
| Untracked files | yellow `#DBBC7F` | `git_status` (untracked) |
| Modified or staged | purple `#D699B6` | `git_status` (modified, staged) |
| Command duration, jobs | grey `#859289` | `cmd_duration`, `jobs` |
| Exit status | red `#E67E80` | `status` |
| Prompt character | fg `#D3C6AA`; red `#E67E80` after an error | `character` (`❯`) |

The prompt is two lines: ruler and info on the first, `❯` on the second. It uses no Nerd Font icons (JetBrains Mono doesn't include them), matching the port's default "fancy" mode.

**Finder** (`modules/80-macos-finder/settings.txt`): one setting per line, taken from `artifacts/finder-changes.md`. Excerpt:

```
# domain                key                              type     value
com.apple.finder        NewWindowTarget                  string   PfHm      # new windows open Home
com.apple.finder        ShowExternalHardDrivesOnDesktop  bool     false
NSGlobalDomain          AppleShowAllExtensions           bool     true
…
```

`FavoriteTagNames` (an array) is written by the module directly. The List view block is imported with `defaults write com.apple.finder StandardViewSettings "$(cat StandardViewSettings.plist)"`, a method already tested.

## 10. Linking and backups (`lib/link.sh`)

`grove_link <target> <link>`:

- Link already points to target: nothing to do.
- Nothing at the link path: create the link (and its parent folder).
- A real file or folder is there: move it to `~/.local/state/grove/backup/<date-time>/<same path>`, then create the link. Nothing is deleted.
- A link pointing somewhere else: report it and stop. Grove doesn't overwrite links it didn't make.

`grove_link_check` returns `0` or `3` with the same rules and changes nothing.

## 11. Migrating this Mac

The first `grove install` on this Mac turns today's hand-made setup into the managed one:

1. `05-config`: `~/.config/gh/` moves into `config/gh/` (ignored by git); `~/.config` becomes the link.
2. `40-ssh`: `~/.ssh/config` goes to the backup folder and becomes a link to the same content. Keys are untouched.
3. `50-git`: identity and signing settings now come from `config/git/`; `~/.gitconfig` goes to the backup folder.
4. `70-zsh`: `~/.zprofile` and `~/.zshrc` go to the backup folder; their content (Homebrew, SSH key loading, `~/.local/bin`) already lives in `config/zsh/`.

## 12. Testing

- **Unit tests (bats-core):** `lib/link.sh` cases from section 10, `lib/defaults.sh` against a dummy domain (`com.grove.test`), `lib/local.sh` (prompting with defaults, writing and reading), and `check` for each module returning ok, needs work and needs you. Tests run with `HOME` and every `GROVE_*` variable pointed at a temporary folder.
- **Lint:** `shellcheck` on every script.
- **This Mac:** run the migration. Afterwards `grove check` reports every module ok, `git verify-commit` succeeds on a new commit, a new Terminal window shows the Starship prompt, and the Finder settings are unchanged.
- **Fresh install:** a new macOS user account runs the bootstrap line and ends with `grove check` all ok. (Command Line Tools and Homebrew are shared by all accounts, so those two modules report ok there; their install paths are covered by unit tests.)

## 13. Done when

1. Every bats test and shellcheck passes.
2. The migration on this Mac passes the checks in section 12.
3. The test-account install ends with `grove check` all ok.
4. `project-grove` is public, with a README covering the bootstrap line, the `grove` commands and the `~/.config` safety note.

## 14. Later

- Shell module: aliases, plugins (syntax highlighting, autosuggestions), completions.
- Terminal module (e.g. Ghostty) and Editor module, each themed in Everforest.
- Light variants of the prompt and terminal, and following macOS Appearance.
- Finder sidebar automation.
- More macOS settings, recorded with `.recording/` tools.
