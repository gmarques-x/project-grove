# shellcheck disable=SC2016,SC1090,SC1091,SC2154
# 85-macos-wallpaper, against a fake osascript: $BATS_TEST_TMPDIR/desktops holds
# one picture path per screen. FAKE_OSA_FAIL=1 acts like a denied Automation prompt.
load helpers

WP_MODULE=85-macos-wallpaper

load_module() {
  local f
  for f in "$GROVE_ROOT"/lib/*.sh; do . "$f"; done
  MODULE_DIR="$GROVE_ROOT/modules/$WP_MODULE"
  . "$MODULE_DIR/module.sh"
}

setup() {
  grove_test_setup
  WANT="$(cd "$GROVE_ROOT/.." && pwd -P)/grove-wallpapers/wallpaper-project-grove-dark-medium.png"
  printf '%s\n' /System/Library/Desktop\ Pictures/Sequoia.heic /System/Library/Desktop\ Pictures/Sequoia.heic \
    > "$BATS_TEST_TMPDIR/desktops"
  stub osascript '
script=$(cat)
st="$BATS_TEST_TMPDIR/desktops"
if [ -n "$FAKE_OSA_FAIL" ]; then
  echo "execution error: Not authorized to send Apple events to System Events. (-1743)" >&2; exit 1
fi
if printf "%s" "$script" | grep -q "set picture"; then
  n=$(wc -l < "$st"); : > "$st"
  for _ in $(seq "$n"); do printf "%s\n" "$2" >> "$st"; done
else
  cat "$st"
fi'
}

@test "wallpaper: the picture is tracked in grove-wallpapers" {
  git -C "$GROVE_ROOT/.." ls-files --error-unmatch grove-wallpapers/wallpaper-project-grove-dark-medium.png
}

@test "wallpaper: about names it" {
  load_module
  run about
  [ "$output" = "Desktop wallpaper" ]
}

@test "wallpaper: needs work when a screen shows another picture" {
  load_module
  printf '%s\n%s\n' "$WANT" /System/Library/Desktop\ Pictures/Sequoia.heic > "$BATS_TEST_TMPDIR/desktops"
  run check
  [ "$status" -eq 3 ]
}

@test "wallpaper: ok when every screen shows the Grove wallpaper" {
  load_module
  printf '%s\n%s\n' "$WANT" "$WANT" > "$BATS_TEST_TMPDIR/desktops"
  run check
  [ "$status" -eq 0 ]
}

@test "wallpaper: apply sets every screen, then check is ok" {
  load_module
  run apply
  [ "$status" -eq 0 ]
  [ "$(sort -u "$BATS_TEST_TMPDIR/desktops")" = "$WANT" ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/desktops")" -eq 2 ]
  [[ "$output" == *Spaces* ]]
  run check
  [ "$status" -eq 0 ]
}

@test "wallpaper: a missing picture fails with its path" {
  export GROVE_WALLPAPER_DIR="$BATS_TEST_TMPDIR/nowhere"
  load_module
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"$BATS_TEST_TMPDIR/nowhere/wallpaper-project-grove-dark-medium.png"* ]]
}

@test "wallpaper: needs you when System Events can't be controlled" {
  export FAKE_OSA_FAIL=1
  load_module
  run check
  [ "$status" -eq 4 ]
  run apply
  [ "$status" -ne 0 ]
  [[ "$output" == *Automation* ]]
}

@test "wallpaper: wants the current scheme's picture" {
  mkdir -p "$GROVE_STATE"; echo light-soft > "$GROVE_STATE/theme"
  load_module
  SOFT="$(cd "$GROVE_ROOT/.." && pwd -P)/grove-wallpapers/wallpaper-project-grove-light-soft.png"
  printf '%s\n%s\n' "$WANT" "$WANT" > "$BATS_TEST_TMPDIR/desktops"
  run check
  [ "$status" -eq 3 ]
  run apply
  [ "$status" -eq 0 ]
  [ "$(sort -u "$BATS_TEST_TMPDIR/desktops")" = "$SOFT" ]
  run check
  [ "$status" -eq 0 ]
}

@test "wallpaper: an unknown or empty scheme means dark-medium" {
  mkdir -p "$GROVE_STATE"; echo nonsense > "$GROVE_STATE/theme"
  load_module
  [ "$(_wp_file)" = "$WANT" ]
  : > "$GROVE_STATE/theme"
  [ "$(_wp_file)" = "$WANT" ]
}

@test "wallpaper: the README lists the module" {
  grep -q '^| `85-macos-wallpaper` |' "$GROVE_ROOT/README.md"
}
