# shellcheck disable=SC2016,SC2030,SC2031,SC1090,SC1091,SC2154
load helpers

load_module() {
  local f
  for f in "$GROVE_ROOT"/lib/*.sh; do
    # shellcheck source=/dev/null
    . "$f"
  done
  MODULE_DIR="$GROVE_ROOT/modules/$1"
  # shellcheck source=/dev/null
  . "$MODULE_DIR/module.sh"
}

setup() {
  grove_test_setup
  export GROVE_FINDER_DOMAIN=com.grove.test
  export GROVE_GLOBAL_DOMAIN=com.grove.testglobal
  defaults delete com.grove.test 2>/dev/null || true
  defaults delete com.grove.testglobal 2>/dev/null || true
  stub killall 'echo "$@" >> "$BATS_TEST_TMPDIR/killall.log"'
}

teardown() {
  defaults delete com.grove.test 2>/dev/null || true
  defaults delete com.grove.testglobal 2>/dev/null || true
}

@test "settings.txt lists the 13 scalar settings" {
  n=$(grep -cv '^\s*\(#\|$\)' "$GROVE_ROOT/modules/80-macos-finder/settings.txt")
  [ "$n" -eq 13 ]
}

@test "finder needs work on an empty domain" {
  load_module 80-macos-finder
  run check
  [ "$status" -eq 3 ]
}

@test "finder is ok after apply" {
  load_module 80-macos-finder
  run apply
  [ "$status" -eq 0 ]
  run check
  [ "$status" -eq 0 ]
}

@test "finder needs work when only the tags are missing" {
  load_module 80-macos-finder
  apply >/dev/null
  defaults delete com.grove.test FavoriteTagNames
  run check
  [ "$status" -eq 3 ]
}

@test "finder needs work when the view block drifts" {
  load_module 80-macos-finder
  apply >/dev/null
  defaults delete com.grove.test StandardViewSettings
  run check
  [ "$status" -eq 3 ]
}

@test "apply restarts Finder only when something changed" {
  load_module 80-macos-finder
  run apply
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/killall.log")" = "Finder" ]
  rm "$BATS_TEST_TMPDIR/killall.log"
  run apply
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/killall.log" ]
}

@test "the view block round-trips" {
  load_module 80-macos-finder
  apply >/dev/null
  live=$(defaults export com.grove.test - | plutil -extract StandardViewSettings xml1 -o - - | plutil -convert json -o - -)
  want=$(plutil -convert json -o - "$GROVE_ROOT/modules/80-macos-finder/StandardViewSettings.plist")
  [ "$live" = "$want" ]
}

@test "favorite tags become one empty string" {
  load_module 80-macos-finder
  apply >/dev/null
  [ "$(defaults export com.grove.test - | plutil -extract FavoriteTagNames json -o - -)" = '[""]' ]
}

@test "apply prints the sidebar checklist" {
  load_module 80-macos-finder
  run apply
  [[ "$output" == *"Applications, Home, Developer, Documents, Downloads, iCloud Drive, Macintosh HD"* ]] || false
  [[ "$output" == *"Recents, Shared, AirDrop, Desktop"* ]] || false
  [[ "$output" == *"Sidebar"* ]] || false
}

@test "settings.txt stays literal and the real domains are untouched" {
  load_module 80-macos-finder
  apply >/dev/null
  grep -q '^com.apple.finder ' "$GROVE_ROOT/modules/80-macos-finder/settings.txt"
  grep -q '^NSGlobalDomain ' "$GROVE_ROOT/modules/80-macos-finder/settings.txt"
  [ "$(defaults export com.grove.testglobal - | plutil -extract AppleShowAllExtensions raw -o - -)" = true ]
}
