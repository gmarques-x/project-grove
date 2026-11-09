# shellcheck disable=SC2016,SC2030,SC2031,SC1090,SC1091,SC2154
load helpers

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
}

@test "zsh links zshenv and grove" {
  load_module 70-zsh
  run apply
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.zshenv")" = "$GROVE_CONFIG/zsh/.zshenv" ]
  [ "$(readlink "$HOME/.local/bin/grove")" = "$GROVE_ROOT/bin/grove" ]
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
           "$GROVE_ROOT"/config/zsh/.zshrc "$GROVE_ROOT"/config/zsh/conf.d/*.zsh; do
    run /bin/zsh -n "$f"
    [ "$status" -eq 0 ]
  done
}

@test "a login shell loads the Grove setup" {
  load_module 70-zsh
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply
  run env -i HOME="$HOME" PATH=/usr/bin:/bin /bin/zsh -lic 'echo $ZDOTDIR; echo $HISTFILE; print -l $path'
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
  run env -i HOME="$HOME" PATH=/usr/bin:/bin /bin/zsh -lic 'echo $ZDOTDIR; echo $HISTFILE'
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
    [ -f "$GROVE_ROOT/config/$f" ]
    run env STARSHIP_CONFIG="$GROVE_ROOT/config/$f" /opt/homebrew/bin/starship print-config >/dev/null 2>"$BATS_TEST_TMPDIR/err"
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
  run env -i HOME="$HOME" PATH=/usr/bin:/bin TERM_PROGRAM=Apple_Terminal TERM_SESSION_ID=T1 /bin/zsh -lic 'print ok'
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

# fetch_shell [VAR=value...]: an interactive zsh on a real terminal (via script),
# with a fake macchina that prints FETCH, running `print -r -- "fetched=$GROVE_FETCHED"`.
fetch_shell() {
  load_module 70-zsh
  [ -L "$HOME/.config" ] || ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/fetchbin"
  [ -n "${NO_MACCHINA:-}" ] || { printf '#!/bin/sh\necho FETCH\n' > "$BATS_TEST_TMPDIR/fetchbin/macchina"; chmod +x "$BATS_TEST_TMPDIR/fetchbin/macchina"; }
  env -i HOME="$HOME" PATH="$BATS_TEST_TMPDIR/fetchbin:/usr/bin:/bin" "$@" \
    script -q /dev/null /bin/zsh -ic 'print -r -- "fetched=$GROVE_FETCHED"' < /dev/null 2>&1 | tr -d '\r\b' | sed 's/\^D//g'  # script echoes ^D for the empty stdin
}

@test "macchina runs in a new Ghostty window" {
  run fetch_shell TERM_PROGRAM=ghostty
  [[ "$output" == *FETCH* ]] || false
  [[ "$output" == *"fetched=1"* ]] || false
}

@test "macchina runs in a new Terminal.app window" {
  run fetch_shell TERM_PROGRAM=Apple_Terminal
  [[ "$output" == *FETCH* ]] || false
}

@test "macchina stays quiet when GROVE_FETCHED is inherited" {
  run fetch_shell TERM_PROGRAM=ghostty GROVE_FETCHED=1
  [[ "$output" != *FETCH* ]] || false
  run fetch_shell TERM_PROGRAM=ghostty GROVE_FETCHED=
  [[ "$output" == *FETCH* ]] || false
}

@test "macchina stays quiet with GROVE_NO_FETCH=1" {
  run fetch_shell TERM_PROGRAM=ghostty GROVE_NO_FETCH=1
  [ "$output" = "fetched=" ]
}

@test "macchina stays quiet in other terminals" {
  run fetch_shell TERM_PROGRAM=vscode
  [ "$output" = "fetched=" ]
}

@test "macchina stays quiet when stdout isn't a terminal" {
  load_module 70-zsh
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/fetchbin"
  printf '#!/bin/sh\necho FETCH\n' > "$BATS_TEST_TMPDIR/fetchbin/macchina"; chmod +x "$BATS_TEST_TMPDIR/fetchbin/macchina"
  run env -i HOME="$HOME" PATH="$BATS_TEST_TMPDIR/fetchbin:/usr/bin:/bin" TERM_PROGRAM=ghostty /bin/zsh -ic 'print -r -- "fetched=$GROVE_FETCHED"'
  [ "$output" = "fetched=" ]
}

@test "macchina stays quiet when macchina is missing" {
  NO_MACCHINA=1 run fetch_shell TERM_PROGRAM=ghostty
  [ "$status" -eq 0 ]
  [ "$output" = "fetched=" ]
}
