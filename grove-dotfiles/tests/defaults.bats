load helpers

setup() {
  grove_test_setup
  # shellcheck source=/dev/null
  . "$GROVE_ROOT/lib/ui.sh"
  # shellcheck source=/dev/null
  . "$GROVE_ROOT/lib/defaults.sh"
  FIX="$GROVE_ROOT/tests/fixtures/settings.txt"
  defaults delete com.grove.test 2>/dev/null || true
  defaults delete com.grove.testglobal 2>/dev/null || true
}

teardown() {
  defaults delete com.grove.test 2>/dev/null || true
  defaults delete com.grove.testglobal 2>/dev/null || true
}

@test "check reports every setting when the domain is empty" {
  run grove_defaults_check "$FIX"
  [ "$status" -eq 3 ]
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[0]}" == "com.grove.test greeting: "*"hello" ]]
}

@test "apply writes them and reports 3" {
  run grove_defaults_apply "$FIX"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
  [ "$(defaults read com.grove.test greeting)" = "hello" ]
  [ "$(defaults read com.grove.test enabled)" = "1" ]
  [ "$(defaults read com.grove.test count)" = "7" ]
}

@test "check is ok after apply" {
  grove_defaults_apply "$FIX" >/dev/null
  run grove_defaults_check "$FIX"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "apply writes only what differs" {
  grove_defaults_apply "$FIX" >/dev/null
  defaults write com.grove.test count -int 9
  run grove_defaults_apply "$FIX"
  [ "$output" = "1" ]
  [ "$(defaults read com.grove.test count)" = "7" ]
}

@test "comments and blank lines are ignored" {
  printf '\n# only comment\n\n   \n' > "$BATS_TEST_TMPDIR/s.txt"
  run grove_defaults_check "$BATS_TEST_TMPDIR/s.txt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run grove_defaults_apply "$BATS_TEST_TMPDIR/s.txt"
  [ "$output" = "0" ]
}

@test "domain comes from each line" {
  printf 'com.grove.testglobal k string v\ncom.grove.test j int 2\n' > "$BATS_TEST_TMPDIR/s.txt"
  run grove_defaults_apply "$BATS_TEST_TMPDIR/s.txt"
  [ "$output" = "2" ]
  [ "$(defaults read com.grove.testglobal k)" = "v" ]
  [ "$(defaults read com.grove.test j)" = "2" ]
}

@test "floats compare numerically (1.0 vs 1)" {
  printf 'com.grove.test speed float 1.0\ncom.grove.test slow float 0.50\n' > "$BATS_TEST_TMPDIR/s.txt"
  grove_defaults_apply "$BATS_TEST_TMPDIR/s.txt" >/dev/null
  run grove_defaults_check "$BATS_TEST_TMPDIR/s.txt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  defaults write com.grove.test speed -float 2
  run grove_defaults_check "$BATS_TEST_TMPDIR/s.txt"
  [ "$status" -eq 3 ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "bool false reads back as 0 and matches" {
  printf 'com.grove.test off bool false\n' > "$BATS_TEST_TMPDIR/s.txt"
  grove_defaults_apply "$BATS_TEST_TMPDIR/s.txt" >/dev/null
  [ "$(defaults read com.grove.test off)" = "0" ]
  run grove_defaults_check "$BATS_TEST_TMPDIR/s.txt"
  [ "$status" -eq 0 ]
}

@test "malformed line (too few fields) fails with its line number" {
  printf '# c\ncom.grove.test onlythree string\n' > "$BATS_TEST_TMPDIR/s.txt"
  run grove_defaults_check "$BATS_TEST_TMPDIR/s.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 2"* ]]
  run grove_defaults_apply "$BATS_TEST_TMPDIR/s.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 2"* ]]
}

@test "unknown type fails with its line number and writes nothing" {
  printf 'com.grove.test a int 1\ncom.grove.test b array x\n' > "$BATS_TEST_TMPDIR/s.txt"
  run grove_defaults_apply "$BATS_TEST_TMPDIR/s.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 2"* ]]
  run defaults read com.grove.test a
  [ "$status" -ne 0 ]
}

@test "missing file fails" {
  run grove_defaults_check "$BATS_TEST_TMPDIR/nope.txt"
  [ "$status" -eq 1 ]
}

@test "non-canonical int 007 matches after apply" {
  printf 'com.grove.test n int 007\ncom.grove.test m int +5\n' > "$BATS_TEST_TMPDIR/s.txt"
  run grove_defaults_apply "$BATS_TEST_TMPDIR/s.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 2"* ]]
  printf 'com.grove.test n int 007\ncom.grove.test z int -0\n' > "$BATS_TEST_TMPDIR/s.txt"
  run grove_defaults_apply "$BATS_TEST_TMPDIR/s.txt"
  [ "$output" = "2" ]
  run grove_defaults_check "$BATS_TEST_TMPDIR/s.txt"
  [ "$status" -eq 0 ]
}

@test "non-numeric int is rejected and nothing is written" {
  printf 'com.grove.test a int 1\ncom.grove.test n int abc\n' > "$BATS_TEST_TMPDIR/s.txt"
  run grove_defaults_apply "$BATS_TEST_TMPDIR/s.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 2"* ]]
  run defaults read com.grove.test a
  [ "$status" -ne 0 ]
}

@test "non-numeric float is rejected" {
  printf 'com.grove.test f float abc\n' > "$BATS_TEST_TMPDIR/s.txt"
  run grove_defaults_check "$BATS_TEST_TMPDIR/s.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 1"* ]]
}

@test "live non-numeric value is a mismatch for float and int" {
  defaults write com.grove.test f -string abc
  defaults write com.grove.test i -string abc
  printf 'com.grove.test f float 0.0\ncom.grove.test i int 0\n' > "$BATS_TEST_TMPDIR/s.txt"
  run grove_defaults_check "$BATS_TEST_TMPDIR/s.txt"
  [ "$status" -eq 3 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "extra token after the value is rejected, trailing comment is fine" {
  printf 'com.grove.test k string hello world\n' > "$BATS_TEST_TMPDIR/s.txt"
  run grove_defaults_apply "$BATS_TEST_TMPDIR/s.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 1"* ]]
  printf 'com.grove.test k string hello # ok\n' > "$BATS_TEST_TMPDIR/s.txt"
  run grove_defaults_apply "$BATS_TEST_TMPDIR/s.txt"
  [ "$output" = "1" ]
}
