load helpers

setup() {
  grove_test_setup
  export GROVE_MODULES="$GROVE_ROOT/tests/fixtures/modules"
  mkdir -p "$(dirname "$GROVE_LOCAL")"
  printf 'GROVE_NAME=T\nGROVE_EMAIL=t@e.x\nGROVE_GITHUB_USER=t\n' > "$GROVE_LOCAL"
  GROVE="$GROVE_ROOT/bin/grove"
}

@test "list shows each module and its about line" {
  run "$GROVE" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"10-ok"*"Always fine"* ]]
  [[ "$output" == *"40-broken"*"Always fails"* ]]
}

@test "check prints a status per module and exits 3" {
  run "$GROVE" check
  [ "$status" -eq 3 ]
  [[ "$output" == *"ok"*"10-ok"* ]]
  [[ "$output" == *"needs work"*"20-work"* ]]
  [[ "$output" == *"needs you"*"30-you"* ]]
}

@test "check exits 0 when everything is ok" {
  mkdir "$BATS_TEST_TMPDIR/mods"; cp -R "$GROVE_MODULES/10-ok" "$BATS_TEST_TMPDIR/mods/"
  GROVE_MODULES="$BATS_TEST_TMPDIR/mods" run "$GROVE" check
  [ "$status" -eq 0 ]
}

@test "check changes nothing" {
  run "$GROVE" check
  [ ! -e "$HOME/apply.log" ]
}

@test "install skips apply when check is ok" {
  run "$GROVE" install 10-ok
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/apply.log" ]
}

@test "install applies needs-work modules and stops at a failure" {
  run "$GROVE" install 20-work 40-broken
  [ "$status" -eq 1 ]
  [ "$(cat "$HOME/apply.log")" = "$(printf '20-work\n40-broken')" ]
  [[ "$output" == *"grove install broken"* ]]
}

@test "install stops at the first failure and runs nothing after it" {
  run "$GROVE" install 40-broken 20-work
  [ "$status" -eq 1 ]
  [ "$(cat "$HOME/apply.log")" = "40-broken" ]
}

@test "install --yes skips needs-you modules and exits 3" {
  run "$GROVE" --yes install 30-you
  [ "$status" -eq 3 ]
  [[ "$output" == *"30-you"* ]]
  [ ! -e "$HOME/apply.log" ]
}

@test "options work after the subcommand too" {
  run "$GROVE" install --yes 30-you
  [ "$status" -eq 3 ]
  run "$GROVE" list --quiet
  [ "$status" -eq 0 ]
}

@test "a run writes a log" {
  run "$GROVE" check
  [ -n "$(ls "$GROVE_STATE/logs")" ]
  grep -q "10-ok" "$GROVE_STATE/logs/test.log"
}

@test "grove resolves its root when called through a symlink from another folder" {
  local g="$BATS_TEST_TMPDIR/g"
  mkdir -p "$g/modules" "$HOME/.local/bin"
  cp -R "$GROVE_ROOT/bin" "$GROVE_ROOT/lib" "$g/"
  cp -R "$GROVE_MODULES/10-ok" "$g/modules/"
  ln -s "$g/bin/grove" "$HOME/.local/bin/grove"
  cd /
  run env -u GROVE_ROOT -u GROVE_MODULES -u GROVE_CONFIG "$HOME/.local/bin/grove" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"10-ok"* ]]
}

@test "unknown module name fails with a message" {
  run "$GROVE" install nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"nope"* ]]
}

@test "module without the contract functions fails that module, not grove" {
  mkdir "$BATS_TEST_TMPDIR/mods"; mkdir "$BATS_TEST_TMPDIR/mods/10-bad"
  echo 'about() { :; }' > "$BATS_TEST_TMPDIR/mods/10-bad/module.sh"
  GROVE_MODULES="$BATS_TEST_TMPDIR/mods" run "$GROVE" check
  [ "$status" -eq 3 ]
  [[ "$output" == *"10-bad"*"check"* ]]
}

@test "modules see the personal values and run variables" {
  mkdir "$BATS_TEST_TMPDIR/mods"; mkdir "$BATS_TEST_TMPDIR/mods/10-env"
  cat > "$BATS_TEST_TMPDIR/mods/10-env/module.sh" <<'M'
about() { :; }
check() { [ "$GROVE_NAME" = T ] && [ -n "$GROVE_RUN_ID" ] && [ -n "$MODULE_DIR" ] && [ -n "$GROVE_STATE" ]; }
apply() { :; }
M
  GROVE_MODULES="$BATS_TEST_TMPDIR/mods" run "$GROVE" check
  [ "$status" -eq 0 ]
}

@test "usage and bad arguments" {
  run "$GROVE" --help;  [ "$status" -eq 0 ]
  run "$GROVE";         [ "$status" -eq 2 ]
  run "$GROVE" --bogus; [ "$status" -eq 2 ]
  run "$GROVE" bogus;   [ "$status" -eq 2 ]
}

@test "update pulls then installs" {
  stub git 'echo "git $*" >> "$HOME/git.log"'
  run "$GROVE" update 20-work
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/git.log")" = "git -C $GROVE_ROOT/.. pull --ff-only" ]
  [ -e "$HOME/applied-20" ]
}

@test "update with a failing pull exits 1 and runs no module" {
  stub git 'exit 1'
  run "$GROVE" update 20-work
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/apply.log" ]
}
