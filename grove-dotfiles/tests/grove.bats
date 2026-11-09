load helpers
bats_require_minimum_version 1.5.0

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
  [[ "$output" == *"10-ok"*"Always fine"* ]] || false
  [[ "$output" == *"40-broken"*"Always fails"* ]] || false
}

@test "check prints a status per module and exits 3" {
  run "$GROVE" check
  [ "$status" -eq 3 ]
  [[ "$output" == *"ok"*"10-ok"* ]] || false
  [[ "$output" == *"needs work"*"20-work"* ]] || false
  [[ "$output" == *"needs you"*"30-you"* ]] || false
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
  [[ "$output" == *"grove install broken"* ]] || false
}

@test "install stops at the first failure and runs nothing after it" {
  run "$GROVE" install 40-broken 20-work
  [ "$status" -eq 1 ]
  [ "$(cat "$HOME/apply.log")" = "40-broken" ]
}

@test "install --yes skips needs-you modules and exits 3" {
  run "$GROVE" --yes install 30-you
  [ "$status" -eq 3 ]
  [[ "$output" == *"skipped 30-you (needs you; run: grove install you)"* ]] || false
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
  [[ "$output" == *"10-ok"* ]] || false
}

@test "unknown module name fails with a message" {
  run "$GROVE" install nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"nope"* ]] || false
}

@test "module without the contract functions fails that module, not grove" {
  mkdir "$BATS_TEST_TMPDIR/mods"; mkdir "$BATS_TEST_TMPDIR/mods/10-bad"
  echo 'about() { :; }' > "$BATS_TEST_TMPDIR/mods/10-bad/module.sh"
  GROVE_MODULES="$BATS_TEST_TMPDIR/mods" run "$GROVE" check
  [ "$status" -eq 3 ]
  [[ "$output" == *"10-bad"*"check"* ]] || false
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

@test "a complete local.env is never rewritten, extra lines survive" {
  echo 'EXTRA=keep' >> "$GROVE_LOCAL"
  local before; before="$(ls -i "$GROVE_LOCAL"; cat "$GROVE_LOCAL")"
  sleep 1
  run "$GROVE" --yes install 10-ok
  run "$GROVE" --yes install 10-ok
  [ "$before" = "$(ls -i "$GROVE_LOCAL"; cat "$GROVE_LOCAL")" ]
  grep -qx 'EXTRA=keep' "$GROVE_LOCAL"
}

@test "stderr stays on stderr and the log has both streams" {
  run --separate-stderr "$GROVE" install nope
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"unknown module: nope"* ]] || false
  [[ "$output" != *"nope"* ]] || false
  grep -q "unknown module: nope" "$GROVE_STATE/logs/test.log"
  run --separate-stderr "$GROVE" check
  [[ "$output" == *"10-ok"* ]] || false
  grep -q "10-ok" "$GROVE_STATE/logs/test.log"
}

@test "output is complete and exit code preserved for a long run" {
  mkdir "$BATS_TEST_TMPDIR/mods" "$BATS_TEST_TMPDIR/mods/10-x"
  printf 'about() { :; }\ncheck() { seq 1 3000; echo last >&2; return 3; }\napply() { :; }\n' > "$BATS_TEST_TMPDIR/mods/10-x/module.sh"
  GROVE_MODULES="$BATS_TEST_TMPDIR/mods" run --separate-stderr "$GROVE" check
  [ "$status" -eq 3 ]
  [[ "$stderr" == *last* ]] || false
  [ "$(grep -c . "$GROVE_STATE/logs/test.log")" -ge 3001 ]
}

@test "a module sees GROVE_YES=1 under --yes install" {
  mkdir "$BATS_TEST_TMPDIR/mods" "$BATS_TEST_TMPDIR/mods/10-y"
  printf 'about() { :; }\ncheck() { [ "$GROVE_YES" = 1 ]; echo $? >/dev/null; return 3; }\napply() { [ "$GROVE_YES" = 1 ] && touch "$HOME/saw-yes"; }\n' > "$BATS_TEST_TMPDIR/mods/10-y/module.sh"
  GROVE_MODULES="$BATS_TEST_TMPDIR/mods" run "$GROVE" --yes install
  [ -e "$HOME/saw-yes" ]
}

