load helpers
bats_require_minimum_version 1.5.0
setup() {
  gt_test_setup
  DOTFILES="$(cd "$GT_ROOT/../grove-dotfiles" && pwd -P)"
  export GROVE_ROOT="$BATS_TEST_TMPDIR/dotfiles"
  export GROVE_STATE="$HOME/.local/state/grove"
  mkdir -p "$GROVE_ROOT"
  cp -R "$DOTFILES/theme" "$GROVE_ROOT/theme"
  cp -R "$DOTFILES/lib" "$GROVE_ROOT/lib"
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
  [ "$(printf '%s' "$output" | jq -c '[.current, .schemes]')" = '["dark-medium",["dark-hard","dark-medium","dark-soft","light-hard","light-medium","light-soft"]]' ]
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
  cp -R "$GROVE_ROOT/config" "$BATS_TEST_TMPDIR/snapshot"
  chmod a-w "$GROVE_ROOT/config/yazi"
  run "$CLI" set light-soft
  chmod u+w "$GROVE_ROOT/config/yazi"
  [ "$status" -eq 1 ]
  [ "$(cat "$GROVE_STATE/theme")" = "dark-hard" ]
  # no temp folder left behind
  [ -z "$(find "$GROVE_ROOT/config" -name '.grove-themes.*')" ]
  run "$CLI" render
  [ "$status" -eq 0 ]
  [ "$(cat "$GROVE_STATE/theme")" = "dark-hard" ]
  [ -z "$(find "$GROVE_ROOT/config" -name '.grove-themes.*')" ]
  # every file is back to the dark-hard render
  run diff -r "$BATS_TEST_TMPDIR/snapshot" "$GROVE_ROOT/config"
  [ "$status" -eq 0 ]
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

@test "list --json has every scheme's palette" {
  run "$CLI" list --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq '.palettes | keys | length')" -eq 6 ]
  [ "$(printf '%s' "$output" | jq -r '.palettes["dark-medium"].name')" = "Dark Medium" ]
  [ "$(printf '%s' "$output" | jq -r '.palettes["dark-medium"].appearance')" = dark ]
  [ "$(printf '%s' "$output" | jq -r '.palettes["dark-medium"].colors.bg0')" = "#2D353B" ]
  [ "$(printf '%s' "$output" | jq -r '.palettes["dark-medium"].colors.green')" = "#A7C080" ]
  [ "$(printf '%s' "$output" | jq -r '.palettes["light-soft"].appearance')" = light ]
  [ "$(printf '%s' "$output" | jq -r '.palettes["light-soft"].colors.bg0')" = "#F3EAD3" ]
  [ "$(printf '%s' "$output" | jq -c '.palettes[].colors | keys' | sort -u | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(printf '%s' "$output" | jq -c '.palettes["dark-hard"].colors | keys')" = '["aqua","bg0","bg1","bg2","bg3","blue","border","dim","fg","green","grey1","hidden_ink","hover","list_hover","list_selected","list_selected_inactive","lockup_ink","on_accent","orange","purple","red","yellow"]' ]
}

@test "list --json carries the three roles, each scheme's own pick" {
  run "$CLI" list --json
  [ "$status" -eq 0 ]
  # Dark: the colours the apps always drew with (bg3, bg0, grey1).
  [ "$(printf '%s' "$output" | jq -c '.palettes["dark-medium"].colors | [.border, .on_accent, .dim]')" = '["#475258","#2D353B","#859289"]' ]
  [ "$(printf '%s' "$output" | jq -c '[.palettes | to_entries[] | select(.key | startswith("dark")) | .value.colors | (.border == .bg3 and .on_accent == .bg0 and .dim == .grey1)] | all')" = true ]
  # Light: bg5, the dark sibling's bg0 as ink, grey2.
  [ "$(printf '%s' "$output" | jq -c '.palettes["light-medium"].colors | [.border, .on_accent, .dim]')" = '["#BDC3AF","#2D353B","#829181"]' ]
  [ "$(printf '%s' "$output" | jq -r '.palettes["light-hard"].colors.on_accent')" = "$(printf '%s' "$output" | jq -r '.palettes["dark-hard"].colors.bg0')" ]
}

