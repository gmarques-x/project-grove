load helpers

setup() { grove_test_setup; }

@test "grove_copy_tracked_config copies tracked files and skips ignored ones" {
  local r="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$r/config/sub"
  git init -q "$r"
  printf '/private\n' > "$r/config/.gitignore"
  echo a > "$r/config/a"; echo b > "$r/config/sub/b"; echo secret > "$r/config/private"
  git -C "$r" -c user.name=t -c user.email=t@e.x add -A
  grove_copy_tracked_config "$BATS_TEST_TMPDIR/out" "$r"
  [ "$(cat "$BATS_TEST_TMPDIR/out/a")" = a ]
  [ "$(cat "$BATS_TEST_TMPDIR/out/sub/b")" = b ]
  [ -f "$BATS_TEST_TMPDIR/out/.gitignore" ]
  [ ! -e "$BATS_TEST_TMPDIR/out/private" ]
}
