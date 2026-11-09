load helpers

setup() {
  grove_test_setup
  # Never read the developer's real git config (Ruling R7).
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  : > "$GIT_CONFIG_GLOBAL"
  unset XDG_CONFIG_HOME
  unset GROVE_NAME GROVE_EMAIL GROVE_GITHUB_USER GROVE_YES
  source "$GROVE_ROOT/lib/ui.sh"
  source "$GROVE_ROOT/lib/local.sh"
}

stub_git() { # records any call, so tests can prove git config is never read
  stub git 'echo "git $*" >> "'"$BATS_TEST_TMPDIR"'/git.log"; echo "from-git"'
}

@test "ensure asks without proposing anything and never reads git config" {
  stub_git
  printf 'Ann\n' > "$GROVE_TTY"
  run grove_local_ensure
  [ "$status" -eq 0 ]
  [[ "$output" == *"Your name: "* ]] || false
  [[ "$output" != *"["* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/git.log" ]
  grep -qx 'GROVE_NAME=Ann' "$GROVE_LOCAL"
}

@test "ensure exports the three variables" {
  printf 'v\n' > "$GROVE_TTY"
  grove_local_ensure >/dev/null 2>&1
  [ "$GROVE_NAME" = "v" ]
  [ "$GROVE_EMAIL" = "v" ]
  [ "$GROVE_GITHUB_USER" = "v" ]
}

@test "ensure keeps existing values without asking" {
  mkdir -p "$(dirname "$GROVE_LOCAL")"
  printf 'GROVE_NAME=Ann\nGROVE_EMAIL=a@b.c\nGROVE_GITHUB_USER=ann\n' > "$GROVE_LOCAL"
  export GROVE_TTY=/dev/null
  grove_local_ensure >/dev/null 2>&1
  [ "$GROVE_NAME" = "Ann" ]
  [ "$GROVE_EMAIL" = "a@b.c" ]
  [ "$GROVE_GITHUB_USER" = "ann" ]
  grove_local_load
}

@test "ensure asks only for missing values" {
  mkdir -p "$(dirname "$GROVE_LOCAL")"
  printf 'GROVE_NAME=Ann\n' > "$GROVE_LOCAL"
  # grove_ask reopens the tty file each time, so every answer is its first line.
  printf 'x@y.z\n' > "$GROVE_TTY"
  run grove_local_ensure
  [[ "$output" != *"Your name"* ]] || false
  grove_local_load
  [ "$GROVE_NAME" = "Ann" ]
  [ "$GROVE_EMAIL" = "x@y.z" ]
}

@test "ensure asks an empty answer again, three times, then saves nothing" {
  printf '\n' > "$GROVE_TTY"
  run grove_local_ensure
  [ "$status" -eq 0 ]
  [ "$(grep -o 'Your name: ' <<< "$output" | wc -l | tr -d ' ')" -eq 3 ]
  [ ! -e "$GROVE_LOCAL" ]
}

@test "ensure with GROVE_YES=1 does not prompt and saves nothing" {
  stub_git
  export GROVE_YES=1
  export GROVE_TTY=/dev/null
  run grove_local_ensure
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$GROVE_LOCAL" ]
  [ ! -e "$BATS_TEST_TMPDIR/git.log" ]
}

@test "load returns 3 when the file is missing or incomplete" {
  run grove_local_load
  [ "$status" -eq 3 ]
  mkdir -p "$(dirname "$GROVE_LOCAL")"
  printf 'GROVE_NAME=Ann\n' > "$GROVE_LOCAL"
  run grove_local_load
  [ "$status" -eq 3 ]
}

@test "local file is private" {
  stub_git
  printf 'v\n' > "$GROVE_TTY"
  grove_local_ensure >/dev/null 2>&1
  [ "$(stat -f %Lp "$GROVE_LOCAL")" = "600" ]
}

@test "write creates the parent folder and leaves no temp files" {
  GROVE_NAME=a GROVE_EMAIL=b GROVE_GITHUB_USER=c
  grove_local_write
  [ -f "$GROVE_LOCAL" ]
  [ "$(ls "$(dirname "$GROVE_LOCAL")" | wc -l | tr -d ' ')" = "1" ]
}

@test "values with quotes and spaces survive a round trip" {
  GROVE_NAME='Gus "G" Marques' GROVE_EMAIL='g@x.y' GROVE_GITHUB_USER='gus g'
  grove_local_write
  unset GROVE_NAME GROVE_EMAIL GROVE_GITHUB_USER
  grove_local_load
  [ "$GROVE_NAME" = 'Gus "G" Marques' ]
  [ "$GROVE_GITHUB_USER" = 'gus g' ]
}

@test "ensure does not rewrite a complete file" {
  mkdir -p "$(dirname "$GROVE_LOCAL")"
  printf 'GROVE_NAME=a\nGROVE_EMAIL=b\nGROVE_GITHUB_USER=c\nEXTRA=1\n' > "$GROVE_LOCAL"
  local before; before="$(ls -i "$GROVE_LOCAL")"
  run grove_local_ensure
  [ "$status" -eq 0 ]
  [ "$before" = "$(ls -i "$GROVE_LOCAL")" ]
  grep -qx 'EXTRA=1' "$GROVE_LOCAL"
}
