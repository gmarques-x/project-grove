# Shared test helpers. Every .bats file: `load helpers` + `setup() { gt_test_setup; }`.

gt_test_setup() {
  GT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
  export GT_ROOT
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/stubs"
  export NO_COLOR=1
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
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
