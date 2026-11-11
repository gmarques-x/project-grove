# shellcheck disable=SC2016,SC2030,SC2031,SC1090,SC1091,SC2154
load helpers
bats_require_minimum_version 1.5.0

load_module() {
  local f
  for f in "$GROVE_ROOT"/lib/*.sh; do
    # shellcheck source=/dev/null
    . "$f"
  done
  MODULE_DIR="$GROVE_ROOT/modules/$1"
  # shellcheck source=/dev/null
  . "$MODULE_DIR/module.sh"
}

setup() {
  grove_test_setup
  grove_copy_tracked_config "$BATS_TEST_TMPDIR/config"
  export GROVE_CONFIG="$BATS_TEST_TMPDIR/config"
  stub starship 'exit 0'
  # Never let a test fix permissions on the real Homebrew folders.
  stub fake-compaudit 'exit 0'
  export GROVE_COMPAUDIT="$BATS_TEST_TMPDIR/stubs/fake-compaudit"
}

# brew_prefix: a temp Homebrew prefix whose share/ links to the real plugins
# (skips the test when they aren't installed). Prints the prefix.
brew_prefix() {
  local p="$BATS_TEST_TMPDIR/brew" d
  mkdir -p "$p/share"
  for d in zsh-completions zsh-autosuggestions zsh-syntax-highlighting; do
    [ -d "/opt/homebrew/share/$d" ] || return 1
    ln -sfn "/opt/homebrew/share/$d" "$p/share/$d"
  done
  printf '%s\n' "$p"
}

# tool_shell CMD [VAR=value...]: an interactive zsh on a real terminal (script),
# with the temp prefix and the real Homebrew tools on PATH. Output merged, \r and
# script's ^D echo stripped.
tool_shell() {
  local cmd="$1"; shift
  load_module 70-zsh
  [ -L "$HOME/.config" ] || ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply >/dev/null
  env -i HOME="$HOME" PATH="/opt/homebrew/bin:/usr/bin:/bin" HOMEBREW_PREFIX="$BATS_TEST_TMPDIR/brew" GROVE_NO_FETCH=1 "$@" \
    script -q /dev/null /bin/zsh -ic "$cmd" < /dev/null 2>&1 | tr -d '\r\b' | sed 's/\^D//g'
}

# login_shell CMD: a login + interactive zsh on a real terminal (script), as a new
# Terminal or Ghostty window starts it; no Homebrew prefix, no fetch.
login_shell() {
  env -i HOME="$HOME" PATH=/usr/bin:/bin GROVE_BREW=/nonexistent GROVE_NO_FETCH=1 \
    script -q /dev/null /bin/zsh -lic "$1" < /dev/null 2>&1 | tr -d '\r\b' | sed 's/\^D//g'
}

@test "zsh links zshenv and grove" {
  load_module 70-zsh
  run apply
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.zshenv")" = "$GROVE_CONFIG/zsh/.zshenv" ]
  [ "$(readlink "$HOME/.local/bin/grove")" = "$GROVE_ROOT/bin/grove" ]
}

@test "70-zsh links grove-themes into ~/.local/bin" {
  load_module 70-zsh
  run check
  [ "$status" -eq 3 ]
  apply
  [ "$(readlink "$HOME/.local/bin/grove-themes")" = "$GROVE_ROOT/../grove-themes/bin/grove-themes" ]
  rm "$HOME/.local/bin/grove-themes"
  run check
  [ "$status" -eq 3 ]
}

@test "zsh retires old zprofile and zshrc into the backup" {
  load_module 70-zsh
  echo 'export OLD=1' > "$HOME/.zshrc"
  echo 'echo old' > "$HOME/.zprofile"
  run apply
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.zshrc" ]
  [ ! -e "$HOME/.zprofile" ]
  [ "$(cat "$GROVE_STATE/backup/test/.zshrc")" = 'export OLD=1' ]
  [ "$(cat "$GROVE_STATE/backup/test/.zprofile")" = 'echo old' ]
}

@test "zsh check is ok after apply" {
  load_module 70-zsh
  run check
  [ "$status" -eq 3 ]
  apply
  run check
  [ "$status" -eq 0 ]
}

@test "zsh check needs work while an old zshrc exists" {
  load_module 70-zsh
  apply
  echo x > "$HOME/.zshrc"
  run check
  [ "$status" -eq 3 ]
}

@test "zsh files parse" {
  local f
  for f in "$GROVE_ROOT"/config/zsh/.zshenv "$GROVE_ROOT"/config/zsh/.zprofile \
           "$GROVE_ROOT"/config/zsh/.zshrc "$GROVE_RENDERED"/zsh/conf.d/*.zsh; do
    run /bin/zsh -n "$f"
    [ "$status" -eq 0 ]
  done
}

@test "a login shell loads the Grove setup" {
  load_module 70-zsh
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply
  run login_shell 'echo $ZDOTDIR; echo $HISTFILE; print -l $path'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$HOME/.config/zsh" ]
  [ "${lines[1]}" = "$HOME/.local/state/zsh/history" ]
  # nothing else printed at startup, and ~/.local/bin is first, exactly once
  [ "${lines[2]}" = "$HOME/.local/bin" ]
  local n=0 l
  for l in "${lines[@]:2}"; do
    [ "$l" = "$HOME/.local/bin" ] && n=$((n + 1))
  done
  [ "$n" -eq 1 ]
  [ -d "$HOME/.local/state/zsh" ]
}

@test "a login shell prints nothing at startup" {
  load_module 70-zsh
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply
  run login_shell 'echo $ZDOTDIR; echo $HISTFILE'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "zshenv is silent and adds .local/bin to PATH once" {
  load_module 70-zsh
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply
  run env -i HOME="$HOME" PATH="$HOME/.local/bin:/usr/bin:/bin" /bin/zsh -c 'echo $PATH'
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.local/bin:/usr/bin:/bin" ]
}

@test "starship accepts both prompt configs" {
  local f
  for f in starship.toml starship-plain.toml; do
    [ -f "$GROVE_RENDERED/$f" ]
    run env STARSHIP_CONFIG="$GROVE_RENDERED/$f" /opt/homebrew/bin/starship print-config >/dev/null 2>"$BATS_TEST_TMPDIR/err"
    [ "$status" -eq 0 ]
    [ ! -s "$BATS_TEST_TMPDIR/err" ]
  done
}

@test "Terminal.app gets the plain prompt" {
  load_module 70-zsh
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply
  run env -i HOME="$HOME" PATH=/usr/bin:/bin TERM_PROGRAM=Apple_Terminal /bin/zsh -ic 'print -r -- "$STARSHIP_CONFIG"'
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.config/starship-plain.toml" ]
}

@test "Ghostty gets the default prompt" {
  load_module 70-zsh
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply
  run env -i HOME="$HOME" PATH=/usr/bin:/bin TERM_PROGRAM=ghostty /bin/zsh -ic 'print -r -- "$STARSHIP_CONFIG"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "zsh copies the old history when the new one is missing" {
  load_module 70-zsh
  echo 'old cmd' > "$HOME/.zsh_history"
  run check
  [ "$status" -eq 3 ]
  run apply
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.local/state/zsh/history")" = 'old cmd' ]
  [ ! -e "$HOME/.zsh_history" ]
  [ "$(cat "$GROVE_STATE/backup/test/.zsh_history")" = 'old cmd' ]
  run check
  [ "$status" -eq 0 ]
}

@test "zsh never overwrites an existing new history" {
  load_module 70-zsh
  mkdir -p "$HOME/.local/state/zsh"
  echo 'old cmd' > "$HOME/.zsh_history"
  echo 'new cmd' > "$HOME/.local/state/zsh/history"
  run apply
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.local/state/zsh/history")" = 'new cmd' ]
  [ "$(cat "$GROVE_STATE/backup/test/.zsh_history")" = 'old cmd' ]
}

@test "zsh keeps Terminal session files in the state folder" {
  load_module 70-zsh
  run apply
  [ "$status" -eq 0 ]
  [ "$(readlink "$GROVE_CONFIG/zsh/.zsh_sessions")" = "$HOME/.local/state/zsh/sessions" ]
  [ -d "$HOME/.local/state/zsh/sessions" ]
}

@test "zsh moves an existing sessions folder out of the config" {
  load_module 70-zsh
  mkdir -p "$GROVE_CONFIG/zsh/.zsh_sessions"
  echo s > "$GROVE_CONFIG/zsh/.zsh_sessions/A.session"
  run check
  [ "$status" -eq 3 ]
  run apply
  [ "$status" -eq 0 ]
  [ -L "$GROVE_CONFIG/zsh/.zsh_sessions" ]
  [ "$(cat "$HOME/.local/state/zsh/sessions/A.session")" = s ]
  run check
  [ "$status" -eq 0 ]
}

@test "zsh backs up a config sessions folder when the state one already exists" {
  load_module 70-zsh
  mkdir -p "$GROVE_CONFIG/zsh/.zsh_sessions" "$HOME/.local/state/zsh/sessions"
  echo old > "$GROVE_CONFIG/zsh/.zsh_sessions/A.session"
  echo new > "$HOME/.local/state/zsh/sessions/A.session"
  run apply
  [ "$status" -eq 0 ]
  [ -L "$GROVE_CONFIG/zsh/.zsh_sessions" ]
  [ "$(cat "$HOME/.local/state/zsh/sessions/A.session")" = new ]
  [ -n "$(find "$GROVE_STATE/backup/test" -name A.session)" ]
}

@test "zsh retires the old sessions folder in home" {
  load_module 70-zsh
  apply
  mkdir -p "$HOME/.zsh_sessions"
  echo s > "$HOME/.zsh_sessions/B.session"
  run check
  [ "$status" -eq 3 ]
  run apply
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.zsh_sessions" ]
  [ "$(cat "$GROVE_STATE/backup/test/.zsh_sessions/B.session")" = s ]
}

@test "zshenv sets every XDG folder, keeps values already set, and turns off per-window history" {
  load_module 70-zsh
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply
  run env -i HOME="$HOME" PATH=/usr/bin:/bin /bin/zsh -c 'print -l $XDG_CONFIG_HOME $XDG_DATA_HOME $XDG_STATE_HOME $XDG_CACHE_HOME $SHELL_SESSION_HISTORY'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$HOME/.config" ]
  [ "${lines[1]}" = "$HOME/.local/share" ]
  [ "${lines[2]}" = "$HOME/.local/state" ]
  [ "${lines[3]}" = "$HOME/.cache" ]
  [ "${lines[4]}" = 0 ]
  run env -i HOME="$HOME" PATH=/usr/bin:/bin XDG_CACHE_HOME=/tmp/c /bin/zsh -c 'echo $XDG_CACHE_HOME'
  [ "$output" = /tmp/c ]
}

@test "an interactive shell writes no zsh files to home or the config folder" {
  load_module 70-zsh
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply
  run env -i HOME="$HOME" PATH=/usr/bin:/bin GROVE_BREW=/nonexistent TERM_PROGRAM=Apple_Terminal TERM_SESSION_ID=T1 /bin/zsh -lic 'print ok'
  [ "$status" -eq 0 ]
  [ -z "$(find "$HOME" -maxdepth 1 -name '.z*' ! -name .zshenv)" ]
  [ -z "$(find "$GROVE_CONFIG/zsh" -maxdepth 1 \( -name '.zsh_history' -o -name '.zcompdump*' \))" ]
  [ -L "$GROVE_CONFIG/zsh/.zsh_sessions" ]
}

@test "interactive shells get zalias and zedit, opening the alias file and the zsh folder in the editor" {
  load_module 70-zsh
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "edit $*"\n' > "$BATS_TEST_TMPDIR/bin/fake-editor"
  chmod +x "$BATS_TEST_TMPDIR/bin/fake-editor"
  run env -i HOME="$HOME" PATH=/usr/bin:/bin EDITOR="$BATS_TEST_TMPDIR/bin/fake-editor" /bin/zsh -ic 'zalias; zedit'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "edit $HOME/.config/zsh/conf.d/20-aliases.zsh" ]
  [ "${lines[1]}" = "edit $HOME/.config/zsh" ]
  run env -i HOME="$HOME" PATH=/usr/bin:/bin /bin/zsh -ic 'alias zalias'
  [[ "$output" == *'${EDITOR:-vim}'* ]] || false
}

# editor_shell [VAR=value...]: what a plain zsh (zshenv only) has for EDITOR and
# VISUAL, with no Homebrew (GROVE_BREW) unless the test gives one.
editor_shell() {
  load_module 70-zsh
  [ -L "$HOME/.config" ] || ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply >/dev/null
  env -i HOME="$HOME" PATH=/usr/bin:/bin GROVE_BREW=/nonexistent/brew "$@" /bin/zsh -c 'print -r -- "$EDITOR|$VISUAL"'
}

@test "the editor is VS Code when code is installed, vim over ssh or without it" {
  local b="$BATS_TEST_TMPDIR/codebin"
  mkdir -p "$b"; printf '#!/bin/sh\n' > "$b/code"; chmod +x "$b/code"
  run editor_shell PATH="$b:/usr/bin:/bin"
  [ "$output" = "code --wait|code --wait" ]
  # a new window's first shell: Homebrew's folder isn't on the PATH yet
  run editor_shell GROVE_BREW="$b/brew"
  [ "$output" = "$b/code --wait|$b/code --wait" ]
  run editor_shell PATH="$b:/usr/bin:/bin" SSH_CONNECTION="10.0.0.1 1 10.0.0.2 22"
  [ "$output" = "vim|vim" ]
  run editor_shell PATH="$b:/usr/bin:/bin" SSH_TTY=/dev/ttys001
  [ "$output" = "vim|vim" ]
  run editor_shell
  [ "$output" = "vim|vim" ]
}

@test "the editor is vi when vim is missing, and values already set win" {
  local b="$BATS_TEST_TMPDIR/vibin"
  mkdir -p "$b"; ln -s /bin/zsh "$b/zsh"
  run editor_shell PATH="$b"
  [ "$output" = "vi|vi" ]
  run editor_shell EDITOR=nano
  [ "$output" = "nano|nano" ]
  run editor_shell VISUAL=nano
  [ "$output" = "vim|nano" ]
}

@test "zshenv starts no other program" {
  # with an empty PATH any command it ran would fail and say so
  load_module 70-zsh
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply >/dev/null
  run env -i HOME="$HOME" PATH= /bin/zsh -c 'print ok'
  [ "$status" -eq 0 ]
  [ "$output" = ok ]
  run grep -vnE '^[[:space:]]*#|^[^`]*$' "$GROVE_ROOT/config/zsh/.zshenv"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  run grep -nF '$(' "$GROVE_ROOT/config/zsh/.zshenv"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "login shells leave the ssh key to ssh's own config" {
  # no ssh-add at every login: UseKeychain and AddKeysToAgent load the key on first use
  run grep -n 'ssh-add' "$GROVE_ROOT/config/zsh/.zprofile"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  grep -qE '^[[:space:]]*UseKeychain yes' "$GROVE_ROOT/config/ssh/config"
  grep -qE '^[[:space:]]*AddKeysToAgent yes' "$GROVE_ROOT/config/ssh/config"
}

# fetch_shell [VAR=value...]: an interactive zsh on a real terminal (via script),
# FETCH_COLS wide (default 160), with a fake fastfetch that prints FETCH and its
# arguments, running `print -r -- "fetched=$GROVE_FETCHED"`.
fetch_shell() {
  load_module 70-zsh
  [ -L "$HOME/.config" ] || ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/fetchbin"
  [ -n "${NO_FASTFETCH:-}" ] || { printf '#!/bin/sh\necho FETCH "$@"\n' > "$BATS_TEST_TMPDIR/fetchbin/fastfetch"; chmod +x "$BATS_TEST_TMPDIR/fetchbin/fastfetch"; }
  env -i HOME="$HOME" PATH="$BATS_TEST_TMPDIR/fetchbin:/usr/bin:/bin" "$@" \
    script -q /dev/null /bin/sh -c "stty cols ${FETCH_COLS:-160} rows 40; exec /bin/zsh -ic 'print -r -- \"fetched=\$GROVE_FETCHED\"'" < /dev/null 2>&1 | tr -d '\r\b' | sed 's/\^D//g'  # script echoes ^D for the empty stdin
}

@test "fastfetch runs in a new Ghostty window, one empty line below the top" {
  run fetch_shell TERM_PROGRAM=ghostty
  [ "${lines[0]}" = "" ] || [[ "$output" == $'\n'FETCH* ]] || false
  [[ "$output" == *FETCH* ]] || false
  [[ "$output" == *"fetched=1"* ]] || false
}

@test "a wide Ghostty window gets the image (the config's default logo)" {
  run fetch_shell TERM_PROGRAM=ghostty
  [[ "$output" == *"FETCH"* ]] || false
  [[ "$output" != *"--logo"* ]] || false
}

@test "a Ghostty window of 125 to 139 columns gets the text art, in aqua" {
  FETCH_COLS=130 run fetch_shell TERM_PROGRAM=ghostty
  [[ "$output" == *"FETCH --logo-type file --logo $HOME/.config/fastfetch/grove.ascii --logo-color-1 #83C092"* ]] || false
}

@test "Terminal.app gets the text art, even when wide" {
  run fetch_shell TERM_PROGRAM=Apple_Terminal
  [[ "$output" == *"--logo-type file --logo $HOME/.config/fastfetch/grove.ascii"* ]] || false
}

@test "Ghostty gets the text art when the image is missing" {
  rm "$GROVE_CONFIG/fastfetch/grove.png"
  run fetch_shell TERM_PROGRAM=ghostty
  [[ "$output" == *"--logo-type file"* ]] || false
}

@test "a window under 125 columns gets the box alone" {
  FETCH_COLS=100 run fetch_shell TERM_PROGRAM=ghostty
  [[ "$output" == *"FETCH --logo none"* ]] || false
}

@test "fastfetch runs in a new Terminal.app window" {
  run fetch_shell TERM_PROGRAM=Apple_Terminal
  [[ "$output" == *FETCH* ]] || false
}

@test "fastfetch stays quiet when GROVE_FETCHED is inherited" {
  run fetch_shell TERM_PROGRAM=ghostty GROVE_FETCHED=1
  [[ "$output" != *FETCH* ]] || false
  run fetch_shell TERM_PROGRAM=ghostty GROVE_FETCHED=
  [[ "$output" == *FETCH* ]] || false
}

@test "fastfetch stays quiet with GROVE_NO_FETCH=1" {
  run fetch_shell TERM_PROGRAM=ghostty GROVE_NO_FETCH=1
  [ "$output" = "fetched=" ]
}

@test "fastfetch stays quiet in other terminals" {
  run fetch_shell TERM_PROGRAM=vscode
  [ "$output" = "fetched=" ]
}

@test "fastfetch stays quiet when stdout isn't a terminal" {
  load_module 70-zsh
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/fetchbin"
  printf '#!/bin/sh\necho FETCH\n' > "$BATS_TEST_TMPDIR/fetchbin/fastfetch"; chmod +x "$BATS_TEST_TMPDIR/fetchbin/fastfetch"
  run env -i HOME="$HOME" PATH="$BATS_TEST_TMPDIR/fetchbin:/usr/bin:/bin" TERM_PROGRAM=ghostty /bin/zsh -ic 'print -r -- "fetched=$GROVE_FETCHED"'
  [ "$output" = "fetched=" ]
}

@test "fastfetch stays quiet when fastfetch is missing" {
  NO_FASTFETCH=1 run fetch_shell TERM_PROGRAM=ghostty
  [ "$status" -eq 0 ]
  [ "$output" = "fetched=" ]
}


@test "completion writes its dump under the XDG cache" {
  brew_prefix >/dev/null || skip "zsh plugins not installed"
  run tool_shell 'print done'
  [ "$status" -eq 0 ]
  [ "$output" = "done" ]
  ls "$HOME"/.cache/zsh/zcompdump-* >/dev/null
  [ -z "$(find "$HOME" "$GROVE_CONFIG/zsh" -maxdepth 1 -name '.zcompdump*')" ]
}

@test "cd is zoxide and builtin cd still works" {
  brew_prefix >/dev/null || skip "zsh plugins not installed"
  run tool_shell 'whence -w cd; builtin cd /tmp && pwd -P'
  [ "${lines[0]}" = "cd: function" ]
  [ "${lines[1]}" = "/private/tmp" ]
}

@test "the plugins load and highlighting loads last" {
  brew_prefix >/dev/null || skip "zsh plugins not installed"
  run tool_shell 'print -r -- $ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE; (( ${+ZSH_HIGHLIGHT_VERSION} )) && print highlight; print -r -- ${${(o)$(print -l $ZDOTDIR/conf.d/*.zsh(N:t))}[-1]}'
  [ "${lines[0]}" = "fg=#859289" ]
  [ "${lines[1]}" = "highlight" ]
  [ "${lines[2]}" = "99-theme.zsh" ]
}

@test "an open shell picks up a new scheme at the next prompt" {
  brew_prefix >/dev/null || skip "zsh plugins not installed"
  local gt="$GROVE_ROOT/../grove-themes/bin/grove-themes" st="$BATS_TEST_TMPDIR/state"
  mkdir -p "$st"
  run tool_shell "a=\${ZSH_HIGHLIGHT_STYLES[command]}
    GROVE_STATE='$st' '$gt' render --scheme light-soft --config '$GROVE_CONFIG' >/dev/null || print renderfail
    print soft > '$st/theme'
    _grove_theme_precmd; b=\${ZSH_HIGHLIGHT_STYLES[command]}
    unset 'ZSH_HIGHLIGHT_STYLES[command]'
    _grove_theme_precmd; c=\${ZSH_HIGHLIGHT_STYLES[command]-unset}
    print light-soft > '$st/theme'
    _grove_theme_precmd; d=\${ZSH_HIGHLIGHT_STYLES[command]}
    print -r -- \"a=\$a\" \"b=\$b\" \"c=\$c\" \"d=\$d\"" GROVE_STATE="$st"
  [[ "$output" != *renderfail* ]] || false
  local last="${lines[${#lines[@]}-1]}"
  [[ "$last" == "a=fg=#A7C080 b=fg=#A7C080 c=unset d=fg="* ]] || { echo "$last"; false; }
  [[ "$last" != *"d=fg=#A7C080" ]] || false
}

@test "fzf keys are bound" {
  brew_prefix >/dev/null || skip "zsh plugins not installed"
  run tool_shell "bindkey '^R'"
  [[ "$output" == *fzf-* ]] || false
  # ⌥C arrives as Esc c (Ghostty: macos-option-as-alt = left)
  run tool_shell "bindkey '^[c'"
  [[ "$output" == *'"^[c" fzf-cd-widget'* ]] || { echo "$output"; false; }
}

@test "a pasted command with a # comment runs without the comment" {
  run alias_shell 'print one # two'
  [ "$output" = one ]
  run alias_shell '[[ -o interactive_comments ]] && print on'
  [ "$output" = on ]
}

@test "shell tool files are quiet without their tools" {
  load_module 70-zsh
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/empty"
  run --separate-stderr env -i HOME="$HOME" PATH=/usr/bin:/bin HOMEBREW_PREFIX="$BATS_TEST_TMPDIR/empty" /bin/zsh -ic 'exit 0'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "zoxide and eza keep their files in XDG folders" {
  load_module 70-zsh
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply >/dev/null
  run env -i HOME="$HOME" PATH=/usr/bin:/bin /bin/zsh -c 'print -r -- $_ZO_DATA_DIR; print -r -- $EZA_CONFIG_DIR'
  [ "${lines[0]}" = "$HOME/.local/share/zoxide" ]
  [ "${lines[1]}" = "$HOME/.config/eza" ]
}

@test "zsh needs work while compaudit reports Homebrew folders" {
  load_module 70-zsh
  local prefix="$BATS_TEST_TMPDIR/hb" d
  d="$prefix/share"
  mkdir -p "$prefix/bin" "$d"
  chmod 775 "$d"
  export GROVE_BREW="$prefix/bin/brew"
  stub fake-compaudit '[ -n "$(find "'"$d"'" -maxdepth 0 -perm -g+w)" ] && echo "'"$d"'"; exit 0'
  apply >/dev/null
  chmod 775 "$d"
  run check
  [ "$status" -eq 3 ]
  run apply
  [ "$status" -eq 0 ]
  [ "$(stat -f %Lp "$d")" = "755" ]
  run check
  [ "$status" -eq 0 ]
}

@test "zsh never changes permissions outside the Homebrew prefix" {
  load_module 70-zsh
  local other="$BATS_TEST_TMPDIR/elsewhere"
  mkdir -p "$other"; chmod 775 "$other"
  export GROVE_BREW="$BATS_TEST_TMPDIR/hb/bin/brew"
  stub fake-compaudit 'echo "'"$other"'"; exit 0'
  run apply
  [ "$status" -eq 0 ]
  [ "$(stat -f %Lp "$other")" = "775" ]
}

# alias_shell CMD [VAR=value...]: an interactive zsh with the real Homebrew tools
# on PATH but no plugins; stderr dropped (fzf's no-tty notice).
alias_shell() {
  local cmd="$1"; shift
  load_module 70-zsh
  [ -L "$HOME/.config" ] || ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply >/dev/null
  env -i HOME="$HOME" PATH="${ALIAS_PATH:-/opt/homebrew/bin:/usr/bin:/bin}" "$@" /bin/zsh -ic "$cmd" 2>/dev/null < /dev/null
}

# pty_alias_shell CMD [VAR=value...]: like alias_shell, on a real terminal
# (eza only lists the current folder when stdin is a terminal). Colors stripped.
pty_alias_shell() {
  local cmd="$1"; shift
  load_module 70-zsh
  [ -L "$HOME/.config" ] || ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply >/dev/null
  env -i HOME="$HOME" PATH="/opt/homebrew/bin:/usr/bin:/bin" GROVE_NO_FETCH=1 "$@" \
    script -q /dev/null /bin/zsh -ic "$cmd" < /dev/null 2>&1 | tr -d '\r\b' | sed -e 's/\^D//g' -e $'s/\033\[[0-9;]*m//g'
}

@test "ls, ll and lt expand as in the spec, with icons in Ghostty" {
  [ -x /opt/homebrew/bin/eza ] || skip "eza not installed"
  run alias_shell 'alias ll; alias ls; alias lt' TERM_PROGRAM=ghostty
  [[ "${lines[0]}" == *"_grove_ls -la --group-directories-first --sort=name --git --icons=auto"* ]] || false
  [[ "${lines[1]}" == *"_grove_ls -l --group-directories-first --sort=name --git --icons=auto"* ]] || false
  [[ "${lines[2]}" == *"eza --tree --level=2 --group-directories-first --icons=auto"* ]] || false
}

@test "Terminal.app gets the listings without icons" {
  [ -x /opt/homebrew/bin/eza ] || skip "eza not installed"
  run alias_shell 'alias ll; alias ls; alias lt' TERM_PROGRAM=Apple_Terminal
  [ "${#lines[@]}" -eq 3 ]
  [[ "$output" != *--icons* ]] || false
}

@test "cat is bat, paging only files longer than the window" {
  [ -x /opt/homebrew/bin/bat ] || skip "bat not installed"
  run alias_shell 'alias cat'
  [[ "$output" == *"bat --paging=auto"* ]] || false
}

@test "ll lists hidden files, folders first, each A to Z ignoring case" {
  [ -x /opt/homebrew/bin/eza ] || skip "eza not installed"
  local d="$BATS_TEST_TMPDIR/listing"
  mkdir -p "$d/zdir" "$d/Cdir"; touch "$d/b.txt" "$d/A.txt" "$d/.hidden"
  run pty_alias_shell "cd '$d' && ll" TERM_PROGRAM=Apple_Terminal
  [ "$(printf '%s\n' "${lines[@]}" | grep -v 'fzf\|zle' | awk 'NF { print $NF }' | tr '\n' ' ')" = "Cdir zdir .hidden A.txt b.txt " ]
}

@test "ls hides hidden files" {
  [ -x /opt/homebrew/bin/eza ] || skip "eza not installed"
  local d="$BATS_TEST_TMPDIR/listing"
  mkdir -p "$d/zdir" "$d/Cdir"; touch "$d/b.txt" "$d/A.txt" "$d/.hidden"
  run pty_alias_shell "cd '$d' && ls" TERM_PROGRAM=Apple_Terminal
  [ "$(printf '%s\n' "${lines[@]}" | grep -v 'fzf\|zle' | awk 'NF { print $NF }' | tr '\n' ' ')" = "Cdir zdir A.txt b.txt " ]
}

# sorted_listing: a folder with files of known sizes and dates (and a subfolder,
# the oldest). Prints its path.
#   name   size  modified
#   sub    -     2019
#   big    3000  2020
#   mid    300   2021
#   small  2     2022
sorted_listing() {
  local d="$BATS_TEST_TMPDIR/sorted"
  mkdir -p "$d/sub"
  head -c 3000 /dev/zero > "$d/big"; head -c 300 /dev/zero > "$d/mid"; printf 'xx' > "$d/small"
  touch -t 201901010000 "$d/sub"; touch -t 202001010000 "$d/big"
  touch -t 202101010000 "$d/mid"; touch -t 202201010000 "$d/small"
  printf '%s\n' "$d"
}

# listed_names: the last word of each line of $output (the names of a long
# listing, or rc=N), on one line.
listed_names() {
  printf '%s\n' "${lines[@]}" | grep -v 'fzf\|zle' | awk 'NF { print $NF }' | tr '\n' ' '
}

@test "ls -t lists newest first, and -ltr, -lrt and -t -r oldest first, as ls does" {
  [ -x /opt/homebrew/bin/eza ] || skip "eza not installed"
  local d; d="$(sorted_listing)"
  run pty_alias_shell "cd '$d' && ls -t; print rc=\$?"
  [ "$(listed_names)" = "small mid big sub rc=0 " ] || { echo "$output"; false; }
  local flags
  for flags in -ltr -lrt '-t -r' '-l -tr'; do
    run pty_alias_shell "cd '$d' && ls $flags; print rc=\$?"
    [ "$(listed_names)" = "sub big mid small rc=0 " ] || { echo "$flags: $output"; false; }
  done
}

@test "ls -lS lists largest first and -lSr smallest first" {
  [ -x /opt/homebrew/bin/eza ] || skip "eza not installed"
  local d; d="$(sorted_listing)"
  run pty_alias_shell "cd '$d' && ls -lS big mid small; print rc=\$?"
  [ "$(listed_names)" = "big mid small rc=0 " ] || { echo "$output"; false; }
  run pty_alias_shell "cd '$d' && ls -lSr big mid small; print rc=\$?"
  [ "$(listed_names)" = "small mid big rc=0 " ] || { echo "$output"; false; }
  # the whole folder, in the real ls's order (the subfolder by its own size)
  run pty_alias_shell "cd '$d' && ls -lS; print rc=\$?; command ls -S | tr '\\n' ' '"
  local real="${lines[${#lines[@]}-1]}"
  [ "$(printf '%s\n' "${lines[@]:0:${#lines[@]}-1}" | grep -v 'fzf\|zle' | awk 'NF { print $NF }' | tr '\n' ' ')" = "${real% } rc=0 " ] || { echo "$output"; false; }
}

@test "ls -ltrh, ll -tr and a time sort of a named folder work; -r alone reverses the names" {
  [ -x /opt/homebrew/bin/eza ] || skip "eza not installed"
  local d; d="$(sorted_listing)"
  # eza's -h is a header row
  run pty_alias_shell "cd '$d' && ls -ltrh; print rc=\$?"
  [ "$(listed_names)" = "Name sub big mid small rc=0 " ] || { echo "$output"; false; }
  run pty_alias_shell "cd / && ll -tr '$d'; print rc=\$?"
  [ "$(listed_names)" = "sub big mid small rc=0 " ] || { echo "$output"; false; }
  run pty_alias_shell "cd / && ls -t '$d'; print rc=\$?"
  [ "$(listed_names)" = "small mid big sub rc=0 " ] || { echo "$output"; false; }
  run pty_alias_shell "cd '$d' && ls -r; print rc=\$?"
  [ "$(listed_names)" = "sub small mid big rc=0 " ] || { echo "$output"; false; }
}

@test "ls passes eza's own options and anything after -- unchanged" {
  [ -x /opt/homebrew/bin/eza ] || skip "eza not installed"
  local d; d="$(sorted_listing)"
  touch "$d/-t"
  run pty_alias_shell "cd '$d' && ls --sort=size --time=modified big small; print rc=\$?; ls -s size big small; print rc=\$?; ls -- -t; print rc=\$?"
  [ "$(listed_names)" = "small big rc=0 small big rc=0 -t rc=0 " ] || { echo "$output"; false; }
}

@test "\\ls and command ls are still the real ls" {
  [ -x /opt/homebrew/bin/eza ] || skip "eza not installed"
  local d; d="$(sorted_listing)"
  run pty_alias_shell "cd '$d' && \\ls -tr | tr '\\n' ' '; print; command ls -S | tr '\\n' ' '; print; whence -w ls"
  [ "$(printf '%s\n' "${lines[@]}" | grep -v 'fzf\|zle' | sed 's/ *$//')" = "$(printf 'sub big mid small\nbig mid sub small\nls: alias')" ] || { echo "$output"; false; }
}

@test "the aliases are absent when eza and bat are missing" {
  ALIAS_PATH=/usr/bin:/bin run alias_shell 'alias ls || print none; alias cat || print none; (( $+functions[_grove_ls] )) || print none'
  [ "$output" = "$(printf 'none\nnone\nnone')" ]
}

# fake_yazi DIR: a yazi on PATH that "quits in" DIR by writing it to --cwd-file.
fake_yazi() {
  mkdir -p "$BATS_TEST_TMPDIR/fakebin"
  cat > "$BATS_TEST_TMPDIR/fakebin/yazi" <<SH
#!/bin/sh
for a in "\$@"; do case "\$a" in --cwd-file=*) printf '%s' '$1' > "\${a#--cwd-file=}" ;; esac; done
SH
  chmod +x "$BATS_TEST_TMPDIR/fakebin/yazi"
}

@test "y opens yazi and moves the shell to the folder it quit in" {
  local d="$BATS_TEST_TMPDIR/landed"
  mkdir -p "$d"
  fake_yazi "$d"
  ALIAS_PATH="$BATS_TEST_TMPDIR/fakebin:/usr/bin:/bin" run alias_shell 'y; pwd'
  [ "$output" = "$(cd "$d" && pwd -P)" ] || [ "$output" = "$d" ]
}

@test "y leaves the shell where it was when yazi quits without a folder" {
  fake_yazi ""
  ALIAS_PATH="$BATS_TEST_TMPDIR/fakebin:/usr/bin:/bin" run alias_shell "builtin cd '$BATS_TEST_TMPDIR' && y; pwd"
  [ "$output" = "$BATS_TEST_TMPDIR" ]
}

@test "finder runs y" {
  local d="$BATS_TEST_TMPDIR/landed"
  mkdir -p "$d"
  fake_yazi "$d"
  ALIAS_PATH="$BATS_TEST_TMPDIR/fakebin:/usr/bin:/bin" run alias_shell 'alias finder; finder; pwd'
  [ "${lines[0]}" = "finder=y" ]
  [ "${lines[1]}" = "$(cd "$d" && pwd -P)" ] || [ "${lines[1]}" = "$d" ]
}

@test "y and finder are absent when yazi is missing" {
  ALIAS_PATH=/usr/bin:/bin run alias_shell '(( $+functions[y] )) && print y; alias finder || print none'
  [ "$output" = "none" ]
}

@test "yazi lists like ls: folders first, A to Z ignoring case, hidden files off" {
  local f="$GROVE_ROOT/config/yazi/yazi.toml"
  grep -qx 'sort_by = "alphabetical"' "$f"
  grep -qx 'sort_sensitive = false' "$f"
  grep -qx 'sort_dir_first = true' "$f"
  grep -qx 'show_hidden = false' "$f"
}

# yazi_screen [VAR=value...]: yazi's first screen on a 100x30 terminal, opened
# in a folder with one subfolder and quit with q. Raw output, colors included.
yazi_screen() {
  local d="$BATS_TEST_TMPDIR/yz"
  mkdir -p "$d/sub"; touch "$d/file.txt"
  [ -L "$HOME/.config" ] || ln -s "$GROVE_CONFIG" "$HOME/.config"
  (sleep 3; printf q) | env -i HOME="$HOME" PATH="/opt/homebrew/bin:/usr/bin:/bin" TERM=xterm-256color COLORTERM=truecolor "$@" \
    script -q "$BATS_TEST_TMPDIR/yazi.out" /bin/sh -c "stty rows 30 cols 100; cd '$d' && exec yazi" >/dev/null 2>&1
  cat "$BATS_TEST_TMPDIR/yazi.out"
}

@test "yazi's top bar is the prompt bar: aqua user, green folder, yellow end" {
  [ -x /opt/homebrew/bin/yazi ] || skip "yazi not installed"
  run yazi_screen TERM_PROGRAM=ghostty
  [[ "$output" == *$'\xee\x82\xb6'* ]] || false                 # rounded start
  [[ "$output" == *'48;2;131;192;146'*$'\xef\x85\xb9'* ]] || false   # aqua block, apple
  [[ "$output" == *'48;2;167;192;128'*'/yz'* ]] || false        # green folder block
  [[ "$output" == *'38;2;219;188;127'*$'\xee\x82\xb4'* ]] || false   # yellow rounded end
  [[ "$output" == *'────'* ]] || false                          # the line under it
}

@test "yazi's top bar has no Nerd Font glyphs in Terminal.app" {
  [ -x /opt/homebrew/bin/yazi ] || skip "yazi not installed"
  local bar
  run yazi_screen TERM_PROGRAM=Apple_Terminal
  bar="${output%%$'\e[2;1H'*}"        # everything drawn before the second row
  [[ "$bar" == *'48;2;131;192;146'* ]] || false
  [[ "$bar" != *$'\xee\x82'* ]] || false     # no rounded ends or arrows
  [[ "$bar" != *$'\xef\x85\xb9'* ]] || false
}

@test "yazi's hovered row is a rounded pill" {
  grep -qx 'padding = { open = "'$'\xee\x82\xb6''", close = "'$'\xee\x82\xb4''" }' "$GROVE_RENDERED/yazi/theme.toml"
}

@test "eza uses the Grove theme" {
  [ -x /opt/homebrew/bin/eza ] || skip "eza not installed"
  local d="$BATS_TEST_TMPDIR/themed"
  mkdir -p "$d/folder"
  run alias_shell "command eza --color=always --oneline '$d'"
  [[ "$output" == *$'\033['*'38;2;127;187;179m'*folder* ]] || false
}

@test "bat reads its config from the XDG folder and uses the ansi theme" {
  [ -x /opt/homebrew/bin/bat ] || skip "bat not installed"
  run alias_shell 'command bat --config-file'
  [ "$output" = "$HOME/.config/bat/config" ]
  grep -qx -- '--theme=ansi' "$GROVE_ROOT/config/bat/config"
  grep -qx -- '--style=numbers,changes,header' "$GROVE_ROOT/config/bat/config"
}

# eza reads file names from stdin when it has no path and stdin isn't a terminal;
# with a path (the usual case in a loop) it doesn't.
@test "ls with a path inside a read loop doesn't swallow the loop's input" {
  [ -x /opt/homebrew/bin/eza ] || skip "eza not installed"
  local d="$BATS_TEST_TMPDIR/loop"
  mkdir -p "$d"; touch "$d/one" "$d/two"
  run alias_shell "cd '$d' && printf 'one\ntwo\n' | while read -r f; do ls \"\$f\" >/dev/null; print seen \$f; done"
  [ "$(printf '%s\n' "${lines[@]}" | tr '\n' ' ')" = "seen one seen two " ]
}

@test "zsh leaves Homebrew folders owned by someone else alone" {
  load_module 70-zsh
  # /usr/share is inside the prefix /usr and owned by root, like another user's Homebrew.
  export GROVE_BREW=/usr/bin/brew
  stub fake-compaudit 'echo /usr/share; exit 0'
  run apply
  [ "$status" -eq 0 ]
  [[ "$output" != *"/usr/share"* ]] || false
  run check
  [ "$status" -eq 0 ]
}

@test "completion skips Homebrew folders that aren't safe for this user" {
  load_module 70-zsh
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply >/dev/null
  local p="$BATS_TEST_TMPDIR/hb"
  mkdir -p "$p/share/zsh/site-functions" "$p/share/zsh-completions"
  chmod 775 "$p/share"
  run env -i HOME="$HOME" PATH=/usr/bin:/bin HOMEBREW_PREFIX="$p" /bin/zsh -ic 'print -l $fpath' < /dev/null
  [[ "$output" != *"$p/share/zsh-completions"* ]] || false
  # site-functions sits in share/zsh (safe), so it stays; compaudit checks only a folder and its parent.
  [[ "$output" == *"$p/share/zsh/site-functions"* ]] || false
  [[ "$output" != *"insecure"* ]] || false
  chmod 755 "$p/share"
  run env -i HOME="$HOME" PATH=/usr/bin:/bin HOMEBREW_PREFIX="$p" /bin/zsh -ic 'print -l $fpath' < /dev/null
  [[ "$output" == *"$p/share/zsh-completions"* ]] || false
}

@test "cls clears the screen and reloads zsh as a fresh login shell with the summary" {
  run alias_shell 'alias cls'
  [ "$output" = "cls='clear && GROVE_FETCHED= exec zsh -l'" ]
}
