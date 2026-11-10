# Suite setup (bats runs it once, for the whole folder or a single file).
# GROVE_RENDERED: a Dark Medium render of a copy of the tracked config, so tests
# read generated files (spec §5) from there, never from $GROVE_ROOT/config.

setup_suite() {
  # shellcheck source=/dev/null
  . "$(dirname "${BASH_SOURCE[0]}")/helpers.bash"
  GROVE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
  unset GROVE_RENDERED   # render it here, don't copy a previous one
  grove_copy_tracked_config "$BATS_SUITE_TMPDIR/config" "$GROVE_ROOT" || return 1
  export GROVE_RENDERED="$BATS_SUITE_TMPDIR/config"
}