@test "list --json carries the wordmark's ink: one on the dark schemes, one on the light" {
  run "$CLI" list --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -c '[.palettes | to_entries[] | select(.key | startswith("dark")) | .value.colors.lockup_ink] | unique')" = '["#DAC7A2"]' ]
  [ "$(printf '%s' "$output" | jq -c '[.palettes | to_entries[] | select(.key | startswith("light")) | .value.colors.lockup_ink] | unique')" = '["#27332A"]' ]
}

@test "list --json carries hover: bg1 on the dark schemes, bg3 on the light" {
  run "$CLI" list --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -c '[.palettes | to_entries[] | select(.key | startswith("dark")) | .value.colors | .hover == .bg1] | unique')" = '[true]' ]
  [ "$(printf '%s' "$output" | jq -c '[.palettes | to_entries[] | select(.key | startswith("light")) | .value.colors | .hover == .bg3] | unique')" = '[true]' ]
}

@test "list --json carries a list's roles: three fills that differ from bg0 and each other, and the hidden ink" {
  run "$CLI" list --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -c '.palettes["dark-medium"].colors | [.list_selected, .list_selected_inactive, .list_hover, .hidden_ink]')" = '["#475258","#3D484D","#343F44","#859289"]' ]
  [ "$(printf '%s' "$output" | jq -c '.palettes["light-soft"].colors | [.list_selected, .list_selected_inactive, .list_hover, .hidden_ink]')" = '["#D8D3BA","#DDD8BE","#E5DFC5","#5C6A72"]' ]
  [ "$(printf '%s' "$output" | jq -c '[.palettes[].colors | [.bg0, .list_selected, .list_selected_inactive, .list_hover] | unique | length] | unique')" = '[4]' ]
}

@test "logo prints grove by default" {
  run "$CLI" logo
  [ "$status" -eq 0 ]
  [ "$output" = grove ]
  run "$CLI" logo --json
  [ "$output" = '{"logo": "grove"}' ]
}

@test "logo avatar saves it, renders the fetch files and logs a logo step" {
  mkdir -p "$GROVE_STATE"; echo light-soft > "$GROVE_STATE/theme"
  run "$CLI" logo avatar
  [ "$status" -eq 0 ]
  [ "$output" = "grove-themes: logo avatar" ]
  [ "$(cat "$GROVE_STATE/fetch-logo")" = avatar ]
  grep -q 'avatar-light-soft.png' "$GROVE_ROOT/config/fastfetch/config.jsonc"
  grep -q '"width": 46,' "$GROVE_ROOT/config/fastfetch/config.jsonc"
  grep -q 'COLUMNS >= 108' "$GROVE_ROOT/config/zsh/conf.d/95-fetch.zsh"
  tail -n 1 "$GROVE_STATE/theme-log.jsonl" | grep -q '"scheme": "light-soft", "exit": 0, "steps": \[{"name": "logo", "result": "live", "message": "avatar"}\]'
  run "$CLI" logo
  [ "$output" = avatar ]
}

@test "logo grove brings back the grove renders" {
  mkdir -p "$GROVE_STATE"; echo dark-medium > "$GROVE_STATE/theme"
  "$CLI" logo avatar
  run "$CLI" logo grove --json
  [ "$status" -eq 0 ]
  [ "$output" = '{"logo": "grove"}' ]
  cmp "$DOTFILES/tests/fixtures/dark-medium/fastfetch/config.jsonc" "$GROVE_ROOT/config/fastfetch/config.jsonc"
  cmp "$DOTFILES/tests/fixtures/dark-medium/zsh/conf.d/95-fetch.zsh" "$GROVE_ROOT/config/zsh/conf.d/95-fetch.zsh"
}

@test "logo with an unknown name exits 2 with usage" {
  run "$CLI" logo banana
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: grove-themes"* ]] || false
  [ ! -e "$GROVE_STATE/fetch-logo" ]
}

