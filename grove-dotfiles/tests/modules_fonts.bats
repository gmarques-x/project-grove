#!/usr/bin/env bats
# shellcheck disable=SC2016,SC1090,SC1091
# 30-fonts: the real install logic, with curl and osascript stubbed and a temp HOME.

load helpers

setup() {
  grove_test_setup
  for lib in "$GROVE_ROOT"/lib/*.sh; do . "$lib"; done
  export MODULE_DIR="$GROVE_ROOT/modules/30-fonts"
  . "$MODULE_DIR/module.sh"
  export GROVE_FONTS_CACHE="$BATS_TEST_TMPDIR/cache"
  export GROVE_FONTS_LIST="$BATS_TEST_TMPDIR/fonts.txt"
  export GROVE_FONTS_LOCAL="$BATS_TEST_TMPDIR/local"
  REMOTE="$BATS_TEST_TMPDIR/remote"
  mkdir -p "$REMOTE"
  # curl stub: serves $REMOTE/<basename of url>; exits 22 (HTTP error) when absent.
  stub curl 'out=""; url=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift ;; -z) shift ;; -*) ;; *) url="$1" ;; esac; shift; done
src="'"$REMOTE"'/$(basename "$url")"
[ -f "$src" ] || exit 22
cp "$src" "$out"'
  # osascript stub: records the files it was given; reports $BATS_TEST_TMPDIR/missing (default 0).
  stub osascript 'shift 2; echo "$@" >> "'"$BATS_TEST_TMPDIR"'/registered"
n=$(cat "'"$BATS_TEST_TMPDIR"'/missing" 2>/dev/null || echo 0)
echo "checked=$# missing=$n"'
  printf 'fake font A' > "$REMOTE/Alpha.ttf"
  SHA_A="$(shasum -a 256 "$REMOTE/Alpha.ttf" | awk '{print $1}')"
}

@test "fonts check reports 3 for a missing font and installs nothing" {
  echo "Alpha|https://example.com/Alpha.ttf|$SHA_A|" > "$GROVE_FONTS_LIST"
  run check
  [ "$status" -eq 3 ]
  [ ! -e "$HOME/Library/Fonts/Alpha.ttf" ]
}

@test "fonts apply installs and registers, then check is ok" {
  echo "Alpha|https://example.com/Alpha.ttf|$SHA_A|" > "$GROVE_FONTS_LIST"
  run apply
  [ "$status" -eq 0 ]
  cmp -s "$REMOTE/Alpha.ttf" "$HOME/Library/Fonts/Alpha.ttf"
  grep -q "$HOME/Library/Fonts/Alpha.ttf" "$BATS_TEST_TMPDIR/registered"
  run check
  [ "$status" -eq 0 ]
}

@test "fonts installs only the zip files that match the pattern" {
  mkdir -p "$BATS_TEST_TMPDIR/z/fonts/ttf" "$BATS_TEST_TMPDIR/z/fonts/variable"
  printf 'b' > "$BATS_TEST_TMPDIR/z/fonts/ttf/Beta.ttf"
  printf 'v' > "$BATS_TEST_TMPDIR/z/fonts/variable/BetaVar.ttf"
  printf 'r' > "$BATS_TEST_TMPDIR/z/fonts/ttf/README.txt"
  (cd "$BATS_TEST_TMPDIR/z" && zip -qr "$REMOTE/Beta.zip" fonts)
  sha="$(shasum -a 256 "$REMOTE/Beta.zip" | awk '{print $1}')"
  echo "Beta|https://example.com/Beta.zip|$sha|fonts/ttf/*.ttf" > "$GROVE_FONTS_LIST"
  run apply
  [ "$status" -eq 0 ]
  [ -f "$HOME/Library/Fonts/Beta.ttf" ]
  [ ! -e "$HOME/Library/Fonts/BetaVar.ttf" ]
  [ ! -e "$HOME/Library/Fonts/README.txt" ]
}

@test "fonts refuses a download with the wrong checksum and drops the cached copy" {
  echo "Alpha|https://example.com/Alpha.ttf|0000|" > "$GROVE_FONTS_LIST"
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"checksum mismatch"* ]] || false
  [ ! -e "$HOME/Library/Fonts/Alpha.ttf" ]
  [ -z "$(ls -A "$GROVE_FONTS_CACHE")" ]
}

@test "fonts fails when a download fails" {
  echo "Gone|https://example.com/Gone.ttf||" > "$GROVE_FONTS_LIST"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"download failed"* ]] || false
}

@test "fonts installs files from the local folder" {
  : > "$GROVE_FONTS_LIST"
  mkdir -p "$GROVE_FONTS_LOCAL/sub"
  printf 'mine' > "$GROVE_FONTS_LOCAL/sub/Mine.otf"
  printf 'notes' > "$GROVE_FONTS_LOCAL/notes.txt"
  run check
  [ "$status" -eq 3 ]
  run apply
  [ "$status" -eq 0 ]
  [ -f "$HOME/Library/Fonts/Mine.otf" ]
  [ ! -e "$HOME/Library/Fonts/notes.txt" ]
}

@test "fonts check reports 3 when installed fonts aren't active" {
  echo "Alpha|https://example.com/Alpha.ttf|$SHA_A|" > "$GROVE_FONTS_LIST"
  run apply
  [ "$status" -eq 0 ]
  echo 1 > "$BATS_TEST_TMPDIR/missing"
  run check
  [ "$status" -eq 3 ]
}

@test "fonts fails when the font list is missing" {
  run check
  [ "$status" -eq 1 ]
}

@test "the shipped fonts.txt has four fields and a supported download type per entry" {
  local n=0 line name url
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    n=$((n + 1))
    [ "$(printf '%s' "$line" | tr -cd '|' | wc -c | tr -d ' ')" -eq 3 ]
    IFS='|' read -r name url _ <<< "$line"
    [ -n "$name" ]
    [[ "$url" =~ \.(zip|dmg|pkg|ttf|otf)$ ]] || false
  done < "$GROVE_ROOT/modules/30-fonts/fonts.txt"
  [ "$n" -ge 2 ]
}
