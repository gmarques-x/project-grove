# shellcheck disable=SC2016,SC2030,SC2031,SC1090,SC1091,SC2154
load helpers

# Source lib/*.sh and the module itself (the same way for every test).
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
  # Temp copy of config/ (Ruling R4): apply moves things into it.
  cp -R "$GROVE_ROOT/config" "$BATS_TEST_TMPDIR/config"
  export GROVE_CONFIG="$BATS_TEST_TMPDIR/config"
  export GROVE_POLL_SECONDS=0
}

# ---- 05-config

@test "config moves existing app folders into the repo config" {
  load_module 05-config
  mkdir -p "$HOME/.config/gh"
  echo "token" > "$HOME/.config/gh/hosts.yml"
  run apply
  [ "$status" -eq 0 ]
  [ "$(cat "$GROVE_CONFIG/gh/hosts.yml")" = "token" ]
  [ -L "$HOME/.config" ]
  [ "$(readlink "$HOME/.config")" = "$GROVE_CONFIG" ]
}

@test "config moves colliding files to the backup" {
  load_module 05-config
  mkdir -p "$GROVE_CONFIG/git" "$HOME/.config/git"
  echo tracked > "$GROVE_CONFIG/git/config"
  echo x > "$HOME/.config/git/config"
  echo extra > "$HOME/.config/git/other"
  run apply
  [ "$status" -eq 0 ]
  [ "$(cat "$GROVE_CONFIG/git/config")" = "tracked" ]
  [ "$(cat "$GROVE_CONFIG/git/other")" = "extra" ]
  [ "$(cat "$GROVE_STATE/backup/test/.config/git/config")" = "x" ]
  [ -L "$HOME/.config" ]
}

@test "config handles dotfiles and names with spaces" {
  load_module 05-config
  mkdir -p "$HOME/.config/my app"
  echo a > "$HOME/.config/.hidden"
  echo b > "$HOME/.config/my app/s p.txt"
  run apply
  [ "$status" -eq 0 ]
  [ "$(cat "$GROVE_CONFIG/.hidden")" = "a" ]
  [ "$(cat "$GROVE_CONFIG/my app/s p.txt")" = "b" ]
}

@test "config check needs work before and is ok once linked" {
  load_module 05-config
  run check
  [ "$status" -eq 3 ]
  apply
  run check
  [ "$status" -eq 0 ]
}

@test "config links when ~/.config does not exist" {
  load_module 05-config
  run apply
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.config")" = "$GROVE_CONFIG" ]
}

@test "config refuses a symlink pointing somewhere else" {
  load_module 05-config
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$HOME/.config"
  run check
  [ "$status" -eq 3 ]
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"not replacing"* ]] || false
  [ "$(readlink "$HOME/.config")" = "$BATS_TEST_TMPDIR/elsewhere" ]
}

@test "config stops with an error when something is left in ~/.config" {
  load_module 05-config
  mkdir -p "$HOME/.config/keep"
  echo k > "$HOME/.config/keep/f"
  # Make the move impossible: tracked name is a read-only folder.
  mkdir -p "$GROVE_CONFIG"
  chmod 500 "$GROVE_CONFIG"
  run apply
  chmod 700 "$GROVE_CONFIG"
  [ "$status" -eq 1 ]
  [ -d "$HOME/.config/keep" ]
  [ ! -L "$HOME/.config" ]
}

# ---- 10-xcode-tools

@test "xcode-tools needs you when missing" {
  load_module 10-xcode-tools
  stub xcode-select 'exit 2'
  run check
  [ "$status" -eq 4 ]
}

@test "xcode-tools is ok when present" {
  load_module 10-xcode-tools
  stub xcode-select 'echo /Library/Developer/CommandLineTools'
  run check
  [ "$status" -eq 0 ]
}

@test "xcode-tools apply installs, then waits until the tools show up" {
  load_module 10-xcode-tools
  stub xcode-select '
f="'"$BATS_TEST_TMPDIR"'/count"
case "$1" in
  --install) echo install >> "'"$BATS_TEST_TMPDIR"'/calls" ;;
  -p) n=$(cat "$f" 2>/dev/null || echo 0); echo $((n+1)) > "$f"; [ "$n" -ge 3 ] || exit 2 ;;
esac'
  run apply
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "install" ]
  [ "$(cat "$BATS_TEST_TMPDIR/count")" -ge 4 ]
}

# ---- 20-homebrew

@test "homebrew needs you when brew is missing" {
  load_module 20-homebrew
  export GROVE_BREW="$BATS_TEST_TMPDIR/nobrew"
  run check
  [ "$status" -eq 4 ]
}

@test "homebrew needs work when bundle check fails" {
  load_module 20-homebrew
  stub brew '[ "$1 $2" = "bundle check" ] && exit 1; exit 0'
  export GROVE_BREW="$BATS_TEST_TMPDIR/stubs/brew"
  run check
  [ "$status" -eq 3 ]
}

