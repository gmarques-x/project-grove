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

stub_git() {
  stub git 'case "$*" in
  "config --global user.name") echo "gmarques-x" ;;
  "config --global user.email") echo "g@x.y" ;;
  *) exit 1 ;;
esac'
}

@test "ensure asks with defaults from git config" {
  stub_git
  printf '\n\n\n' > "$GROVE_TTY"
  run grove_local_ensure
  [ "$status" -eq 0 ]
  grep -qx 'GROVE_NAME=gmarques-x' "$GROVE_LOCAL"
  grep -qx 'GROVE_EMAIL=g@x.y' "$GROVE_LOCAL"
  grep -qx 'GROVE_GITHUB_USER=gmarques-x' "$GROVE_LOCAL"
}

@test "ensure exports the three variables" {
  stub_git
  printf '\n\n\n' > "$GROVE_TTY"
  grove_local_ensure >/dev/null 2>&1
  [ "$GROVE_NAME" = "gmarques-x" ]
  [ "$GROVE_EMAIL" = "g@x.y" ]
  [ "$GROVE_GITHUB_USER" = "gmarques-x" ]
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
  stub_git
  mkdir -p "$(dirname "$GROVE_LOCAL")"
  printf 'GROVE_NAME=Ann\n' > "$GROVE_LOCAL"
  # grove_ask reopens the tty file each time, so every answer is its first line.
  printf 'x@y.z\n' > "$GROVE_TTY"
  grove_local_ensure >/dev/null 2>&1
  [ "$GROVE_NAME" = "Ann" ]
  [ "$GROVE_EMAIL" = "x@y.z" ]
}

@test "ensure with GROVE_YES=1 does not prompt and fills defaults" {
  stub_git
  export GROVE_YES=1
  export GROVE_TTY=/dev/null
  run grove_local_ensure
  [ "$status" -eq 0 ]
  grep -qx 'GROVE_NAME=gmarques-x' "$GROVE_LOCAL"
  grep -qx 'GROVE_EMAIL=g@x.y' "$GROVE_LOCAL"
  grep -qx 'GROVE_GITHUB_USER=gmarques-x' "$GROVE_LOCAL"
}

@test "ensure with nothing in git config defaults to empty" {
  stub git 'exit 1'
  export GROVE_YES=1
  grove_local_ensure >/dev/null 2>&1
  [ -z "$GROVE_NAME" ]
  [ -z "$GROVE_EMAIL" ]
  [ -f "$GROVE_LOCAL" ]
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
  printf '\n\n\n' > "$GROVE_TTY"
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
