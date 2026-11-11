# shellcheck disable=SC2016,SC1090,SC1091,SC2154
# 99-sketchybar against fake brew, sketchybar, defaults, killall, ps and
# grove-themes. Nothing reaches the real menu bar or Homebrew.
load helpers

SB_MODULE=99-sketchybar

load_module() {
  local f
  for f in "$GROVE_ROOT"/lib/*.sh; do . "$f"; done
  MODULE_DIR="$GROVE_ROOT/modules/$SB_MODULE"
  . "$MODULE_DIR/module.sh"
}

setup() {
  grove_test_setup
  export CALLS="$BATS_TEST_TMPDIR/calls"
  : > "$CALLS"
  # brew: install puts a sketchybar next to it; FAKE_BREW_RC fails a call.
  mkdir -p "$BATS_TEST_TMPDIR/brew/bin"
  cat > "$BATS_TEST_TMPDIR/brew/bin/brew" <<'EOF'
#!/bin/bash
echo "brew $*" >> "$CALLS"
[ "${FAKE_BREW_RC:-0}" = 0 ] || exit 1
if [ "$1" = install ]; then
  printf '#!/bin/bash\necho "sketchybar $*" >> "$CALLS"\n' > "$(dirname "$0")/sketchybar"
  chmod +x "$(dirname "$0")/sketchybar"
fi
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/brew/bin/brew"
  export GROVE_BREW="$BATS_TEST_TMPDIR/brew/bin/brew"
  stub defaults '
echo "defaults $*" >> "$CALLS"
[ "$1" = read ] && echo "${FAKE_HIDE:-1}"
exit 0'
  stub killall 'echo "killall $*" >> "$CALLS"'
  stub fakeps 'printf "%s\n" "  1 /usr/bin/zsh" ${FAKE_PS:+"  2 $FAKE_PS"}'
  export GROVE_PS=fakeps FAKE_PS=/opt/homebrew/opt/sketchybar/bin/sketchybar
  stub grove-themes 'echo "grove-themes $*" >> "$CALLS"; mkdir -p "$HOME/.config/sketchybar"; echo "export BG0=0xff2D353B" > "$HOME/.config/sketchybar/colors.sh"'
  export GROVE_THEMES_CLI="$BATS_TEST_TMPDIR/stubs/grove-themes"
  # The config as 05-config links it, with a rendered colors.sh and an AeroSpace
  # config that triggers the bar.
  mkdir -p "$HOME/.config/sketchybar" "$HOME/.config/aerospace"
  echo '#!/bin/bash' > "$HOME/.config/sketchybar/sketchybarrc"
  echo "export BG0=0xff2D353B" > "$HOME/.config/sketchybar/colors.sh"
  echo "exec-on-workspace-change = ['/bin/bash', '-c', 'sketchybar --trigger aerospace_workspace_change']" > "$HOME/.config/aerospace/aerospace.toml"
  load_module
}

# installed: a sketchybar next to the fake brew, as after brew install.
installed() {
  printf '#!/bin/bash\necho "sketchybar $*" >> "$CALLS"\n' > "$BATS_TEST_TMPDIR/brew/bin/sketchybar"
  chmod +x "$BATS_TEST_TMPDIR/brew/bin/sketchybar"
}

@test "sketchybar: about" {
  [ "$(about)" = "The Grove top bar (SketchyBar)" ]
}

@test "sketchybar: ok when installed, running, configured and the menu bar hidden" {
  installed
  run check
  [ "$status" -eq 0 ]
}

@test "sketchybar: needs work when it isn't installed" {
  run check
  [ "$status" -eq 3 ]
}

@test "sketchybar: needs work when it isn't running" {
  installed
  export FAKE_PS=
  run check
  [ "$status" -eq 3 ]
}

@test "sketchybar: needs work when the menu bar isn't auto-hidden" {
  installed
  export FAKE_HIDE=0
  run check
  [ "$status" -eq 3 ]
}

@test "sketchybar: needs work when colors.sh hasn't been rendered" {
  installed
  rm "$HOME/.config/sketchybar/colors.sh"
  run check
  [ "$status" -eq 3 ]
}

@test "sketchybar: fails when the config isn't linked" {
  installed
  rm "$HOME/.config/sketchybar/sketchybarrc"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Grove bar config"*"grove install config"* ]] || false
}

@test "sketchybar: fails when AeroSpace doesn't trigger the bar" {
  installed
  echo "# rendered" > "$HOME/.config/aerospace/aerospace.toml"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"AeroSpace doesn't tell the bar"*"grove install keys-app"* ]] || false
}

@test "sketchybar: check changes nothing" {
  installed
  export FAKE_PS= FAKE_HIDE=0
  rm "$HOME/.config/sketchybar/colors.sh"
  run check
  ! grep -qE 'brew (trust|install|services)|defaults write|killall|grove-themes' "$CALLS"
}

@test "sketchybar: apply trusts the tap, installs, hides the menu bar, renders and starts" {
  export FAKE_PS= FAKE_HIDE=0
  rm "$HOME/.config/sketchybar/colors.sh"
  run apply
  [ "$status" -eq 0 ]
  grep -q '^brew trust felixkratz/formulae$' "$CALLS"
  grep -q '^brew install felixkratz/formulae/sketchybar$' "$CALLS"
  grep -q '^defaults write NSGlobalDomain _HIHideMenuBar -bool true$' "$CALLS"
  grep -q '^killall SystemUIServer$' "$CALLS"
  grep -q '^grove-themes render$' "$CALLS"
  grep -q '^brew services start felixkratz/formulae/sketchybar$' "$CALLS"
  # Trust before install, install before the menu bar is hidden.
  [ "$(grep -n 'brew trust' "$CALLS" | cut -d: -f1)" -lt "$(grep -n 'brew install' "$CALLS" | cut -d: -f1)" ]
  [ "$(grep -n 'brew install' "$CALLS" | cut -d: -f1)" -lt "$(grep -n 'defaults write' "$CALLS" | cut -d: -f1)" ]
}

@test "sketchybar: a failed install stops before the menu bar is hidden" {
  export FAKE_BREW_RC=1 FAKE_HIDE=0
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not install SketchyBar"* ]] || false
  ! grep -q 'defaults write' "$CALLS"
}

@test "sketchybar: apply on a ready Mac changes nothing" {
  installed
  run apply
  [ "$status" -eq 0 ]
  ! grep -qE 'brew (trust|install|services)|defaults write|killall|grove-themes' "$CALLS"
}

@test "sketchybar: the README lists the module" {
  grep -q '`99-sketchybar`' "$GROVE_ROOT/README.md"
}
