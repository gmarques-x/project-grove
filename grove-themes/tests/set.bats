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
  stub killall 'echo "killall $*" >> "$CALLS"'
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

@test "the wallpaper path is clean, the same text 85-macos-wallpaper checks for" {
  local clean
  clean="$(cd "$GROVE_WALLPAPER_DIR" && pwd -P)"
  export GROVE_WALLPAPER_DIR="$GROVE_WALLPAPER_DIR/../$(basename "$GROVE_WALLPAPER_DIR")"
  run "$CLI" set light-soft
  [ "$status" -eq 0 ]
  grep -q "^osascript - $clean/wallpaper-project-grove-light-soft.png\$" "$CALLS"
  run grep -q '/\.\./' "$CALLS"
  [ "$status" -ne 0 ]
}

@test "set puts the scheme's wallpaper on every screen" {
  run "$CLI" set light-soft
  [ "$status" -eq 0 ]
  grep -q "^osascript - $(cd "$GROVE_WALLPAPER_DIR" && pwd -P)/wallpaper-project-grove-light-soft.png\$" "$CALLS"
  grep -q 'set picture of every desktop' "$CALLS"
}

@test "a denied Automation prompt doesn't stop the other steps" {
  export FAKE_OSA_FAIL=1
  run "$CLI" set light-soft
  [ "$status" -eq 1 ]
  [[ "$output" == *Automation* ]] || false
  [[ "$output" == *"allow Grove Themes or your terminal to control System Events (System Settings > Privacy & Security > Automation), then switch again"* ]] || false
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

@test "a render into another folder leaves the last-written records alone" {
  run "$CLI" set dark-medium
  [ "$status" -eq 0 ]
  before="$(cd "$GROVE_STATE/theme-rendered" && find . -type f -exec cksum {} + | LC_ALL=C sort)"
  gt_copy_config "$BATS_TEST_TMPDIR/preview"
  run "$CLI" render --scheme light-soft --config "$BATS_TEST_TMPDIR/preview"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/preview/ghostty/config" ]
  after="$(cd "$GROVE_STATE/theme-rendered" && find . -type f -exec cksum {} + | LC_ALL=C sort)"
  [ "$before" = "$after" ]
  run "$CLI" set dark-soft
  [ "$status" -eq 0 ]
  [[ "$output" != *"backed up"* ]] || false
}

@test "a render through a link to the config still records what it wrote" {
  run "$CLI" set dark-medium
  [ "$status" -eq 0 ]
  ln -s "$GROVE_ROOT/config" "$HOME/.config"
  run "$CLI" render --scheme dark-hard --config "$HOME/.config"
  [ "$status" -eq 0 ]
  run "$CLI" set dark-soft
  [ "$status" -eq 0 ]
  [[ "$output" != *"backed up"* ]] || false
}

@test "set --json lists every step" {
  run "$CLI" set --json dark-soft
  [ "$status" -eq 0 ]
  names="$(printf '%s' "$output" | grep -o '"name": "[a-z]*"' | sed 's/"name": //' | tr -d '"\n' )"
  [ "$names" = "configsghosttyzshstarshipezabatfastfetchvscodechromeyazibordersbar""appearanceaccentwallpaper" ]
}

borders_line() { printf '%s\n' "$output" | grep '^borders '; }

# fake_borders_sh: GROVE_BORDERS_SH logs the script it runs, exits $FAKE_SH_RC.
fake_borders_sh() {
  stub fakesh 'echo "sh $*" >> "$CALLS"; exit "${FAKE_SH_RC:-0}"'
  export GROVE_BORDERS_SH="$BATS_TEST_TMPDIR/stubs/fakesh"
  stub bordersps 'printf "%s\n" "  202 /usr/bin/zsh" "  505 /opt/homebrew/bin/borders" "  606 /usr/bin/vim bordersrc"'
}

@test "borders: recolours a running borders" {
  fake_borders_sh
  export GROVE_PS=bordersps
  run "$CLI" set dark-soft
  [ "$status" -eq 0 ]
  [[ "$(borders_line)" == *"live"*"recoloured"* ]] || false
  grep -qx "sh $GROVE_ROOT/config/borders/bordersrc" "$CALLS"
  grep -q 'active_color=' "$GROVE_ROOT/config/borders/bordersrc"
}

@test "borders: leaves a stopped borders alone" {
  fake_borders_sh
  stub vimps 'printf "%s\n" "  606 /usr/bin/vim" "  707 /tmp/bordersrc"'
  export GROVE_PS=vimps
  run "$CLI" set dark-soft
  [ "$status" -eq 0 ]
  [[ "$(borders_line)" == *"live"*"not running"* ]] || false
  run grep -q '^sh ' "$CALLS"
  [ "$status" -ne 0 ]
}

@test "borders: a failing script fails the step" {
  fake_borders_sh
  export GROVE_PS=bordersps FAKE_SH_RC=1
  run "$CLI" set dark-soft
  [ "$status" -eq 1 ]
  [[ "$(borders_line)" == *"failed"*"could not recolour the borders"* ]] || false
}

chrome_line() { printf '%s\n' "$output" | grep '^chrome '; }

@test "chrome: not installed is live, not a problem" {
  export GROVE_CHROME_APP="$BATS_TEST_TMPDIR/nope.app"
  run "$CLI" set dark-soft
  [ "$status" -eq 0 ]
  [[ "$(chrome_line)" == *"live"*"Chrome not installed"* ]] || false
}

@test "chrome: installed with the theme rendered is next-launch" {
  export GROVE_CHROME_APP="$BATS_TEST_TMPDIR/Google Chrome.app"
  mkdir -p "$GROVE_CHROME_APP"
  run "$CLI" set dark-soft
  [ "$status" -eq 0 ]
  [ -f "$GROVE_ROOT/config/chrome-theme/manifest.json" ]
  [[ "$(chrome_line)" == *"next-launch"*"Chrome takes the new colours the next time it starts (load ~/.config/chrome-theme once in chrome://extensions if you haven't)"* ]] || false
}

@test "chrome: set removes Chrome's compiled theme so it rebuilds at the next start" {
  export GROVE_CHROME_APP="$BATS_TEST_TMPDIR/Google Chrome.app"
  mkdir -p "$GROVE_CHROME_APP" "$GROVE_ROOT/config/chrome-theme"
  echo stale > "$GROVE_ROOT/config/chrome-theme/Cached Theme.pak"
  run "$CLI" set dark-soft
  [ "$status" -eq 0 ]
  [ ! -e "$GROVE_ROOT/config/chrome-theme/Cached Theme.pak" ]
  [ -f "$GROVE_ROOT/config/chrome-theme/manifest.json" ]
}

@test "chrome: installed but the theme wasn't rendered fails" {
  export GROVE_CHROME_APP="$BATS_TEST_TMPDIR/Google Chrome.app"
  mkdir -p "$GROVE_CHROME_APP"
  rm "$GROVE_ROOT/config/chrome-theme/manifest.json.tmpl"
  run "$CLI" set dark-soft
  [ "$status" -eq 1 ]
  [[ "$(chrome_line)" == *"failed"*"the Chrome theme wasn't rendered"* ]] || false
}

@test "chrome: the version differs for every scheme" {
  local s v seen=""
  for s in dark-hard light-soft dark-medium; do
    run "$CLI" set "$s"
    v="$(jq -r .version "$GROVE_ROOT/config/chrome-theme/manifest.json")"
    [[ " $seen " != *" $v "* ]] || false
    seen="$seen $v"
  done
}

@test "wallpaper: every Space's entry is rewritten, with a backup and a WallpaperAgent restart" {
  gt_make_store "$GROVE_WALLPAPER_STORE"
  run "$CLI" set light-soft
  [ "$status" -eq 0 ]
  [[ "$output" == *"light-soft on every Space"* ]] || false
  [ "$(gt_store_urls "$GROVE_WALLPAPER_STORE" | sort -u)" = "file://$(cd "$GROVE_WALLPAPER_DIR" && pwd -P)/wallpaper-project-grove-light-soft.png" ]
  [ "$(gt_store_idle "$GROVE_WALLPAPER_STORE" | sort -u)" = "com.apple.wallpaper.choice.aerials:idle" ]
  [ -n "$(find "$GROVE_STATE/backup" -name Index.plist)" ]
  grep -qx 'killall -KILL WallpaperAgent' "$CALLS"
}

@test "wallpaper: a failing helper names the backup in the message" {
  local lib2="$BATS_TEST_TMPDIR/lib2"
  gt_make_store "$GROVE_WALLPAPER_STORE"
  cp -R "$GT_ROOT/lib" "$lib2"
  printf 'import sys\nprint("boom")\nsys.exit(1)\n' > "$lib2/wallpaper_store.py"
  run bash -c '. "$1/render.sh"; . "$1/state.sh"; . "$1/steps.sh"; gt_step_wallpaper dark-soft' _ "$lib2"
  [[ "$output" == *"on the visible Spaces; other Spaces couldn't be updated: boom (backup: $GROVE_STATE/backup/"* ]] || false
}

@test "wallpaper: a missing store leaves the visible Spaces done, no restart" {
  run "$CLI" set light-soft
  [ "$status" -eq 0 ]
  [[ "$output" == *"light-soft on the visible Spaces; other Spaces couldn't be updated: "* ]] || false
  run grep -q killall "$CALLS"
  [ "$status" -ne 0 ]
}

@test "wallpaper: the store stays in place while the helper runs; the backup equals the old store" {
  local lib2="$BATS_TEST_TMPDIR/lib2" b
  gt_make_store "$GROVE_WALLPAPER_STORE"
  cp -p "$GROVE_WALLPAPER_STORE" "$BATS_TEST_TMPDIR/before.plist"
  ino="$(stat -f %i "$GROVE_WALLPAPER_STORE")"
  cp -R "$GT_ROOT/lib" "$lib2"
  mv "$lib2/wallpaper_store.py" "$lib2/real_store.py"
  cat > "$lib2/wallpaper_store.py" <<PY
import os, runpy, sys
open("$BATS_TEST_TMPDIR/seen", "w").write("present %d" % os.stat(sys.argv[1]).st_ino if os.path.isfile(sys.argv[1]) else "missing")
sys.argv[0] = "$lib2/real_store.py"
runpy.run_path("$lib2/real_store.py", run_name="__main__")
PY
  run bash -c '. "$1/render.sh"; . "$1/state.sh"; . "$1/steps.sh"; gt_step_wallpaper dark-soft' _ "$lib2"
  [[ "$output" == *"dark-soft on every Space"* ]] || false
  [ "$(cat "$BATS_TEST_TMPDIR/seen")" = "present $ino" ]
  b="$(find "$GROVE_STATE/backup" -name Index.plist)"
  [ -n "$b" ]
  cmp "$b" "$BATS_TEST_TMPDIR/before.plist"
}

@test "set puts the avatar wallpaper on every screen when it is chosen" {
  for s in dark-hard light-soft; do : > "$GROVE_WALLPAPER_DIR/wallpaper-avatar-$s.png"; done
  mkdir -p "$GROVE_STATE"; echo avatar > "$GROVE_STATE/wallpaper"
  run "$CLI" set light-soft
  grep -q "^osascript - $(cd "$GROVE_WALLPAPER_DIR" && pwd -P)/wallpaper-avatar-light-soft.png\$" "$CALLS"
  run "$CLI" set dark-hard
  grep -q "^osascript - $(cd "$GROVE_WALLPAPER_DIR" && pwd -P)/wallpaper-avatar-dark-hard.png\$" "$CALLS"
}

bar_line() { printf '%s\n' "$output" | grep '^bar '; }

@test "bar: reloads a running sketchybar" {
  stub barps 'printf "%s\n" "  202 /usr/bin/zsh" "  707 /opt/homebrew/opt/sketchybar/bin/sketchybar"'
  export GROVE_PS=barps
  stub sketchybar 'echo "$*" >> "$BATS_TEST_TMPDIR/sketchybar-calls"'
  export GROVE_SKETCHYBAR="$BATS_TEST_TMPDIR/stubs/sketchybar"
  run "$CLI" set dark-hard
  [[ "$(bar_line)" == *"live"*"reloaded"* ]] || false
  [ "$(cat "$BATS_TEST_TMPDIR/sketchybar-calls")" = "--reload" ]
}

@test "bar: says next-launch when sketchybar isn't running" {
  stub barps 'printf "%s\n" "  202 /usr/bin/zsh"'
  export GROVE_PS=barps
  run "$CLI" set dark-hard
  [[ "$(bar_line)" == *"next-launch"* ]] || false
}

@test "bar: a failing reload fails the step" {
  stub barps 'printf "%s\n" "  707 /opt/homebrew/bin/sketchybar"'
  export GROVE_PS=barps
  stub sketchybar 'exit 1'
  export GROVE_SKETCHYBAR="$BATS_TEST_TMPDIR/stubs/sketchybar"
  run "$CLI" set dark-hard
  [[ "$(bar_line)" == *"failed"*"could not reload the bar"* ]] || false
}
