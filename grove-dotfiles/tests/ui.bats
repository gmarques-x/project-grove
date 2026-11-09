bats_require_minimum_version 1.5.0
load helpers

setup() {
  grove_test_setup
  # shellcheck source=/dev/null
  source "$GROVE_ROOT/lib/ui.sh"
}

@test "status lines carry their label" {
  run grove_ok "fonts"
  [[ "$output" == *ok* && "$output" == *fonts* ]]
  run grove_work "fonts"
  [[ "$output" == *"needs work"* && "$output" == *fonts* ]]
  run grove_you "fonts"
  [[ "$output" == *"needs you"* && "$output" == *fonts* ]]
  run --separate-stderr grove_fail "boom"
  [ -z "$output" ]
  [[ "$stderr" == *boom* ]]
}

@test "no color codes when NO_COLOR is set" {
  run grove_ok "fonts"
  [[ "$output" != *$'\033['* ]]
  run grove_step "Title"
  [[ "$output" != *$'\033['* ]]
}

@test "ask returns the default on an empty reply" {
  printf '\n' > "$GROVE_TTY"
  run --separate-stderr grove_ask "Email" "a@b.c"
  [ "$output" = "a@b.c" ]
}

@test "ask reads from GROVE_TTY, not stdin" {
  printf 'typed\n' > "$GROVE_TTY"
  run bash -c 'source "$GROVE_ROOT/lib/ui.sh"; echo piped | grove_ask "Q" "d" 2>/dev/null'
  [ "$output" = "typed" ]
}

@test "info is silent when quiet" {
  GROVE_QUIET=1 run grove_info x
  [ -z "$output" ]
}
