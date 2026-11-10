load helpers
bats_require_minimum_version 1.5.0
setup() {
  gt_test_setup
  DOTFILES="$(cd "$GT_ROOT/../grove-dotfiles" && pwd -P)"
  export GROVE_ROOT="$BATS_TEST_TMPDIR/dotfiles"
  export GROVE_STATE="$HOME/.local/state/grove"
  mkdir -p "$GROVE_ROOT"
  cp -R "$DOTFILES/theme" "$GROVE_ROOT/theme"
  gt_copy_config "$GROVE_ROOT/config"
  CLI="$GT_ROOT/bin/grove-themes"
}

# gt_copy_config DEST: the tracked templates only (no generated files).
gt_copy_config() {
  local dest="$1" f
  mkdir -p "$dest"
  while IFS= read -r f; do
    mkdir -p "$dest/$(dirname "$f")"
    cp "$DOTFILES/config/$f" "$dest/$f"
  done < <(git -C "$DOTFILES/config" ls-files . | grep '\.tmpl$')
}

@test "list marks the current scheme" {
  mkdir -p "$GROVE_STATE"; echo dark-soft > "$GROVE_STATE/theme"
  run "$CLI" list
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 6 ]
  [[ "$output" == *"* dark-soft"* ]] || false
  [ "$(printf '%s\n' "$output" | grep -c '^\*')" -eq 1 ]
}

@test "list --json gives current and schemes" {
  run "$CLI" list --json
  [ "$status" -eq 0 ]
  [ "$output" = '{"current": "dark-medium", "schemes": ["dark-hard", "dark-medium", "dark-soft", "light-hard", "light-medium", "light-soft"]}' ]
}

@test "current defaults to dark-medium" {
  run "$CLI" current
  [ "$status" -eq 0 ]
  [ "$output" = "dark-medium" ]
}

@test "current falls back on a bad state file" {
  mkdir -p "$GROVE_STATE"; echo light-pink > "$GROVE_STATE/theme"
  run --separate-stderr "$CLI" current
  [ "$status" -eq 0 ]
  [ "$output" = "dark-medium" ]
  [[ "$stderr" == *"grove-themes: unknown scheme in $GROVE_STATE/theme, using dark-medium"* ]] || false
}

@test "set writes the configs and the state" {
  run "$CLI" set light-soft
  [ "$status" -eq 0 ]
  bg0="$(sed -n 's/^bg0 *= *//p' "$GROVE_ROOT/theme/everforest-light-soft")"
  grep -q "^background = $bg0\$" "$GROVE_ROOT/config/ghostty/config"
  [ "$(cat "$GROVE_STATE/theme")" = "light-soft" ]
  run "$CLI" current
  [ "$output" = "light-soft" ]
}

@test "set --json prints the scheme and steps" {
  run "$CLI" set dark-hard --json
  [ "$status" -eq 0 ]
  [[ "$output" == '{"scheme": "dark-hard", "steps": [{"name": "configs",'* ]] || false
}

@test "set with an unknown scheme exits 2 and changes nothing" {
  run "$CLI" set light-pink
  [ "$status" -eq 2 ]
  [[ "$output" == *"dark-hard"* ]] || false
  [ ! -e "$GROVE_STATE/theme" ]
  [ ! -e "$GROVE_ROOT/config/ghostty/config" ]
  run "$CLI" set
  [ "$status" -eq 2 ]
}

@test "a failed render changes nothing" {
  "$CLI" set dark-hard
  before="$(cat "$GROVE_ROOT/config/ghostty/config")"
  echo '{{nope}}' >> "$GROVE_ROOT/config/ghostty/config.tmpl"
  run "$CLI" set light-soft
  [ "$status" -eq 1 ]
  [ "$(cat "$GROVE_ROOT/config/ghostty/config")" = "$before" ]
  [ "$(cat "$GROVE_STATE/theme")" = "dark-hard" ]
}

@test "an unwritable target keeps the old state" {
  "$CLI" set dark-hard
  chmod a-w "$GROVE_ROOT/config/yazi"
  run "$CLI" set light-soft
  chmod u+w "$GROVE_ROOT/config/yazi"
  [ "$status" -eq 1 ]
  [ "$(cat "$GROVE_STATE/theme")" = "dark-hard" ]
  run "$CLI" render
  [ "$status" -eq 0 ]
  [ "$(cat "$GROVE_STATE/theme")" = "dark-hard" ]
}

@test "render writes the configs for the current scheme" {
  mkdir -p "$GROVE_STATE"; echo dark-hard > "$GROVE_STATE/theme"
  run "$CLI" render
  [ "$status" -eq 0 ]
  bg0="$(sed -n 's/^bg0 *= *//p' "$GROVE_ROOT/theme/everforest-dark-hard")"
  grep -q "^background = $bg0\$" "$GROVE_ROOT/config/ghostty/config"
}

@test "render --scheme --config renders elsewhere" {
  gt_copy_config "$BATS_TEST_TMPDIR/other"
  run "$CLI" render --scheme light-hard --config "$BATS_TEST_TMPDIR/other"
  [ "$status" -eq 0 ]
  bg0="$(sed -n 's/^bg0 *= *//p' "$GROVE_ROOT/theme/everforest-light-hard")"
  grep -q "^background = $bg0\$" "$BATS_TEST_TMPDIR/other/ghostty/config"
  [ ! -e "$GROVE_ROOT/config/ghostty/config" ]
  [ ! -e "$GROVE_STATE/theme" ]
}

@test "bad usage exits 2" {
  run "$CLI" frobnicate
  [ "$status" -eq 2 ]
  run "$CLI" render --scheme light-pink
  [ "$status" -eq 2 ]
}
