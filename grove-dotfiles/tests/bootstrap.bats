bats_require_minimum_version 1.5.0
load helpers

setup() {
  grove_test_setup
  export GROVE_POLL_SECONDS=0
  export GROVE_CLONE_DIR="$BATS_TEST_TMPDIR/dev/project-grove"
  export GROVE_REPO_URL="https://example.invalid/project-grove.git"
  export CALLS="$BATS_TEST_TMPDIR/calls"
  export GROVE_ARGS="$BATS_TEST_TMPDIR/grove-args"
  export GROVE_STDIN="$BATS_TEST_TMPDIR/grove-stdin"
  echo marker > "$GROVE_TTY"
  : > "$CALLS"
  stub xcode-select 'exit 0'
  stub git '
echo "git $*" >> "$CALLS"
case "$*" in
  clone\ *)
    mkdir -p "$3/.git" "$3/grove-dotfiles/bin"
    printf "#!/bin/bash\necho \"\$*\" > \"$GROVE_ARGS\"; cat > \"$GROVE_STDIN\"\n" > "$3/grove-dotfiles/bin/grove"
    chmod +x "$3/grove-dotfiles/bin/grove" ;;
  *" remote get-url"*) echo "$GROVE_REPO_URL" ;;
esac'
}

make_clone() {
  mkdir -p "$GROVE_CLONE_DIR/.git" "$GROVE_CLONE_DIR/grove-dotfiles/bin"
  printf '#!/bin/bash\necho "$*" > "%s"; cat > "%s"\n' "$GROVE_ARGS" "$GROVE_STDIN" > "$GROVE_CLONE_DIR/grove-dotfiles/bin/grove"
  chmod +x "$GROVE_CLONE_DIR/grove-dotfiles/bin/grove"
}

@test "bootstrap clones when the folder is missing" {
  run bash "$GROVE_ROOT/bootstrap.sh"
  [ "$status" -eq 0 ]
  grep -qF "git clone $GROVE_REPO_URL $GROVE_CLONE_DIR" "$CALLS"
}

@test "bootstrap reuses an existing clone" {
  make_clone
  run bash "$GROVE_ROOT/bootstrap.sh"
  [ "$status" -eq 0 ]
  run grep -q clone "$CALLS"
  [ "$status" -ne 0 ]
  [ -f "$GROVE_ARGS" ]
}

@test "bootstrap runs grove install" {
  run bash "$GROVE_ROOT/bootstrap.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$GROVE_ARGS")" = "install" ]
}

@test "bootstrap works when piped" {
  run bash -c "cat '$GROVE_ROOT/bootstrap.sh' | bash"
  [ "$status" -eq 0 ]
  [ "$(cat "$GROVE_ARGS")" = "install" ]
  [ "$(cat "$GROVE_STDIN")" = "marker" ]
}

@test "bootstrap accepts a repo with no origin" {
  make_clone
  run bash "$GROVE_ROOT/bootstrap.sh"
  [ "$status" -eq 0 ]
  [ -f "$GROVE_ARGS" ]
}

@test "bootstrap accepts a worktree whose .git is a file" {
  make_clone
  rmdir "$GROVE_CLONE_DIR/.git"
  echo "gitdir: elsewhere" > "$GROVE_CLONE_DIR/.git"
  run bash "$GROVE_ROOT/bootstrap.sh"
  [ "$status" -eq 0 ]
  [ -f "$GROVE_ARGS" ]
}

@test "bootstrap stops on an empty existing folder" {
  mkdir -p "$GROVE_CLONE_DIR"
  run bash "$GROVE_ROOT/bootstrap.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"has no .git"* ]] || false
}

@test "bootstrap stops when the folder exists but is not project-grove" {
  mkdir -p "$GROVE_CLONE_DIR/.git"
  echo keep > "$GROVE_CLONE_DIR/mine"
  run bash "$GROVE_ROOT/bootstrap.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"has no grove-dotfiles/bin/grove"* ]] || false
  [ "$(cat "$GROVE_CLONE_DIR/mine")" = "keep" ]
  [ ! -e "$GROVE_ARGS" ]
}

@test "bootstrap waits for the command line tools" {
  stub xcode-select '
if [ "$1" = "--install" ]; then echo started >> "$CALLS"; touch "$BATS_TEST_TMPDIR/clt"; exit 0; fi
[ -e "$BATS_TEST_TMPDIR/clt" ] && [ -e "$BATS_TEST_TMPDIR/clt2" ] && exit 0
[ -e "$BATS_TEST_TMPDIR/clt" ] && touch "$BATS_TEST_TMPDIR/clt2"
exit 2'
  run bash "$GROVE_ROOT/bootstrap.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Waiting for the Command Line Tools installer"* ]] || false
  grep -q started "$CALLS"
  [ "$(cat "$GROVE_ARGS")" = "install" ]
}

@test "a truncated script runs nothing" {
  head -n 20 "$GROVE_ROOT/bootstrap.sh" > "$BATS_TEST_TMPDIR/cut.sh"
  run bash "$BATS_TEST_TMPDIR/cut.sh"
  [ "$status" -ne 0 ]
  [ ! -s "$CALLS" ]
  [ ! -e "$GROVE_ARGS" ]
}
