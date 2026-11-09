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
  cp -R "$GROVE_ROOT/config" "$BATS_TEST_TMPDIR/config"
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
  run env -i HOME="$HOME" PATH=/usr/bin:/bin /bin/zsh -lic 'echo $ZDOTDIR; echo $HISTFILE'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$HOME/.config/zsh" ]
  [ "${lines[1]}" = "$HOME/.local/state/zsh/history" ]
  [ -d "$HOME/.local/state/zsh" ]
}

@test "zshenv is silent and adds .local/bin to PATH once" {
  load_module 70-zsh
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  apply
  run env -i HOME="$HOME" PATH="$HOME/.local/bin:/usr/bin:/bin" /bin/zsh -c 'echo $PATH'
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.local/bin:/usr/bin:/bin" ]
}

@test "starship accepts the config" {
  run env STARSHIP_CONFIG="$GROVE_ROOT/config/starship.toml" /opt/homebrew/bin/starship print-config >/dev/null 2>"$BATS_TEST_TMPDIR/err"
  [ "$status" -eq 0 ]
  [ ! -s "$BATS_TEST_TMPDIR/err" ]
}