@test "homebrew is ok when bundle check passes" {
  load_module 20-homebrew
  stub brew 'exit 0'
  export GROVE_BREW="$BATS_TEST_TMPDIR/stubs/brew"
  run check
  [ "$status" -eq 0 ]
}

@test "homebrew apply runs brew bundle install with the Brewfile" {
  load_module 20-homebrew
  stub brew 'echo "$@" > "'"$BATS_TEST_TMPDIR"'/args"'
  export GROVE_BREW="$BATS_TEST_TMPDIR/stubs/brew"
  run apply
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/args")" = "bundle install --file $GROVE_ROOT/Brewfile" ]
}

@test "homebrew apply installs brew first when missing" {
  load_module 20-homebrew
  export GROVE_BREW="$BATS_TEST_TMPDIR/opt/bin/brew"
  # The fake installer script (what curl "downloads") creates the fake brew.
  mkdir -p "$(dirname "$GROVE_BREW")"
  cat > "$BATS_TEST_TMPDIR/installer.sh" <<INST
mkdir -p "$(dirname "$GROVE_BREW")"
cat > "$GROVE_BREW" <<'BREW'
#!/bin/bash
echo "\$@" > "$BATS_TEST_TMPDIR/args"
BREW
chmod +x "$GROVE_BREW"
INST
  rmdir "$(dirname "$GROVE_BREW")"
  stub curl 'cat "'"$BATS_TEST_TMPDIR"'/installer.sh"'
  run apply
  [ "$status" -eq 0 ]
  [ -x "$GROVE_BREW" ]
  [ "$(cat "$BATS_TEST_TMPDIR/args")" = "bundle install --file $GROVE_ROOT/Brewfile" ]
}

# ---- 30-fonts

fake_fonts() { # fake_fonts BODY: temp GROVE_ROOT layout with a fake installer
  mkdir -p "$BATS_TEST_TMPDIR/layout/grove-dotfiles" "$BATS_TEST_TMPDIR/layout/grove-fonts"
  printf '#!/bin/bash\n%s\n' "$1" > "$BATS_TEST_TMPDIR/layout/grove-fonts/install-fonts.sh"
  chmod +x "$BATS_TEST_TMPDIR/layout/grove-fonts/install-fonts.sh"
  export GROVE_ROOT="$BATS_TEST_TMPDIR/layout/grove-dotfiles"
}

@test "fonts maps install-fonts exit codes" {
  local real="$GROVE_ROOT"
  # shellcheck disable=SC2016
  fake_fonts 'echo "$@" > "'"$BATS_TEST_TMPDIR"'/args"; exit "$(cat "'"$BATS_TEST_TMPDIR"'/rc")"'
  for lib in "$real"/lib/*.sh; do . "$lib"; done
  . "$real/modules/30-fonts/module.sh"
  echo 0 > "$BATS_TEST_TMPDIR/rc"
  run check
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/args")" = "--check --quiet" ]
  echo 3 > "$BATS_TEST_TMPDIR/rc"
  run check
  [ "$status" -eq 3 ]
  echo 1 > "$BATS_TEST_TMPDIR/rc"
  run check
  [ "$status" -eq 1 ]
  echo 2 > "$BATS_TEST_TMPDIR/rc"
  run check
  [ "$status" -eq 1 ]
}

@test "fonts apply runs install-fonts --quiet and passes its status on" {
  local real="$GROVE_ROOT"
  fake_fonts 'echo "$@" > "'"$BATS_TEST_TMPDIR"'/args"; exit 0'
  for lib in "$real"/lib/*.sh; do . "$lib"; done
  . "$real/modules/30-fonts/module.sh"
  run apply
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/args")" = "--quiet" ]
}

@test "fonts fails when install-fonts.sh is missing" {
  local real="$GROVE_ROOT"
  fake_fonts 'exit 0'
  rm "$BATS_TEST_TMPDIR/layout/grove-fonts/install-fonts.sh"
  for lib in "$real"/lib/*.sh; do . "$lib"; done
  . "$real/modules/30-fonts/module.sh"
  run check
  [ "$status" -eq 1 ]
}

# ---- C-1: worktree guard

@test "config refuses to link from a linked git worktree" {
  load_module 05-config
  local fake="$BATS_TEST_TMPDIR/wt"
  mkdir -p "$fake/grove-dotfiles"
  echo "gitdir: /elsewhere" > "$fake/.git"
  GROVE_ROOT="$fake/grove-dotfiles"
  unset GROVE_ALLOW_WORKTREE
  run check
  [ "$status" -eq 3 ]
  [[ "$output" == *"git worktree"*"main project-grove checkout"* ]] || false
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"git worktree"* ]] || false
  [ ! -e "$HOME/.config" ]
}
