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
  # The suite may run from a linked worktree; one test unsets this (C-1).
  export GROVE_ALLOW_WORKTREE=1
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
}

# stub <cmd> <script body>: executable bash stub placed first on PATH.
stub() {
  local cmd="$1" body="$2"
  mkdir -p "$BATS_TEST_TMPDIR/stubs"
  printf '#!/bin/bash\n%s\n' "$body" > "$BATS_TEST_TMPDIR/stubs/$cmd"
  chmod +x "$BATS_TEST_TMPDIR/stubs/$cmd"
}

# grove_copy_tracked_config DEST [ROOT]: copy only the git-tracked files of
# ROOT/config (default $GROVE_ROOT) into DEST, so private ignored files
# (gh/hosts.yml, grove/local.env, git/local) never reach a test's temp copy.
# Then render Dark Medium into DEST, so the generated files (spec §5) are there
# too. A copy of $GROVE_ROOT reuses the suite's render ($GROVE_RENDERED).
grove_copy_tracked_config() {
  local dest="$1" root="${2:-$GROVE_ROOT}" f
  mkdir -p "$dest"
  while IFS= read -r -d '' f; do
    mkdir -p "$dest/$(dirname "$f")"
    cp -p "$root/config/$f" "$dest/$f"
  done < <(git -C "$root/config" ls-files -z .)
  if [ -n "${GROVE_RENDERED:-}" ] && [ -d "$GROVE_RENDERED" ] && [ "$root" = "$GROVE_ROOT" ] \
     && [ "$dest" != "$GROVE_RENDERED" ]; then
    while IFS= read -r f; do
      cp -p "$GROVE_RENDERED/${f%.tmpl}" "$dest/${f%.tmpl}" || return 1
    done < <(cd "$dest" && find . -type f -name '*.tmpl' | sed 's|^\./||')
  else
    grove_render_config "$dest" "$root" || return 1
  fi
}

# grove_render_config DIR [ROOT]: render every DIR/<f>.tmpl to DIR/<f> for
# Dark Medium, with ROOT/theme's palettes and grove-themes' renderer.
grove_render_config() {
  local dir="$1" root="${2:-$GROVE_ROOT}"
  local lib
  lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)/grove-themes/lib/render.sh"
  (
    # shellcheck source=/dev/null
    . "$lib" || exit 1
    for t in $(gt_templates "$dir"); do
      gt_render_file dark-medium "$root/theme" "$dir/$t" "$dir/${t%.tmpl}" || exit 1
    done
  )
}
