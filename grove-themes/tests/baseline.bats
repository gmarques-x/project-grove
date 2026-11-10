# The suite baseline (setup_suite.bash) holds even in a file that never calls
# gt_test_setup: no test can reach the real home, state, config or desktop.

@test "without gt_test_setup, HOME, GROVE_STATE and GROVE_ROOT are suite temp paths" {
  [ -n "$BATS_SUITE_TMPDIR" ]
  [[ "$HOME" == "$BATS_SUITE_TMPDIR"/* ]] || false
  [[ "$GROVE_STATE" == "$BATS_SUITE_TMPDIR"/* ]] || false
  [[ "$GROVE_ROOT" == "$BATS_SUITE_TMPDIR"/* ]] || false
  [ ! -e "$GROVE_ROOT" ]
  [[ "$GROVE_WALLPAPER_DIR" == "$BATS_SUITE_TMPDIR"/* ]] || false
}

@test "without gt_test_setup, the desktop commands are no-op stubs" {
  local c
  for c in osascript defaults ps; do
    [[ "$(command -v "$c")" == "$BATS_SUITE_TMPDIR"/stubs/"$c" ]] || false
  done
  # kill is a builtin, so steps.sh calls it through GROVE_KILL; the PATH copy
  # still is a stub, for anything that execs it.
  [[ "$(type -P kill)" == "$BATS_SUITE_TMPDIR"/stubs/kill ]] || false
  [[ "$GROVE_KILL" == "$BATS_SUITE_TMPDIR"/stubs/kill ]] || false
  [[ "$GROVE_PS" == "$BATS_SUITE_TMPDIR"/stubs/ps ]] || false
}

@test "without gt_test_setup, render without --config finds no config to write" {
  run "$BATS_TEST_DIRNAME/../bin/grove-themes" render
  [ "$status" -ne 0 ]
  [[ "$output" == *"$BATS_SUITE_TMPDIR"* ]] || false
}

@test "gt_test_setup keeps GROVE_ROOT and GROVE_STATE off the live checkout" {
  load helpers
  gt_test_setup
  [[ "$GROVE_ROOT" == "$BATS_TEST_TMPDIR"/* ]] || false
  [ ! -e "$GROVE_ROOT" ]
  [[ "$GROVE_STATE" == "$HOME"/* ]] || false
  [[ "$HOME" == "$BATS_TEST_TMPDIR"/* ]] || false
  [[ "$GROVE_PS" == "$BATS_TEST_TMPDIR"/stubs/ps ]] || false
}