@test "apply sees the personal values on the install path" {
  mkdir "$BATS_TEST_TMPDIR/mods" "$BATS_TEST_TMPDIR/mods/10-p"
  printf 'about() { :; }\ncheck() { return 3; }\napply() { echo "$GROVE_NAME|$GROVE_EMAIL|$GROVE_GITHUB_USER" > "$HOME/vals"; }\n' > "$BATS_TEST_TMPDIR/mods/10-p/module.sh"
  GROVE_MODULES="$BATS_TEST_TMPDIR/mods" run env -u GROVE_NAME -u GROVE_EMAIL "$GROVE" install
  [ "$(cat "$HOME/vals")" = "T|t@e.x|t" ]
}

@test "a module lacking a function after one that has it still fails cleanly" {
  mkdir "$BATS_TEST_TMPDIR/mods" "$BATS_TEST_TMPDIR/mods/10-a" "$BATS_TEST_TMPDIR/mods/20-b"
  printf 'about() { :; }\ncheck() { return 0; }\napply() { :; }\n' > "$BATS_TEST_TMPDIR/mods/10-a/module.sh"
  echo 'about() { :; }' > "$BATS_TEST_TMPDIR/mods/20-b/module.sh"
  GROVE_MODULES="$BATS_TEST_TMPDIR/mods" run "$GROVE" check
  [ "$status" -eq 3 ]
  [[ "$output" == *"20-b: module is missing the function 'check'"* ]] || false
}

@test "--quiet hides info lines, their absence otherwise" {
  run "$GROVE" --yes install 30-you
  [[ "$output" == *"skipped 30-you"* ]] || false
  run "$GROVE" --yes --quiet install 30-you
  [[ "$output" != *"skipped 30-you"* ]] || false
}

# ---- I-3: failure output and --yes summary survive --quiet

@test "a failed apply prints retry, log and backup folder even with --quiet" {
  mkdir "$BATS_TEST_TMPDIR/mods" "$BATS_TEST_TMPDIR/mods/10-bk"
  cat > "$BATS_TEST_TMPDIR/mods/10-bk/module.sh" <<'M'
about() { :; }
check() { return 3; }
apply() { echo x > "$HOME/old"; grove_backup "$HOME/old" >/dev/null; return 1; }
M
  GROVE_MODULES="$BATS_TEST_TMPDIR/mods" run --separate-stderr "$GROVE" --quiet install
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"grove install bk"* ]] || false
  [[ "$stderr" == *"log: $GROVE_STATE/logs/test.log"* ]] || false
  [[ "$stderr" == *"backups: $GROVE_STATE/backup/test"* ]] || false
}

@test "no backups line when nothing was backed up" {
  run --separate-stderr "$GROVE" --quiet install 40-broken
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"log: "* ]] || false
  [[ "$stderr" != *"backups:"* ]] || false
}

@test "backup notices are not hidden by --quiet" {
  echo old > "$HOME/.zshrc"; echo old > "$HOME/.zprofile"
  local f
  for f in "$GROVE_ROOT"/lib/*.sh; do . "$f"; done
  GROVE_QUIET=1 run grove_link "$GROVE_ROOT/bin/grove" "$HOME/.zshrc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"backed up $HOME/.zshrc to "* ]] || false
}

@test "--yes lists skipped needs-you modules in a final summary, even with --quiet" {
  run "$GROVE" --yes --quiet install 30-you
  [ "$status" -eq 3 ]
  [[ "$output" == *"Skipped because they need you"* ]] || false
  [[ "$output" == *"30-you: run grove install you"* ]] || false
}
