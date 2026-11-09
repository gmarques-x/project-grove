bats_require_minimum_version 1.5.0
load helpers

setup() {
  grove_test_setup
  # shellcheck source=/dev/null
  source "$GROVE_ROOT/lib/ui.sh"
}

@test "status lines carry their label" {
  run grove_ok "fonts"
  [[ "$output" == *ok* && "$output" == *fonts* ]] || false
  run grove_work "fonts"
  [[ "$output" == *"needs work"* && "$output" == *fonts* ]] || false
  run grove_you "fonts"
  [[ "$output" == *"needs you"* && "$output" == *fonts* ]] || false
  run --separate-stderr grove_fail "boom"
  [ -z "$output" ]
  [[ "$stderr" == *boom* ]] || false
}

@test "no color codes when NO_COLOR is set" {
  run grove_ok "fonts"
  [[ "$output" != *$'\033['* ]] || false
  run grove_step "Title"
  [[ "$output" != *$'\033['* ]] || false
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

# Real pseudo-terminal via macOS script(1): stdout is a tty inside the command.
on_tty() { script -q /dev/null /bin/bash -c "$1" < /dev/null; }

@test "color is emitted on a real tty" {
  unset NO_COLOR
  run on_tty 'source "$GROVE_ROOT/lib/ui.sh"; grove_ok fonts; grove_step S; grove_info i'
  [[ "$output" == *$'\033[38;2;167;192;128m'*fonts* ]] || false
  [[ "$output" == *$'\033[38;2;133;146;137m'* ]] || false
}

@test "NO_COLOR suppresses color on a real tty" {
  run on_tty 'source "$GROVE_ROOT/lib/ui.sh"; grove_ok fonts'
  [[ "$output" == *fonts* ]] || false
  [[ "$output" != *$'\033['* ]] || false
}

@test "GROVE_FORCE_COLOR forces color per fd and NO_COLOR beats it" {
  source "$GROVE_ROOT/lib/ui.sh"
  unset NO_COLOR
  GROVE_FORCE_COLOR=1 run grove_ok hi
  [[ "$output" == *$'\033['* ]] || false
  GROVE_FORCE_COLOR=1 run grove_fail hi
  [[ "$output" != *$'\033['* ]] || false
  GROVE_FORCE_COLOR=1,2 run grove_fail hi
  [[ "$output" == *$'\033['* ]] || false
  NO_COLOR=1 GROVE_FORCE_COLOR=1,2 run grove_ok hi
  [[ "$output" != *$'\033['* ]] || false
}

@test "ask shows no brackets when there is no default" {
  printf 'x\n' > "$GROVE_TTY"
  run grove_ask "Your name" ""
  [ "$output" = "Your name: x" ]
}
