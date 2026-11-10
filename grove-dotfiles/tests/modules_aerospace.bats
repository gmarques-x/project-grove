# shellcheck disable=SC2016,SC1090,SC1091,SC2154
# 98-aerospace against fake aerospace, borders, defaults, open and ps.
load helpers

AS_MODULE=98-aerospace

load_module() {
  local f
  for f in "$GROVE_ROOT"/lib/*.sh; do . "$f"; done
  MODULE_DIR="$GROVE_ROOT/modules/$AS_MODULE"
  . "$MODULE_DIR/module.sh"
}

# The fakes log to $CALLS. aerospace fails while $FAKE_AS_FAILS (a count in a
# file) is above zero, counting down, or always when FAKE_AS_RC=1.
setup() {
  grove_test_setup
  export CALLS="$BATS_TEST_TMPDIR/calls"
  : > "$CALLS"
  echo 0 > "$BATS_TEST_TMPDIR/as-fails"
  stub aerospace '
echo "aerospace $*" >> "$CALLS"
[ "${FAKE_AS_RC:-0}" = 0 ] || exit 2
n=$(cat "$BATS_TEST_TMPDIR/as-fails")
if [ "$n" -gt 0 ]; then echo $((n - 1)) > "$BATS_TEST_TMPDIR/as-fails"; exit 2; fi
echo 1'
  stub borders 'echo "borders $*" >> "$CALLS"'
  stub defaults '
echo "defaults $*" >> "$CALLS"
[ "$1" = read ] && echo "${FAKE_SPANS:-1}"
exit 0'
  stub open 'echo "open $*" >> "$CALLS"'
  stub fakeps 'printf "%s\n" "  1 /usr/bin/zsh" ${FAKE_PS:+"  2 $FAKE_PS"}'
  export GROVE_PS=fakeps GROVE_POLL_SECONDS=0 GROVE_START_SECONDS=0
  export FAKE_PS=/Applications/AeroSpace.app/Contents/MacOS/AeroSpace
  export GROVE_BREW="$BATS_TEST_TMPDIR/nobrew/brew"
  load_module
}

@test "aerospace: about" {
  [ "$(about)" = "AeroSpace tiles the desktop" ]
}

@test "aerospace: check is ok when installed, Spaces shared, running and allowed" {
  run check
  [ "$status" -eq 0 ]
  run grep -E '^(defaults write|open)' "$CALLS"
  [ "$status" -ne 0 ]
}

@test "aerospace: check needs work without aerospace" {
  export GROVE_AEROSPACE="$BATS_TEST_TMPDIR/missing/aerospace"
  run check
  [ "$status" -eq 3 ]
}

@test "aerospace: check needs work without borders" {
  export GROVE_BORDERS="$BATS_TEST_TMPDIR/missing/borders"
  run check
  [ "$status" -eq 3 ]
}

@test "aerospace: check finds aerospace and borders next to brew when PATH lacks them" {
  mkdir -p "$BATS_TEST_TMPDIR/nobrew"
  mv "$BATS_TEST_TMPDIR/stubs/aerospace" "$BATS_TEST_TMPDIR/stubs/borders" "$BATS_TEST_TMPDIR/nobrew/"
  # Without Homebrew on PATH, so the real aerospace can't be found instead.
  export PATH="$BATS_TEST_TMPDIR/stubs:/usr/bin:/bin"
  run command -v aerospace
  [ "$status" -ne 0 ]
  run check
  [ "$status" -eq 0 ]
}

@test "aerospace: check needs work while Displays have separate Spaces" {
  export FAKE_SPANS=0
  run check
  [ "$status" -eq 3 ]
}

@test "aerospace: check needs work when AeroSpace isn't running" {
  export FAKE_PS=/usr/bin/vim
  run check
  [ "$status" -eq 3 ]
}

@test "aerospace: check needs you without Accessibility" {
  export FAKE_AS_RC=1
  run check
  [ "$status" -eq 4 ]
  run grep -E '^(defaults write|open)' "$CALLS"
  [ "$status" -ne 0 ]
}

@test "aerospace: apply turns off separate Spaces and says to log out" {
  export FAKE_SPANS=0
  run apply
  [ "$status" -eq 0 ]
  grep -qx 'defaults write com.apple.spaces spans-displays -bool true' "$CALLS"
  [[ "$output" == *"log out once to finish the Spaces change"* ]] || false
}

@test "aerospace: apply leaves the Spaces setting alone when it's set" {
  run apply
  [ "$status" -eq 0 ]
  run grep -q '^defaults write' "$CALLS"
  [ "$status" -ne 0 ]
}

@test "aerospace: apply starts AeroSpace and waits for it to answer" {
  export FAKE_PS=/usr/bin/vim
  echo 2 > "$BATS_TEST_TMPDIR/as-fails"
  run apply
  [ "$status" -eq 0 ]
  grep -qx 'open -a AeroSpace' "$CALLS"
  run grep -q 'Privacy_Accessibility' "$CALLS"
  [ "$status" -ne 0 ]
}

@test "aerospace: apply opens the Accessibility page and waits for the grant" {
  echo 12 > "$BATS_TEST_TMPDIR/as-fails"
  run apply
  [ "$status" -eq 0 ]
  grep -qx 'open x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility' "$CALLS"
  [[ "$output" == *"allow AeroSpace under Accessibility"* ]] || false
  [ "$(cat "$BATS_TEST_TMPDIR/as-fails")" = 0 ]
}

@test "aerospace: apply fails without aerospace" {
  export GROVE_AEROSPACE="$BATS_TEST_TMPDIR/missing/aerospace"
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"run grove install homebrew"* ]] || false
}

@test "aerospace: the README lists the module" {
  grep -qF '| `98-aerospace` | AeroSpace tiles the desktop: pinned workspaces, Option shortcuts and JankyBorders in the scheme'"'"'s colours (Accessibility is a manual step) |' "$GROVE_ROOT/README.md"
}
