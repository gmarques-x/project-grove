# grove-dotfiles Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `grove` command, its module framework and the nine foundation modules, then migrate this Mac onto it.

**Architecture:** Bash 3.2 scripts. `bin/grove` discovers `modules/NN-name/module.sh` files and runs each one's `check`/`apply` in a subshell. Shared helpers live in `lib/`. `config/` is linked as `~/.config` and protected by an allowlist `.gitignore`.

**Tech Stack:** bash 3.2 (`/bin/bash`), macOS `defaults`/`PlistBuddy`, bats-core 1.14 (tests), shellcheck 0.11 (lint), Homebrew, gh, Starship 1.27.

**Spec:** `grove-dotfiles/docs/specs/2026-11-09-grove-dotfiles-foundation-design.md`

## Global Constraints

- Every script runs under `/bin/bash` 3.2: no associative arrays, no `mapfile`, no `${var,,}`, no `[[ -v ]]`.
- `bootstrap.sh`, `bin/grove`, `lib/*` and modules 05–30 use only built-in macOS tools.
- Module `check` exit codes: `0` ok, `3` needs work, `4` needs you. `check` never changes anything.
- `grove check` exits `0` when all modules are ok, `3` otherwise. `grove install` exits `0` on success, `1` on a failed `apply`, `3` when `--yes` skipped a needs-you module.
- Paths: `GROVE_ROOT` = grove-dotfiles folder, `GROVE_CONFIG` = `$GROVE_ROOT/config`, `GROVE_STATE` = `$HOME/.local/state/grove`, `GROVE_LOCAL` = `$HOME/.config/grove/local.env`. Every helper reads these (and `HOME`) from the environment so tests can redirect them.
- Nothing is deleted: anything replaced moves to `$GROVE_STATE/backup/$GROVE_RUN_ID/<path relative to $HOME>`.
- Personal values (`GROVE_NAME`, `GROVE_EMAIL`, `GROVE_GITHUB_USER`) never appear in tracked files.
- Output colors (Everforest Dark): ok `#A7C080`, needs work `#DBBC7F`, needs you `#83C092`, failed `#E67E80`, dim `#859289`. Colors off when stdout isn't a terminal or `NO_COLOR` is set.
- The private Finder recording is never committed, published or referenced from tracked files (it is gitignored).
- Commits are signed (already configured globally). End each commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Run tests with `bats grove-dotfiles/tests` from `project-grove/`; lint with `shellcheck -x` on every changed script.

## Review Focus

1. **Prompts while piped from curl.** In `curl … | bash`, stdin is the script itself. Prompts must read from the terminal (`GROVE_TTY`, default `/dev/tty`), never stdin. Test: Task 2 `ask reads from GROVE_TTY, not stdin`.
2. **`grove` called through its symlink or from another folder.** `~/.local/bin/grove` is a link, so `GROVE_ROOT` must resolve through it. Test: Task 6 `grove resolves its root when called through a symlink from another folder`.
3. **Paths with spaces.** Backup and link paths must survive spaces. Test: Task 3 `link backs up a file whose path contains spaces`.
4. **Second run changes nothing.** When `check` is ok, `apply` must not run. Test: Task 6 `install skips apply when check is ok`.
5. **Existing `~/.config` content that collides with tracked files** (e.g. a real `~/.config/git/config`). It must go to the backup, not overwrite the tracked file and not be silently lost. Test: Task 7 `config moves colliding files to the backup`.

---

### Task 1: Scaffold, Brewfile, allowlist and test harness

**Files:**
- Create: `grove-dotfiles/Brewfile`, `grove-dotfiles/config/.gitignore`, `grove-dotfiles/tests/helpers.bash`, `grove-dotfiles/tests/config_allowlist.bats`

**Interfaces:**
- Produces: `tests/helpers.bash` with `grove_test_setup` (creates `$BATS_TEST_TMPDIR/home`, exports `HOME`, `GROVE_ROOT` = real grove-dotfiles path, `GROVE_CONFIG`, `GROVE_STATE`, `GROVE_LOCAL`, `GROVE_RUN_ID=test`, `GROVE_TTY=$BATS_TEST_TMPDIR/tty`, `NO_COLOR=1`, prepends `$BATS_TEST_TMPDIR/stubs` to `PATH`) and `stub <cmd> <script body>` (writes an executable stub into that stubs folder). Every later `.bats` file starts with `load helpers` and `setup() { grove_test_setup; }`.

