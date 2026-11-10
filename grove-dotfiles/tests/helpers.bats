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

@test "grove_test_setup's GROVE_CONFIG is a temp copy, never the live config" {
  local live
  live="$(cd "$GROVE_ROOT/config" && pwd -P)"
  [[ "$GROVE_CONFIG" == "$BATS_TEST_TMPDIR"/* ]] || false
  [ "$(cd "$GROVE_CONFIG" && pwd -P)" != "$live" ]
  # The tracked files and the generated ones are there for tests to read.
  [ -f "$GROVE_CONFIG/vscode/grove-icons/package.json" ]
  [ -f "$GROVE_CONFIG/ghostty/config" ]
}

@test "05-config's apply with grove_test_setup's defaults leaves the live config alone" {
  local live f before after
  live="$(cd "$GROVE_ROOT/config" && pwd -P)"
  [ "$(cd "$GROVE_CONFIG" && pwd -P)" != "$live" ]   # stop before apply if not
  before="$(cd "$live" && find . -type f -name '*.tmpl' | while IFS= read -r f; do
    stat -f '%m %i' "${f%.tmpl}" 2>/dev/null; done)"
  for f in "$GROVE_ROOT"/lib/*.sh; do . "$f"; done
  MODULE_DIR="$GROVE_ROOT/modules/05-config"
  . "$MODULE_DIR/module.sh"
  run apply
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.config")" = "$GROVE_CONFIG" ]
  after="$(cd "$live" && find . -type f -name '*.tmpl' | while IFS= read -r f; do
    stat -f '%m %i' "${f%.tmpl}" 2>/dev/null; done)"
  [ "$before" = "$after" ]
}
