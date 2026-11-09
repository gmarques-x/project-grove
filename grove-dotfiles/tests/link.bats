bats_require_minimum_version 1.5.0
load helpers

setup() {
  grove_test_setup
  # shellcheck source=/dev/null
  source "$GROVE_ROOT/lib/ui.sh"
  # shellcheck source=/dev/null
  source "$GROVE_ROOT/lib/link.sh"
  t="$BATS_TEST_TMPDIR/target"
  echo tgt > "$t"
}

@test "link creates a missing link and its parent folder" {
  run grove_link "$t" "$HOME/a/b/link"
  [ "$status" -eq 0 ]
  [ -L "$HOME/a/b/link" ]
  [ "$(readlink "$HOME/a/b/link")" = "$t" ]
}

@test "link leaves a correct link alone" {
  grove_link "$t" "$HOME/link"
  run grove_link "$t" "$HOME/link"
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/link")" = "$t" ]
  [ ! -e "$GROVE_STATE/backup" ] || [ -z "$(ls -A "$GROVE_STATE/backup")" ]
}

@test "link backs up a real file before linking" {
  echo x > "$HOME/.zshrc"
  run grove_link "$t" "$HOME/.zshrc"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.zshrc" ]
  [ "$(cat "$GROVE_STATE/backup/test/.zshrc")" = "x" ]
}

@test "link backs up a file whose path contains spaces" {
  mkdir -p "$HOME/My Folder"
  echo x > "$HOME/My Folder/file"
  run grove_link "$t" "$HOME/My Folder/file"
  [ "$status" -eq 0 ]
  [ -L "$HOME/My Folder/file" ]
  [ "$(cat "$GROVE_STATE/backup/test/My Folder/file")" = "x" ]
}

@test "link refuses a symlink pointing elsewhere" {
  ln -s /tmp/other "$HOME/link"
  run --separate-stderr grove_link "$t" "$HOME/link"
  [ "$status" -eq 1 ]
  [ "$(readlink "$HOME/link")" = "/tmp/other" ]
  [ ! -e "$GROVE_STATE/backup" ]
}

@test "link refuses a dangling symlink pointing elsewhere" {
  ln -s "$BATS_TEST_TMPDIR/nope" "$HOME/link"
  run grove_link "$t" "$HOME/link"
  [ "$status" -eq 1 ]
  [ "$(readlink "$HOME/link")" = "$BATS_TEST_TMPDIR/nope" ]
}

@test "link backs up a real directory before linking" {
  mkdir -p "$HOME/d"
  echo y > "$HOME/d/f"
  run grove_link "$t" "$HOME/d"
  [ "$status" -eq 0 ]
  [ -L "$HOME/d" ]
  [ "$(cat "$GROVE_STATE/backup/test/d/f")" = "y" ]
}

@test "link fails when the parent path is a file, changing nothing" {
  echo x > "$HOME/f"
  run grove_link "$t" "$HOME/f/link"
  [ "$status" -eq 1 ]
  [ "$(cat "$HOME/f")" = "x" ]
}

@test "link_check returns 0, 3, 3 and creates nothing" {
  ln -s "$t" "$HOME/ok"
  echo x > "$HOME/real"
  run grove_link_check "$t" "$HOME/ok"
  [ "$status" -eq 0 ]
  run grove_link_check "$t" "$HOME/missing/link"
  [ "$status" -eq 3 ]
  run grove_link_check "$t" "$HOME/real"
  [ "$status" -eq 3 ]
  [ ! -e "$HOME/missing" ]
  [ -f "$HOME/real" ] && [ ! -L "$HOME/real" ]
  [ ! -e "$GROVE_STATE" ]
}

@test "link_check returns 3 for a symlink pointing elsewhere" {
  ln -s /tmp/other "$HOME/link"
  run grove_link_check "$t" "$HOME/link"
  [ "$status" -eq 3 ]
  [ "$(readlink "$HOME/link")" = "/tmp/other" ]
}

@test "backup of a missing path is a no-op returning 0" {
  run grove_backup "$HOME/nothing"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$GROVE_STATE" ]
}

@test "backup moves a file and prints the new location" {
  echo x > "$HOME/f"
  run grove_backup "$HOME/f"
  [ "$status" -eq 0 ]
  [ "$output" = "$GROVE_STATE/backup/test/f" ]
  [ ! -e "$HOME/f" ]
  [ "$(cat "$output")" = "x" ]
}

@test "backup moves a symlink itself, not what it points to" {
  echo keep > "$BATS_TEST_TMPDIR/real"
  ln -s "$BATS_TEST_TMPDIR/real" "$HOME/l"
  run grove_backup "$HOME/l"
  [ "$status" -eq 0 ]
  [ ! -L "$HOME/l" ]
  [ -L "$GROVE_STATE/backup/test/l" ]
  [ "$(readlink "$GROVE_STATE/backup/test/l")" = "$BATS_TEST_TMPDIR/real" ]
  [ "$(cat "$BATS_TEST_TMPDIR/real")" = "keep" ]
}

@test "backup moves a dangling symlink" {
  ln -s "$BATS_TEST_TMPDIR/nope" "$HOME/l"
  run grove_backup "$HOME/l"
  [ "$status" -eq 0 ]
  [ -L "$GROVE_STATE/backup/test/l" ]
  [ ! -L "$HOME/l" ]
}

@test "backup moves a directory with its contents" {
  mkdir -p "$HOME/d/sub"
  echo z > "$HOME/d/sub/f"
  run grove_backup "$HOME/d"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/d" ]
  [ "$(cat "$GROVE_STATE/backup/test/d/sub/f")" = "z" ]
}

@test "backup never overwrites an earlier backup in the same run" {
  echo one > "$HOME/f"
  grove_backup "$HOME/f" >/dev/null
  echo two > "$HOME/f"
  run grove_backup "$HOME/f"
  [ "$status" -eq 0 ]
  [ "$output" = "$GROVE_STATE/backup/test/f.1" ]
  echo three > "$HOME/f"
  run grove_backup "$HOME/f"
  [ "$output" = "$GROVE_STATE/backup/test/f.2" ]
  [ "$(cat "$GROVE_STATE/backup/test/f")" = "one" ]
  [ "$(cat "$GROVE_STATE/backup/test/f.1")" = "two" ]
  [ "$(cat "$GROVE_STATE/backup/test/f.2")" = "three" ]
}

@test "backup of a path outside HOME uses its absolute path minus the slash" {
  mkdir -p "$BATS_TEST_TMPDIR/outside"
  echo o > "$BATS_TEST_TMPDIR/outside/x"
  run grove_backup "$BATS_TEST_TMPDIR/outside/x"
  [ "$status" -eq 0 ]
  [ "$output" = "$GROVE_STATE/backup/test${BATS_TEST_TMPDIR}/outside/x" ]
  [ "$(cat "$output")" = "o" ]
  [ ! -e "$BATS_TEST_TMPDIR/outside/x" ]
}

@test "backup refuses a relative path and HOME itself" {
  run grove_backup "relative/file"
  [ "$status" -eq 1 ]
  run grove_backup "$HOME"
  [ "$status" -eq 1 ]
  [ -d "$HOME" ]
}

@test "backup treats a sibling prefix of HOME as outside HOME" {
  mkdir -p "${HOME}-other"
  echo s > "${HOME}-other/f"
  run grove_backup "${HOME}-other/f"
  [ "$status" -eq 0 ]
  [ "$output" = "$GROVE_STATE/backup/test${HOME}-other/f" ]
}
