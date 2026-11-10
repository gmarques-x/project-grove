# Shared test helpers. Every .bats file: `load helpers` + `setup() { gt_test_setup; }`.
# setup_suite.bash already gives every test a safe baseline; gt_test_setup
# narrows it to this test's own temp folder.

gt_test_setup() {
  GT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
  export GT_ROOT
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/stubs"
  export GROVE_STATE="$HOME/.local/state/grove"
  # No live checkout: tests that need one point GROVE_ROOT at their own copy.
  export GROVE_ROOT="$BATS_TEST_TMPDIR/no-grove-root"
  export NO_COLOR=1
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
  # Safety: `set` must never reach the real desktop. No-op fakes for everything
  # it calls; tests that care replace them.
  local c s
  for c in osascript defaults kill ps; do stub "$c" 'cat > /dev/null 2>&1 < /dev/null; exit 0'; done
  export GROVE_KILL="$BATS_TEST_TMPDIR/stubs/kill"
  export GROVE_PS="$BATS_TEST_TMPDIR/stubs/ps"
  export GROVE_WALLPAPER_DIR="$BATS_TEST_TMPDIR/wallpapers"
  # Never the real Chrome: not installed unless a test says otherwise.
  export GROVE_CHROME_APP="$BATS_TEST_TMPDIR/no-chrome.app"
  mkdir -p "$GROVE_WALLPAPER_DIR"
  for s in dark-hard dark-medium dark-soft light-hard light-medium light-soft; do
    : > "$GROVE_WALLPAPER_DIR/wallpaper-project-grove-$s.png"
  done
}

# stub <cmd> <script body>: executable bash stub placed first on PATH.
stub() {
  local cmd="$1" body="$2"
  mkdir -p "$BATS_TEST_TMPDIR/stubs"
  printf '#!/bin/bash\n%s\n' "$body" > "$BATS_TEST_TMPDIR/stubs/$cmd"
  chmod +x "$BATS_TEST_TMPDIR/stubs/$cmd"
}

# gt_toy_palettes: a palette dir with all six schemes; each has fg, bg0 and a
# value unique to the scheme (so a wrong scheme shows).
gt_toy_palettes() {
  PALETTES="$BATS_TEST_TMPDIR/palettes"
  mkdir -p "$PALETTES"
  local s n=0
  for s in dark-hard dark-medium dark-soft light-hard light-medium light-soft; do
    n=$((n + 1))
    {
      echo "# toy palette for $s"
      echo
      echo "fg    = #D3C6A$n"
      echo "bg0   = #27E3$n"
      echo "amp   = #A&B/C\\$n"
    } > "$PALETTES/everforest-$s"
  done
}