@test "logo keeps the state and files when a render fails" {
  mkdir -p "$GROVE_STATE"; echo dark-medium > "$GROVE_STATE/theme"
  "$CLI" logo grove
  cp "$GROVE_ROOT/config/fastfetch/config.jsonc" "$BATS_TEST_TMPDIR/before"
  printf 'x={{nope}}\n' > "$GROVE_ROOT/config/broken.tmpl"
  run "$CLI" logo avatar
  [ "$status" -eq 1 ]
  [ "$(cat "$GROVE_STATE/fetch-logo")" = grove ]
  cmp "$BATS_TEST_TMPDIR/before" "$GROVE_ROOT/config/fastfetch/config.jsonc"
}

@test "list --json carries the logo and the logos" {
  run "$CLI" list --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"logo": "grove", "logos": ["grove", "avatar"]'* ]] || false
}

@test "set keeps the chosen logo" {
  mkdir -p "$GROVE_STATE"; echo dark-medium > "$GROVE_STATE/theme"
  "$CLI" logo avatar
  run "$CLI" set light-medium
  grep -q 'avatar-light-medium.png' "$GROVE_ROOT/config/fastfetch/config.jsonc"
}

@test "logo --json prints only JSON when a hand-edited config is backed up" {
  mkdir -p "$GROVE_STATE"; echo dark-medium > "$GROVE_STATE/theme"
  "$CLI" logo grove
  echo "# my edit" >> "$GROVE_ROOT/config/ghostty/config"
  run --separate-stderr "$CLI" logo avatar --json
  [ "$status" -eq 0 ]
  [ "$output" = '{"logo": "avatar"}' ]
  [[ "$stderr" == *"backed up edited ghostty/config to "* ]] || false
}

wp_avatar_files() {
  local s
  for s in dark-hard dark-medium dark-soft light-hard light-medium light-soft; do
    : > "$GROVE_WALLPAPER_DIR/wallpaper-avatar-$s.png"
  done
}

@test "wallpaper prints grove by default" {
  run "$CLI" wallpaper
  [ "$status" -eq 0 ]
  [ "$output" = grove ]
  run "$CLI" wallpaper --json
  [ "$output" = '{"wallpaper": "grove"}' ]
}

@test "wallpaper avatar saves it, sets the avatar picture, logs a wallpaper step, --json is only JSON" {
  wp_avatar_files
  mkdir -p "$GROVE_STATE"; echo light-soft > "$GROVE_STATE/theme"
  stub osascript 'cat > /dev/null; echo "$2" >> "$BATS_TEST_TMPDIR/pictures"; exit 0'
  run --separate-stderr "$CLI" wallpaper avatar --json
  [ "$status" -eq 0 ]
  [[ "$output" == '{"wallpaper": "avatar", "steps": [{"name": "wallpaper", "result": "live", "message": '* ]] || false
  printf '%s' "$output" | /opt/homebrew/bin/python3 -I -c 'import json,sys; json.load(sys.stdin)'
  [ "$(cat "$GROVE_STATE/wallpaper")" = avatar ]
  grep -q 'wallpaper-avatar-light-soft.png' "$BATS_TEST_TMPDIR/pictures"
  tail -n 1 "$GROVE_STATE/theme-log.jsonl" | grep -q '"scheme": "light-soft", "exit": 0, "steps": \[{"name": "wallpaper", "result": "live"'
  run "$CLI" wallpaper
  [ "$output" = avatar ]
}

@test "wallpaper with Automation refused says needs-you, exits 1 and still saves the choice" {
  wp_avatar_files
  stub osascript 'cat > /dev/null; exit 1'
  run "$CLI" wallpaper avatar
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs-you"* ]] || false
  [ "$(cat "$GROVE_STATE/wallpaper")" = avatar ]
}

@test "wallpaper with a missing picture exits 1 and saves nothing" {
  run "$CLI" wallpaper avatar
  [ "$status" -eq 1 ]
  [[ "$output" == *"wallpaper not found:"*"wallpaper-avatar-dark-medium.png"* ]] || false
  [ ! -e "$GROVE_STATE/wallpaper" ]
}

@test "wallpaper with an unknown name exits 2" {
  run "$CLI" wallpaper banana
  [ "$status" -eq 2 ]
  [ ! -e "$GROVE_STATE/wallpaper" ]
}

@test "list --json carries the wallpaper and the wallpapers" {
  run "$CLI" list --json
  [[ "$output" == *'"wallpaper": "grove", "wallpapers": ["grove", "avatar"]'* ]] || false
}
