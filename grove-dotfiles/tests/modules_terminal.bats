#!/usr/bin/env bats
# 90-terminal: Ghostty checks and the Dock swap, against a throwaway Dock domain.
# shellcheck disable=SC2016,SC1090,SC1091

load helpers

PB=/usr/libexec/PlistBuddy

setup() {
  grove_test_setup
  for f in "$GROVE_ROOT"/lib/*.sh; do . "$f"; done
  export MODULE_DIR="$GROVE_ROOT/modules/90-terminal"
  . "$MODULE_DIR/module.sh"
  export GROVE_DOCK_DOMAIN=com.grove.testdock
  /usr/bin/defaults delete "$GROVE_DOCK_DOMAIN" 2>/dev/null || true
  export GROVE_GHOSTTY_APP="$BATS_TEST_TMPDIR/Ghostty.app"
  mkdir -p "$GROVE_GHOSTTY_APP"
  export GROVE_GHOSTTY="$BATS_TEST_TMPDIR/stubs/ghostty-cli"
  stub ghostty-cli 'cat "'"$BATS_TEST_TMPDIR"'/ghostty-msg" 2>/dev/null; exit "$(cat "'"$BATS_TEST_TMPDIR"'/ghostty-rc" 2>/dev/null || echo 0)"'
  stub macchina 'exit 0'
  stub killall 'echo "$@" >> "'"$BATS_TEST_TMPDIR"'/killall.log"'
  export GROVE_BREW="$BATS_TEST_TMPDIR/nobrew/bin/brew"   # no macchina next to it
}

teardown() { /usr/bin/defaults delete "$GROVE_DOCK_DOMAIN" 2>/dev/null || true; }

# tile LABEL URL BUNDLE [book]: one persistent-apps entry as plist XML.
tile() {
  printf '<dict><key>tile-data</key><dict>'
  [ "${4:-}" = book ] && printf '<key>book</key><data>Ym9vaw==</data>'
  printf '<key>bundle-identifier</key><string>%s</string>' "$3"
  printf '<key>file-data</key><dict><key>_CFURLString</key><string>%s</string><key>_CFURLStringType</key><integer>15</integer></dict>' "$2"
  printf '<key>file-label</key><string>%s</string><key>file-type</key><integer>41</integer></dict>' "$1"
  printf '<key>tile-type</key><string>file-tile</string></dict>'
}
SAFARI() { tile Safari file:///Applications/Safari.app/ com.apple.Safari; }
TERMINAL() { tile "${1:-Terminal}" file:///System/Applications/Utilities/Terminal.app/ com.apple.Terminal book; }
GHOSTTY() { tile Ghostty file:///Applications/Ghostty.app/ com.mitchellh.ghostty; }
SETTINGS() { tile "System Settings" "file:///System/Applications/System%20Settings.app/" com.apple.systempreferences; }

# seed_dock TILE...: replace the test domain with these persistent-apps.
seed_dock() {
  local f="$BATS_TEST_TMPDIR/seed.plist"
  { printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>persistent-apps</key><array>'
    printf '%s' "$@"
    printf '</array><key>orientation</key><string>right</string></dict></plist>\n'; } > "$f"
  /usr/bin/defaults import "$GROVE_DOCK_DOMAIN" "$f"
}

# dock_field FIELD: that tile-data field for every tile, space-separated.
dock_field() {
  local f="$BATS_TEST_TMPDIR/now.plist" i=0 out="" v
  /usr/bin/defaults export "$GROVE_DOCK_DOMAIN" "$f"
  while v="$($PB -c "Print :persistent-apps:$i:tile-data:$1" "$f" 2>/dev/null)"; do
    out="$out${out:+|}$v"; i=$((i + 1))
  done
  printf '%s\n' "$out"
}

@test "check is ok on a finished setup" {
  seed_dock "$(SAFARI)" "$(GHOSTTY)" "$(SETTINGS)"
  run check
  [ "$status" -eq 0 ]
}

@test "check needs work when Ghostty is missing" {
  seed_dock "$(GHOSTTY)"
  rmdir "$GROVE_GHOSTTY_APP"
  run check
  [ "$status" -eq 3 ]
}

@test "check needs work when macchina is missing" {
  seed_dock "$(GHOSTTY)"
  rm "$BATS_TEST_TMPDIR/stubs/macchina"
  PATH="$BATS_TEST_TMPDIR/stubs:/usr/bin:/bin" run check
  [ "$status" -eq 3 ]
}

@test "check needs work when the Dock has Terminal" {
  seed_dock "$(SAFARI)" "$(TERMINAL)"
  run check
  [ "$status" -eq 3 ]
}

@test "check needs work when Ghostty isn't in the Dock" {
  seed_dock "$(SAFARI)"
  run check
  [ "$status" -eq 3 ]
}

@test "check fails with Ghostty's message when the config is invalid" {
  seed_dock "$(GHOSTTY)"
  echo 1 > "$BATS_TEST_TMPDIR/ghostty-rc"
  echo "bad key" > "$BATS_TEST_TMPDIR/ghostty-msg"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"bad key"* ]] || false
}

@test "apply swaps Terminal for Ghostty in the same slot" {
  seed_dock "$(SAFARI)" "$(TERMINAL)" "$(SETTINGS)"
  run apply
  [ "$status" -eq 0 ]
  [ "$(dock_field file-label)" = "Safari|Ghostty|System Settings" ]
  [ "$(/usr/bin/defaults read "$GROVE_DOCK_DOMAIN" orientation)" = right ]
  run check
  [ "$status" -eq 0 ]
}

@test "swap removes the old bookmark and sets Ghostty's bundle id" {
  seed_dock "$(SAFARI)" "$(TERMINAL)"
  apply >/dev/null
  [ "$(dock_field bundle-identifier)" = "com.apple.Safari|com.mitchellh.ghostty" ]
  [ "$(dock_field file-data:_CFURLString)" = "file:///Applications/Safari.app/|file:///Applications/Ghostty.app/" ]
  [ "$(dock_field file-type)" = "41|41" ]
  local f="$BATS_TEST_TMPDIR/after.plist"
  /usr/bin/defaults export "$GROVE_DOCK_DOMAIN" "$f"
  run $PB -c "Print :persistent-apps:1:tile-data:book" "$f"
  [ "$status" -ne 0 ]
}

@test "swap finds Terminal by its path even when the label differs" {
  seed_dock "$(SAFARI)" "$(TERMINAL "Terminal (old)")"
  apply >/dev/null
  [ "$(dock_field file-label)" = "Safari|Ghostty" ]
}

@test "apply puts Ghostty first when Terminal is absent" {
  seed_dock "$(SAFARI)" "$(SETTINGS)"
  apply >/dev/null
  [ "$(dock_field file-label)" = "Ghostty|Safari|System Settings" ]
  [ "$(dock_field bundle-identifier)" = "com.mitchellh.ghostty|com.apple.Safari|com.apple.systempreferences" ]
}

@test "apply removes Terminal when Ghostty is already in the Dock" {
  seed_dock "$(GHOSTTY)" "$(SAFARI)" "$(TERMINAL)"
  apply >/dev/null
  [ "$(dock_field file-label)" = "Ghostty|Safari" ]
}

@test "apply twice changes nothing and doesn't restart the Dock" {
  seed_dock "$(SAFARI)" "$(TERMINAL)"
  apply >/dev/null
  apply >/dev/null
  [ "$(wc -l < "$BATS_TEST_TMPDIR/killall.log" | tr -d ' ')" -eq 1 ]
  [ "$(cat "$BATS_TEST_TMPDIR/killall.log")" = Dock ]
}

@test "apply leaves the Dock untouched when the import fails" {
  seed_dock "$(SAFARI)" "$(TERMINAL)"
  stub defaults '[ "$1" = import ] && exit 1; exec /usr/bin/defaults "$@"'
  run apply
  [ "$status" -eq 1 ]
  [ "$(dock_field file-label)" = "Safari|Terminal" ]
  [ ! -e "$BATS_TEST_TMPDIR/killall.log" ]
}

@test "a Ghostty config in Application Support is backed up" {
  seed_dock "$(GHOSTTY)"
  local extra="$HOME/Library/Application Support/com.mitchellh.ghostty/config"
  mkdir -p "$(dirname "$extra")"
  echo "font-size = 20" > "$extra"
  run check
  [ "$status" -eq 3 ]
  run apply
  [ "$status" -eq 0 ]
  [ ! -e "$extra" ]
  [ "$(cat "$GROVE_STATE/backup/test/Library/Application Support/com.mitchellh.ghostty/config")" = "font-size = 20" ]
  run check
  [ "$status" -eq 0 ]
}

@test "an empty Ghostty config in Application Support is left alone" {
  seed_dock "$(GHOSTTY)"
  local extra="$HOME/Library/Application Support/com.mitchellh.ghostty/config"
  mkdir -p "$(dirname "$extra")"
  : > "$extra"
  run check
  [ "$status" -eq 0 ]
}

@test "apply fails without Ghostty or macchina and points to grove install homebrew" {
  rmdir "$GROVE_GHOSTTY_APP"
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"grove install homebrew"* ]] || false
}

@test "apply prints the Accessibility step, also with GROVE_QUIET=1" {
  seed_dock "$(GHOSTTY)"
  GROVE_QUIET=1 run apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"Privacy & Security › Accessibility"* ]] || false
}

@test "about names the module" {
  [ "$(about)" = "Ghostty, the prompt and macchina" ]
}

@test "check finds macchina next to brew when Homebrew isn't on PATH yet" {
  seed_dock "$(GHOSTTY)"
  rm "$BATS_TEST_TMPDIR/stubs/macchina"
  mkdir -p "$BATS_TEST_TMPDIR/brew/bin"
  printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/brew/bin/macchina"; chmod +x "$BATS_TEST_TMPDIR/brew/bin/macchina"
  GROVE_BREW="$BATS_TEST_TMPDIR/brew/bin/brew" PATH="$BATS_TEST_TMPDIR/stubs:/usr/bin:/bin" run check
  [ "$status" -eq 0 ]
}