- [ ] **Step 1: Write the failing test** `tests/config_allowlist.bats`:
  - `untracked app files in config are ignored`: `git -C "$GROVE_ROOT" check-ignore -q config/gh/hosts.yml` succeeds.
  - `tracked config entries are not ignored`: `check-ignore` fails for `config/zsh/.zshrc`, `config/git/config`, `config/ssh/config`, `config/starship.toml`.
  - `generated personal files are ignored`: `check-ignore` succeeds for `config/git/local`, `config/git/allowed_signers`, `config/grove/local.env`.
- [ ] **Step 2: Run** `bats grove-dotfiles/tests/config_allowlist.bats`. Expected: FAIL (no `.gitignore`).
- [ ] **Step 3: Create** `config/.gitignore`: `/*` then `!/.gitignore`, `!/git/`, `!/ssh/`, `!/zsh/`, `!/starship.toml`, then `/git/local`, `/git/allowed_signers`. Create `Brewfile` with `brew "git"`, `brew "python"`, `brew "gh"`, `brew "starship"`, `brew "bats-core"`, `brew "shellcheck"`. Create `tests/helpers.bash` per Interfaces.
- [ ] **Step 4: Run** the test. Expected: PASS (3 tests).
- [ ] **Step 5: Commit** `Scaffold grove-dotfiles: Brewfile, config allowlist, test harness`.

### Task 2: `lib/ui.sh` — output and prompts

**Files:**
- Create: `grove-dotfiles/lib/ui.sh`, `grove-dotfiles/tests/ui.bats`

**Interfaces:**
- Produces: `grove_ok MSG`, `grove_work MSG`, `grove_you MSG`, `grove_fail MSG` (one status line each; `grove_fail` writes to stderr), `grove_step TITLE` (section header), `grove_info MSG` (dim line; silent when `GROVE_QUIET=1`), `grove_ask PROMPT DEFAULT` → prints the answer on stdout (the default when the reply is empty).

- [ ] **Step 1: Write failing tests:**
  - `status lines carry their label`: with `NO_COLOR=1`, `grove_ok "fonts"` outputs `ok  fonts`-style text containing `ok` and `fonts`; `grove_work` contains `needs work`; `grove_you` contains `needs you`; `grove_fail` output appears on stderr only.
  - `no color codes when NO_COLOR is set`: output contains no `\033[`.
  - `ask returns the default on an empty reply`: `GROVE_TTY` file holds an empty line; `grove_ask "Email" "a@b.c"` prints `a@b.c`.
  - `ask reads from GROVE_TTY, not stdin`: `GROVE_TTY` holds `typed`; run `echo piped | grove_ask "Q" "d"`; output is `typed`.
  - `info is silent when quiet`: `GROVE_QUIET=1 grove_info x` prints nothing.
- [ ] **Step 2: Run** `bats grove-dotfiles/tests/ui.bats`. Expected: FAIL.
- [ ] **Step 3: Implement** `lib/ui.sh`. Colors as 24-bit escapes from Global Constraints, enabled only when `[ -t 1 ]` and `NO_COLOR` is unset. `grove_ask` prints the prompt as `PROMPT [DEFAULT]: ` to stderr and reads one line from `${GROVE_TTY:-/dev/tty}`.
- [ ] **Step 4: Run** the tests and `shellcheck -x lib/ui.sh`. Expected: PASS, no warnings.
- [ ] **Step 5: Commit** `Add grove output and prompt helpers`.

### Task 3: `lib/link.sh` — links with backup

**Files:**
- Create: `grove-dotfiles/lib/link.sh`, `grove-dotfiles/tests/link.bats`

