load helpers
bats_require_minimum_version 1.5.0
setup() {
  gt_test_setup
  DOTFILES="$(cd "$GT_ROOT/../grove-dotfiles" && pwd -P)"
  export GROVE_ROOT="$BATS_TEST_TMPDIR/dotfiles"
  export GROVE_STATE="$HOME/.local/state/grove"
  export GROVE_RUN_ID=test-run
  export CALLS="$BATS_TEST_TMPDIR/calls"
  : > "$CALLS"
  mkdir -p "$GROVE_ROOT"
  cp -R "$DOTFILES/theme" "$GROVE_ROOT/theme"
  cp -R "$DOTFILES/lib" "$GROVE_ROOT/lib"
  gt_copy_config "$GROVE_ROOT/config"
  CLI="$GT_ROOT/bin/grove-themes"
  stub osascript 'echo "osascript $*" >> "$CALLS"; [ "$1" != - ] || cat >> "$CALLS"; [ -z "$FAKE_OSA_FAIL" ] || { echo "not authorized" >&2; exit 1; }'
  stub defaults 'echo "defaults $*" >> "$CALLS"'
  stub kill 'echo "kill $*" >> "$CALLS"'
  stub fakeps 'printf "%s\n" "  101 /Applications/Ghostty.app/Contents/MacOS/ghostty" "  202 /usr/bin/zsh" "  303 /Applications/Ghostty.app/Contents/MacOS/ghostty" "  404 /Applications/Ghostty.app/Contents/MacOS/ghostty-helper"'
  stub noneps 'printf "%s\n" "  202 /usr/bin/zsh"'
  export GROVE_PS=fakeps
}

gt_copy_config() {
  local dest="$1" f
  mkdir -p "$dest"
  while IFS= read -r f; do
    mkdir -p "$dest/$(dirname "$f")"
    cp "$DOTFILES/config/$f" "$dest/$f"
  done < <(git -C "$DOTFILES/config" ls-files . | grep '\.tmpl$')
}

@test "set signals each running Ghostty" {
  run "$CLI" set dark-soft
  [ "$status" -eq 0 ]
  [ "$(grep -c '^kill' "$CALLS")" -eq 2 ]
  grep -qx 'kill -USR2 101' "$CALLS"
  grep -qx 'kill -USR2 303' "$CALLS"
}

@test "set with no Ghostty running is fine" {
  export GROVE_PS=noneps
  run "$CLI" set dark-soft
  [ "$status" -eq 0 ]
  [ "$(grep -c '^kill' "$CALLS")" -eq 0 ]
  [[ "$output" == *"not running"* ]] || false
}

@test "set turns macOS light for light schemes and dark for dark ones" {
  run "$CLI" set light-hard
  [ "$status" -eq 0 ]
  grep -q 'set dark mode to false' "$CALLS"
  : > "$CALLS"
  run "$CLI" set dark-hard
  [ "$status" -eq 0 ]
  grep -q 'set dark mode to true' "$CALLS"
}

@test "set sets the green accent and the scheme's highlight" {
  run "$CLI" set light-medium
  [ "$status" -eq 0 ]
  grep -qx 'defaults write -g AppleAccentColor -int 3' "$CALLS"
  grep -qx 'defaults write -g AppleHighlightColor -string 0.917647 0.929412 0.784314 Other' "$CALLS"
}

@test "set puts the scheme's wallpaper on every screen" {
  run "$CLI" set light-soft
  [ "$status" -eq 0 ]
  grep -q "^osascript - $GROVE_WALLPAPER_DIR/wallpaper-project-grove-light-soft.png\$" "$CALLS"
  grep -q 'set picture of every desktop' "$CALLS"
}

@test "a denied Automation prompt doesn't stop the other steps" {
  export FAKE_OSA_FAIL=1
  run "$CLI" set light-soft
  [ "$status" -eq 1 ]
  [[ "$output" == *Automation* ]] || false
  grep -qx 'defaults write -g AppleAccentColor -int 3' "$CALLS"
  grep -q 'kill -USR2 101' "$CALLS"
  run "$CLI" set --json light-soft
  [ "$status" -eq 1 ]
  [[ "$output" == *'"name": "appearance", "result": "needs-you"'* ]] || false
  [[ "$output" == *'"name": "wallpaper", "result": "needs-you"'* ]] || false
  [[ "$output" == *'"name": "accent", "result": "live"'* ]] || false
}

@test "set backs up a hand-edited generated file" {
  run "$CLI" set dark-medium
  [ "$status" -eq 0 ]
  [[ "$output" != *"backed up"* ]] || false
  echo "# my edit" >> "$GROVE_ROOT/config/ghostty/config"
  run "$CLI" set dark-hard
  [ "$status" -eq 0 ]
  [[ "$output" == *"backed up edited ghostty/config to "* ]] || false
  dest="$(printf '%s\n' "$output" | sed -n 's/.*backed up edited ghostty\/config to //p')"
  grep -q '# my edit' "$dest"
  run grep -q '# my edit' "$GROVE_ROOT/config/ghostty/config"
  [ "$status" -ne 0 ]
  run "$CLI" set dark-soft
  [[ "$output" != *"backed up"* ]] || false
}

@test "set --json lists every step" {
  run "$CLI" set --json dark-soft
  [ "$status" -eq 0 ]
  names="$(printf '%s' "$output" | grep -o '"name": "[a-z]*"' | sed 's/"name": //' | tr -d '"\n' )"
  [ "$names" = "configsghosttyzshstarshipezabatfastfetchvscodeyazi""appearanceaccentwallpaper" ]
}
