# Suite setup (bats runs it once, for the whole folder or a single file).
# A safe baseline for every test, even one whose file forgets gt_test_setup:
# HOME, GROVE_STATE and the wallpapers live in the suite's temp folder, the
# desktop commands are no-op stubs first on PATH, and GROVE_ROOT points at a
# folder that doesn't exist, so `set` and `render` can't find the live config.
# Tests that need a dotfiles checkout set GROVE_ROOT to their own copy.

setup_suite() {
  local base="$BATS_SUITE_TMPDIR" c s
  export HOME="$base/home"
  export GROVE_STATE="$HOME/.local/state/grove"
  export GROVE_ROOT="$base/no-grove-root"
  export GROVE_WALLPAPER_DIR="$base/wallpapers"
  export GROVE_CHROME_APP="$base/no-chrome.app"
  mkdir -p "$HOME" "$base/stubs" "$GROVE_WALLPAPER_DIR"
  for c in osascript defaults kill killall ps sketchybar; do
    printf '#!/bin/bash\ncat > /dev/null 2>&1 < /dev/null; exit 0\n' > "$base/stubs/$c"
    chmod +x "$base/stubs/$c"
  done
  export PATH="$base/stubs:$PATH"
  export GROVE_KILL="$base/stubs/kill"
  export GROVE_KILLALL="$base/stubs/killall"
  export GROVE_SKETCHYBAR="$base/stubs/sketchybar"
  export GROVE_WALLPAPER_STORE="$base/wallpaper-store/Index.plist"
  export GROVE_PS="$base/stubs/ps"
  for s in dark-hard dark-medium dark-soft light-hard light-medium light-soft; do
    : > "$GROVE_WALLPAPER_DIR/wallpaper-project-grove-$s.png"
  done
}