**Interfaces:**
- Consumes: `grove_info`, `grove_fail` (Task 2).
- Produces: `grove_link TARGET LINK` (returns 0 on success, 1 when LINK is a symlink to something else), `grove_link_check TARGET LINK` (returns 0 or 3, changes nothing), `grove_backup PATH` (moves PATH into the backup folder, prints the new location, returns 0; no-op returning 0 when PATH doesn't exist).

- [ ] **Step 1: Write failing tests:**
  - `link creates a missing link and its parent folder`: `grove_link "$t" "$HOME/a/b/link"` → `[ -L ]` and `readlink` equals `$t`.
  - `link leaves a correct link alone`: second call returns 0 and backup folder stays empty.
  - `link backs up a real file before linking`: `$HOME/.zshrc` with content `x` → after linking, `$GROVE_STATE/backup/test/.zshrc` contains `x`.
  - `link backs up a file whose path contains spaces`: same with `$HOME/My Folder/file`.
  - `link refuses a symlink pointing elsewhere`: existing link to `/tmp/other` → returns 1, link unchanged.
  - `link_check returns 0, 3, 3`: correct link → 0; missing → 3; real file → 3; nothing created by any call.
- [ ] **Step 2: Run** `bats grove-dotfiles/tests/link.bats`. Expected: FAIL.
- [ ] **Step 3: Implement** `lib/link.sh`. Backup path = `$GROVE_STATE/backup/$GROVE_RUN_ID/${PATH#$HOME/}`. Use `mv`, `mkdir -p`, `ln -s`. Quote every path.
- [ ] **Step 4: Run** tests and shellcheck. Expected: PASS.
- [ ] **Step 5: Commit** `Add link and backup helpers`.

### Task 4: `lib/local.sh` — personal values

**Files:**
- Create: `grove-dotfiles/lib/local.sh`, `grove-dotfiles/tests/local.bats`

**Interfaces:**
- Consumes: `grove_ask` (Task 2).
- Produces: `grove_local_load` (sources `$GROVE_LOCAL` if present; returns 0 if all three values are set, 3 otherwise), `grove_local_ensure` (loads; asks for missing values with defaults; writes the file; exports the three variables), `grove_local_write` (writes the three variables, mode 600).

- [ ] **Step 1: Write failing tests:**
  - `ensure asks with defaults from git config`: stub `git` so `git config --global user.name` prints `gmarques-x` and `user.email` prints `g@x.y`; `GROVE_TTY` has three empty lines; after `grove_local_ensure`, the file contains `GROVE_NAME="gmarques-x"`, `GROVE_EMAIL="g@x.y"`, `GROVE_GITHUB_USER="gmarques-x"` (GitHub default = name).
  - `ensure keeps existing values without asking`: pre-written file; `GROVE_TTY` is `/dev/null`; values unchanged.
  - `local file is private`: mode is `600`.
  - `values with quotes and spaces survive a round trip`: name `Gus "G" Marques` written and loaded back identically.
- [ ] **Step 2: Run** `bats grove-dotfiles/tests/local.bats`. Expected: FAIL.
- [ ] **Step 3: Implement** `lib/local.sh`. Write values with `printf '%s=%q\n'` so they reload safely with `source`.
- [ ] **Step 4: Run** tests and shellcheck. Expected: PASS.
- [ ] **Step 5: Commit** `Add personal values helpers`.

### Task 5: `lib/defaults.sh` — macOS settings from data files

**Files:**
- Create: `grove-dotfiles/lib/defaults.sh`, `grove-dotfiles/tests/defaults.bats`, `grove-dotfiles/tests/fixtures/settings.txt`

**Interfaces:**
- Produces: `grove_defaults_check FILE` (prints one line per mismatch as `domain key: live → wanted`; returns 0 or 3), `grove_defaults_apply FILE` (writes only the mismatched settings; prints the number written on stdout).
- File format, one setting per line: `domain key type value [# comment]`; `type` is `string`, `bool`, `int` or `float`; blank lines and `#` lines are skipped; `value` has no spaces.

- [ ] **Step 1: Write failing tests** (fixture uses domain `com.grove.test` with one `string`, one `bool`, one `int`; `teardown` runs `defaults delete com.grove.test`):
  - `check reports every setting when the domain is empty`: returns 3 and prints 3 lines.
  - `apply writes them and reports 3`: then `defaults read com.grove.test` values match; `bool true` reads back as `1`.
  - `check is ok after apply`: returns 0, prints nothing.
  - `apply writes only what differs`: change one value by hand → apply prints `1`.
  - `comments and blank lines are ignored`.
- [ ] **Step 2: Run** `bats grove-dotfiles/tests/defaults.bats`. Expected: FAIL.
- [ ] **Step 3: Implement** `lib/defaults.sh`. Read live values with `defaults read DOMAIN KEY 2>/dev/null`; normalize `bool` `true/false` to `1/0` before comparing; write with `defaults write DOMAIN KEY -TYPE VALUE`.
- [ ] **Step 4: Run** tests and shellcheck. Expected: PASS.
- [ ] **Step 5: Commit** `Add macOS settings helpers`.

### Task 6: `bin/grove` — the command

**Files:**
- Create: `grove-dotfiles/bin/grove`, `grove-dotfiles/tests/grove.bats`, `grove-dotfiles/tests/fixtures/modules/{10-ok,20-work,30-you,40-broken}/module.sh`

**Interfaces:**
- Consumes: all of `lib/` (Tasks 2–5).
- Produces: the `grove` CLI (`install [module…]`, `check`, `update`, `list`, `--yes`, `--quiet`, `--help`). Module discovery: folders in `${GROVE_MODULES:-$GROVE_ROOT/modules}` sorted by name; a module is addressed by its full folder name or the part after `NN-` (`fonts` = `30-fonts`). Each module runs in a subshell with `lib/*.sh` sourced and `MODULE_DIR` set to its folder. Run ID `GROVE_RUN_ID=$(date +%Y%m%d-%H%M%S)` unless set. Log: everything also appended to `$GROVE_STATE/logs/$GROVE_RUN_ID.log`. Before modules run, `install` calls `grove_local_ensure` (skipped when `--yes` and the file exists).

Fixture modules: `10-ok` (check 0), `20-work` (check 3 until its apply creates `$HOME/applied-20`), `30-you` (check 4), `40-broken` (check 3, apply exits 1). Each apply appends its name to `$HOME/apply.log`.

- [ ] **Step 1: Write failing tests** (with `GROVE_MODULES` pointed at the fixtures and a pre-written `local.env`):
  - `list shows each module and its about line`.
  - `check prints a status per module and exits 3`; with only `10-ok` present it exits 0.
  - `check changes nothing`: `$HOME/apply.log` doesn't exist afterwards.
  - `install skips apply when check is ok`: `apply.log` never contains `10-ok`.
  - `install applies needs-work modules and stops at a failure`: `grove install 20-work 40-broken` exits 1, `apply.log` has `20-work` then `40-broken`, and output names `grove install broken` as the retry command.
  - `install --yes skips needs-you modules and exits 3`: `grove --yes install 30-you` exits 3, output lists `30-you`.
  - `a run writes a log`: a file appears in `$GROVE_STATE/logs/`.
  - `grove resolves its root when called through a symlink from another folder`: link `$HOME/.local/bin/grove` → `bin/grove`, `cd /`, run `grove list` without `GROVE_ROOT` set → lists the real modules.
  - `unknown module name fails with a message`: exit 1, stderr names it.
  - `update pulls then installs`: stub `git` records its arguments; `grove update` calls `git -C <project-grove> pull --ff-only` before any module runs; a failing pull exits 1 and runs no module.
- [ ] **Step 2: Run** `bats grove-dotfiles/tests/grove.bats`. Expected: FAIL.
- [ ] **Step 3: Implement** `bin/grove`. Resolve its own path by following symlinks with `cd -P` / `readlink` in a loop (bash 3.2 safe). `update` runs `git -C "$GROVE_ROOT/.." pull --ff-only` then `install`.
- [ ] **Step 4: Run** tests and shellcheck. Expected: PASS.
- [ ] **Step 5: Commit** `Add the grove command`.

### Task 7: Modules 05-config, 10-xcode-tools, 20-homebrew, 30-fonts

**Files:**
- Create: `modules/05-config/module.sh`, `modules/10-xcode-tools/module.sh`, `modules/20-homebrew/module.sh`, `modules/30-fonts/module.sh`, `tests/modules_base.bats`

**Interfaces:**
- Consumes: `grove_link`, `grove_link_check`, `grove_backup` (Task 3); module contract (Task 6).
- Produces: `~/.config` → `$GROVE_CONFIG` (other modules rely on it).

Behavior per spec section 9:
- `05-config`: ok when `~/.config` links to `$GROVE_CONFIG`. Apply: if `~/.config` is a real folder, move each entry into `$GROVE_CONFIG/` unless that name already exists there; colliding entries go to the backup. Then link.
- `10-xcode-tools`: ok when `xcode-select -p` succeeds; otherwise needs you; apply runs `xcode-select --install` and waits (poll every 5 s) until `xcode-select -p` succeeds.
- `20-homebrew`: needs you when `/opt/homebrew/bin/brew` is missing (apply prints the official install command and runs it: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`); needs work when `brew bundle check --file "$GROVE_ROOT/Brewfile"` fails (apply runs `brew bundle install --file …`).
- `30-fonts`: check = `"$GROVE_ROOT/../grove-fonts/install-fonts.sh" --check --quiet` (exit 0 → 0, 3 → 3, else → 1); apply = `install-fonts.sh --quiet`.

- [ ] **Step 1: Write failing tests** (stub `xcode-select`, `brew`, and a fake `grove-fonts/install-fonts.sh` via a temp `GROVE_ROOT/..` copy where needed):
  - `config moves existing app folders into the repo config`: real `$HOME/.config/gh/hosts.yml` → after apply, `$GROVE_CONFIG/gh/hosts.yml` exists and `$HOME/.config` is a link. (Use a temp copy of `config/` as `GROVE_CONFIG`.)
  - `config moves colliding files to the backup`: real `$HOME/.config/git/config` with `x` → tracked `$GROVE_CONFIG/git/config` unchanged, backup holds `x`.
  - `config check is ok once linked`.
  - `xcode-tools needs you when missing` (stub exits 2) and `is ok when present`.
  - `homebrew needs work when bundle check fails` and `is ok when it passes`.
  - `fonts maps install-fonts exit codes` (0 → 0, 3 → 3).
- [ ] **Step 2: Run** `bats grove-dotfiles/tests/modules_base.bats`. Expected: FAIL.
- [ ] **Step 3: Implement** the four modules. `20-homebrew` must find `brew` at `/opt/homebrew/bin/brew` even when it's not yet on `PATH` (overridable with `GROVE_BREW` for tests).
- [ ] **Step 4: Run** tests and shellcheck. Expected: PASS.
- [ ] **Step 5: Commit** `Add config, Xcode tools, Homebrew and fonts modules`.

### Task 8: Modules 40-ssh and 50-git with their config files

**Files:**
- Create: `modules/40-ssh/module.sh`, `modules/50-git/module.sh`, `config/ssh/config`, `config/git/config`, `tests/modules_git_ssh.bats`

**Interfaces:**
- Consumes: Tasks 3–4, `GROVE_NAME`, `GROVE_EMAIL` from `grove_local_ensure`.
- Produces: `config/git/local` (`[user]` name, email, `signingkey = $HOME/.ssh/id_ed25519.pub`) and `config/git/allowed_signers` (`<email> <key type> <key>`), both generated.

Content: `config/ssh/config` and `config/git/config` exactly as in spec section 9 (ssh: `Host *`, `UseKeychain yes`, `AddKeysToAgent yes`, `IdentityFile ~/.ssh/id_ed25519`).

- `40-ssh`: needs work when `~/.ssh/config` isn't the link; needs you when `~/.ssh/id_ed25519` is missing; needs work when the key's fingerprint isn't in `ssh-add -l`. Apply: `mkdir -m 700 ~/.ssh`, link config, `ssh-keygen -t ed25519 -C "$GROVE_EMAIL" -f ~/.ssh/id_ed25519` if missing (interactive), `ssh-add --apple-use-keychain ~/.ssh/id_ed25519`.
- `50-git`: needs work when `config/git/local` or `allowed_signers` is missing or out of date with `local.env` and the public key, or when a real `~/.gitconfig` exists. Apply: write both files, back up `~/.gitconfig`.

- [ ] **Step 1: Write failing tests** (stub `ssh-add`, `ssh-keygen`; create a fake key pair with real `ssh-keygen -N ''` in the temp `HOME`):
  - `ssh needs you without a key`, `ssh needs work when the config isn't linked`, `ssh is ok when linked and loaded`.
  - `git writes identity and allowed_signers from local values`: files contain `gmarques-x`, the email, and the public key text.
  - `git retires a real ~/.gitconfig into the backup`.
  - `git check notices a changed email`: change `GROVE_EMAIL` → returns 3.
  - `git config parses`: `git config --file config/git/config --list` succeeds and includes `gpg.format=ssh`.
- [ ] **Step 2: Run** `bats grove-dotfiles/tests/modules_git_ssh.bats`. Expected: FAIL.
- [ ] **Step 3: Implement** both modules and config files.
- [ ] **Step 4: Run** tests and shellcheck. Expected: PASS.
- [ ] **Step 5: Commit** `Add SSH and git modules`.

### Task 9: Module 60-github

**Files:**
- Create: `modules/60-github/module.sh`, `tests/modules_github.bats`

**Interfaces:**
- Consumes: `~/.ssh/id_ed25519.pub` (Task 8), `GROVE_GITHUB_USER`.

Behavior: needs you when `gh auth status` fails or its scopes lack `admin:ssh_signing_key`; needs work when the key's fingerprint (`ssh-keygen -lf`) is not among `gh ssh-key list` signing keys (compare key text). Apply: `gh auth login --hostname github.com --git-protocol https --web --scopes admin:ssh_signing_key,workflow` when signed out, `gh auth refresh -h github.com -s admin:ssh_signing_key` when the scope is missing, then `gh ssh-key add ~/.ssh/id_ed25519.pub --type signing --title "<computer name> · Project Grove"` (computer name from `scutil --get ComputerName`).

- [ ] **Step 1: Write failing tests** with a stubbed `gh`: `needs you when signed out`, `needs you without the signing scope`, `needs work when the key isn't uploaded`, `ok when uploaded`, `apply uploads as a signing key` (stub records its arguments; assert `--type signing`).
- [ ] **Step 2: Run** `bats grove-dotfiles/tests/modules_github.bats`. Expected: FAIL.
- [ ] **Step 3: Implement** the module.
- [ ] **Step 4: Run** tests and shellcheck. Expected: PASS.
- [ ] **Step 5: Commit** `Add GitHub module`.

### Task 10: Module 70-zsh, zsh files and the Starship prompt

**Files:**
- Create: `modules/70-zsh/module.sh`, `config/zsh/.zshenv`, `config/zsh/.zprofile`, `config/zsh/.zshrc`, `config/zsh/conf.d/10-history.zsh`, `config/zsh/conf.d/90-prompt.zsh`, `config/starship.toml`, `tests/modules_zsh.bats`

**Interfaces:**
- Consumes: Task 3 helpers.
- Produces: links `~/.zshenv` → `$GROVE_CONFIG/zsh/.zshenv` and `~/.local/bin/grove` → `$GROVE_ROOT/bin/grove`.

Content (spec section 9):
- `.zshenv`: `export ZDOTDIR="$HOME/.config/zsh"`, `XDG_CONFIG_HOME="$HOME/.config"`, `XDG_STATE_HOME="$HOME/.local/state"`, `~/.local/bin` prepended to `PATH` once.
- `.zprofile`: `eval "$(/opt/homebrew/bin/brew shellenv zsh)"` (guarded by `[ -x ]`), `ssh-add --apple-load-keychain -q 2>/dev/null`.
- `.zshrc`: sources `$ZDOTDIR/conf.d/*.zsh` in order.
- `10-history.zsh`: `HISTFILE="$XDG_STATE_HOME/zsh/history"` (creates the folder), `HISTSIZE=50000`, `SAVEHIST=50000`, `setopt share_history hist_ignore_dups hist_ignore_space`.
- `90-prompt.zsh`: `eval "$(starship init zsh)"` when `starship` exists.
- `starship.toml`: two-line layout from the spec table. Format line 1: `$directory$git_branch$git_status$fill$cmd_duration$jobs$status`, then `$line_break$character`. `fill.symbol = "─"`, `fill.style = "fg:#596763"`; `directory.style = "fg:#A7C080"`, `directory.before_repo_root_style = "fg:#83C092"`, `directory.read_only_style = "fg:#E67E80"`; `git_branch.style = "fg:#7FBBB3"`, `git_branch.symbol = ""`; `git_status.untracked` styled `#DBBC7F`, modified/staged `#D699B6`; `cmd_duration.style` and `jobs.style` `fg:#859289`; `status.disabled = false`, `status.style = "fg:#E67E80"`; `character.success_symbol = "[❯](fg:#D3C6AA)"`, `character.error_symbol = "[❯](fg:#E67E80)"`. No Nerd Font glyphs.

Module: ok when both links are right, no real `~/.zprofile`/`~/.zshrc` exist, and `starship` is on PATH or in `/opt/homebrew/bin`. Apply: back up `~/.zprofile` and `~/.zshrc`, create both links.

- [ ] **Step 1: Write failing tests:**
  - `zsh links zshenv and grove`, `zsh retires old zprofile and zshrc into the backup`, `zsh check is ok after apply`.
  - `zsh files parse`: `zsh -n` succeeds on each file in `config/zsh/`.
  - `a login shell loads the Grove setup`: `env -i HOME="$HOME" zsh -lic 'echo $ZDOTDIR; echo $HISTFILE'` prints the config path and `…/.local/state/zsh/history` (after apply, with the temp `HOME`).
  - `starship accepts the config`: `STARSHIP_CONFIG=config/starship.toml starship print-config >/dev/null 2>err` succeeds and `err` is empty.
- [ ] **Step 2: Run** `bats grove-dotfiles/tests/modules_zsh.bats`. Expected: FAIL.
- [ ] **Step 3: Implement** the module and files.
- [ ] **Step 4: Run** tests and shellcheck (shellcheck only on `module.sh`; zsh files are checked with `zsh -n`). Expected: PASS.
- [ ] **Step 5: Commit** `Add zsh module and Everforest Starship prompt`.

### Task 11: Module 80-macos-finder

**Files:**
- Create: `modules/80-macos-finder/module.sh`, `modules/80-macos-finder/settings.txt`, `modules/80-macos-finder/StandardViewSettings.plist` (copy of `.recording/finder/blocks/StandardViewSettings.plist`), `tests/modules_finder.bats`

**Interfaces:**
- Consumes: `grove_defaults_check`, `grove_defaults_apply` (Task 5).

`settings.txt`: the 14 scalar settings from the "Apply with" block of the Finder recording (a local, ignored file under `.recording/finder/`: read it, never commit or link to it), in the Task 5 format. The module also handles `FavoriteTagNames` (wanted: empty-string array) and the `StandardViewSettings` block (compare `defaults export com.apple.finder - | plutil -extract StandardViewSettings xml1 -o - -` with the file, normalized through `plutil -convert json`). Apply restarts Finder (`killall Finder`) only when it wrote something. After apply, it prints the sidebar checklist from the spec (shown: Applications, Home, Developer, Documents, Downloads, iCloud Drive, Macintosh HD; hidden: Recents, Shared, AirDrop, Desktop). Domains are overridable for tests with `GROVE_FINDER_DOMAIN` and `GROVE_GLOBAL_DOMAIN`.

- [ ] **Step 1: Write failing tests** (domains pointed at `com.grove.test` and `com.grove.testglobal`; stub `killall`):
  - `finder needs work on an empty domain`, `finder is ok after apply`.
  - `apply restarts Finder only when something changed`: second apply → stub `killall` not called.
  - `the view block round-trips`: after apply, the exported block equals the file.
  - `settings.txt lists the 14 recorded settings`: `grep -cv '^\s*\(#\|$\)'` equals 14.
- [ ] **Step 2: Run** `bats grove-dotfiles/tests/modules_finder.bats`. Expected: FAIL.
- [ ] **Step 3: Implement** the module and data files.
- [ ] **Step 4: Run** tests and shellcheck. Expected: PASS.
- [ ] **Step 5: Commit** `Add Finder settings module`.

### Task 12: `bootstrap.sh` and README

**Files:**
- Create: `grove-dotfiles/bootstrap.sh`, `grove-dotfiles/README.md`, `tests/bootstrap.bats`

Behavior (spec section 8): wait for Command Line Tools (same logic as `10-xcode-tools`, inlined; bootstrap can't source lib before cloning), clone `https://github.com/gmarques-x/project-grove.git` into `${GROVE_CLONE_DIR:-$HOME/Developer/project-grove}` unless it exists, then `exec` its `grove-dotfiles/bin/grove install`. Prompts read from `/dev/tty`.

README sections: what Project Grove is (one paragraph), the bootstrap line, `grove` commands, what each module does (table), the `~/.config` safety note ("deleting or re-cloning the repo deletes ~/.config"), how to add a module, credits (Everforest by sainnhe; Starship).

- [ ] **Step 1: Write failing tests** (stub `xcode-select`, `git`; the clone dir points into the temp folder; stub the cloned `bin/grove` to record its arguments):
  - `bootstrap clones when the folder is missing` (stub `git` records `clone` and the URL).
  - `bootstrap reuses an existing clone` (no `git clone` call).
  - `bootstrap runs grove install` (recorded args = `install`).
  - `bootstrap works when piped`: `cat bootstrap.sh | bash` with the same stubs succeeds.
- [ ] **Step 2: Run** `bats grove-dotfiles/tests/bootstrap.bats`. Expected: FAIL.
- [ ] **Step 3: Implement** `bootstrap.sh` and write the README.
- [ ] **Step 4: Run** the full suite `bats grove-dotfiles/tests` and `shellcheck -x` on all scripts. Expected: all PASS, no warnings.
- [ ] **Step 5: Commit** `Add bootstrap and README`.

### Task 13: Migrate this Mac

Changes the real home folder. Run only after Tasks 1–12 pass.

- [ ] **Step 1:** Record the before state: `ls -la ~ ~/.config ~/.ssh`, `git config --global --list`, and `grove check` from the repo (`grove-dotfiles/bin/grove check`). Expected: 05-config, 40-ssh, 50-git and 70-zsh need work; the rest are ok.
- [ ] **Step 2:** Run `grove-dotfiles/bin/grove install`. Answer the three prompts with the pre-filled defaults.
- [ ] **Step 3:** Verify: `grove check` exits 0. `readlink ~/.config` points to the repo. `~/.config/gh/hosts.yml` still exists. `git config user.email` prints `you@example.com`. The backup folder holds `.gitconfig`, `.zprofile`, `.zshrc` and `.ssh/config`. `git status` in project-grove shows no untracked files from `config/`.
- [ ] **Step 4:** Verify signing: a signed empty commit in a scratch repo passes `git verify-commit HEAD`.
- [ ] **Step 5:** Verify the shell: `zsh -lic 'echo $ZDOTDIR; command -v grove; starship --version'` prints `~/.config/zsh`, `~/.local/bin/grove` and the version. Ask the user to open a new Terminal window and confirm the Everforest prompt.
- [ ] **Step 6:** Verify Finder: `grove check` shows `macos-finder` ok, and the 14 values are unchanged.
- [ ] **Step 7:** Commit any fixes found during migration, each with a test reproducing the problem first.

### Task 14: Make project-grove public

Needs the user's explicit go-ahead at this step, because it publishes content.

- [ ] **Step 1:** Confirm with the user that the repo can be made public now.
- [ ] **Step 2:** Check nothing private goes out. The Finder recording is never published (user rule): `git ls-files .recording` and `git log --all --format=%h -- .recording` both print nothing. `git grep -nI -e 'oauth' -e 'token' -e 'BEGIN OPENSSH PRIVATE'` returns nothing. `git ls-files grove-dotfiles/config` lists only allowlisted files.
- [ ] **Step 3:** `gh repo create gmarques-x/project-grove --public --source . --remote origin --push` (description: "A complete macOS desktop overhaul, grown from Everforest.").
- [ ] **Step 4:** Verify: `curl -fsSL https://raw.githubusercontent.com/gmarques-x/project-grove/main/grove-dotfiles/bootstrap.sh | head -1` prints the shebang.

### Task 15: Fresh-install test on a new macOS user account

- [ ] **Step 1:** Ask the user to create a standard account named `grovetest` (System Settings › Users & Groups; needs their password) and log in to it.
- [ ] **Step 2:** In that account, the user pastes the bootstrap line into Terminal and answers the prompts (a test email is fine; skip the GitHub upload for this account by answering the browser step with the main account, or decline and note it).
- [ ] **Step 3:** Verify with the user: `grove check` output. Expected: all ok, except `60-github` if the browser step was declined (acceptable for this test, noted in the result).
- [ ] **Step 4:** Record the outcome in `grove-dotfiles/docs/specs/2026-11-09-grove-dotfiles-foundation-design.md` under a new "Results" heading; commit. The user can delete the test account afterwards.
