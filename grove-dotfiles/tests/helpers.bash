# Shared test helpers. Every .bats file: `load helpers` + `setup() { grove_test_setup; }`.

grove_test_setup() {
  GROVE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
  export GROVE_ROOT
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/stubs"
  export GROVE_CONFIG="$GROVE_ROOT/config"
  export GROVE_STATE="$HOME/.local/state/grove"
  export GROVE_LOCAL="$HOME/.config/grove/local.env"
  export GROVE_RUN_ID=test
  export GROVE_TTY="$BATS_TEST_TMPDIR/tty"
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
