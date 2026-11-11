# shellcheck disable=SC2016,SC1090,SC1091,SC2154,SC2030,SC2031
# 97-themes-app: builds Grove Themes, installs it and starts it at login,
# against fake swift, codesign, iconutil, sips and launchctl and temp folders.
load helpers

TA_MODULE=97-themes-app

load_module() {
  local f
  for f in "$GROVE_ROOT"/lib/*.sh; do . "$f"; done
  MODULE_DIR="$GROVE_ROOT/modules/$TA_MODULE"
  . "$MODULE_DIR/module.sh"
}

setup() {
  grove_test_setup
  # The fake swift builds into its cwd, so the source is a throwaway git copy.
  export GROVE_APP_SRC="$BATS_TEST_TMPDIR/app-src"
  cp -R "$GROVE_ROOT/../grove-themes/app" "$GROVE_APP_SRC"
  rm -rf "$GROVE_APP_SRC/.build"
  git -C "$GROVE_APP_SRC" init -q
  git -C "$GROVE_APP_SRC" add -A
  export GROVE_APPS_DIR="$BATS_TEST_TMPDIR/Applications"
  export GROVE_AGENTS_DIR="$BATS_TEST_TMPDIR/LaunchAgents"
  mkdir -p "$GROVE_APPS_DIR" "$GROVE_AGENTS_DIR"
  APP="$GROVE_APPS_DIR/Grove Themes.app"
  AGENT="$GROVE_AGENTS_DIR/com.projectgrove.themes.plist"
  UID_="$(id -u)"
  stub swift '
echo "$*" >> "$BATS_TEST_TMPDIR/swift-args"
if [ -n "$FAKE_SWIFT_FAIL" ]; then echo "error: boom.swift:1: cannot find x" >&2; exit 1; fi
mkdir -p .build/release && printf "#!/bin/sh\n" > .build/release/GroveThemes && chmod +x .build/release/GroveThemes'
  stub codesign 'echo "$*" >> "$BATS_TEST_TMPDIR/codesign-args"'
  stub sips 'echo "$*" >> "$BATS_TEST_TMPDIR/sips-args"; while [ $# -gt 0 ]; do [ "$1" = --out ] && cp "$BATS_TEST_TMPDIR/stubs/sips" "$2"; shift; done'
  stub iconutil 'echo "$*" >> "$BATS_TEST_TMPDIR/iconutil-args"; while [ $# -gt 0 ]; do [ "$1" = -o ] && echo icns > "$2"; shift; done'
  # FAKE_LINGER=N: after a bootout, print still finds the job N times (launchd
  # finishes a bootout after launchctl returns), and a bootstrap meanwhile fails.
  # FAKE_BOOTSTRAP_FAILS=N: the first N bootstraps fail.
  stub launchctl '
echo "$*" >> "$BATS_TEST_TMPDIR/launchctl-args"
linger="$BATS_TEST_TMPDIR/linger"
fails="$BATS_TEST_TMPDIR/bootstrap-fails"
case "$1" in
  print)
    [ -e "$BATS_TEST_TMPDIR/loaded" ] && exit 0
    n="$(cat "$linger" 2>/dev/null || echo 0)"
    [ "$n" -gt 0 ] || exit 1
    echo $((n - 1)) > "$linger" ;;
  bootstrap)
    [ "$(cat "$linger" 2>/dev/null || echo 0)" -eq 0 ] || exit 5
    n="$(cat "$fails" 2>/dev/null || echo "${FAKE_BOOTSTRAP_FAILS:-0}")"
    if [ "$n" -gt 0 ]; then echo $((n - 1)) > "$fails"; exit 5; fi
    touch "$BATS_TEST_TMPDIR/loaded" ;;
  bootout) rm -f "$BATS_TEST_TMPDIR/loaded"; echo "${FAKE_LINGER:-0}" > "$linger" ;;
  *) : ;;
esac'
  export GROVE_SWIFT="$BATS_TEST_TMPDIR/stubs/swift"
  export GROVE_CODESIGN="$BATS_TEST_TMPDIR/stubs/codesign"
  export GROVE_LAUNCHCTL="$BATS_TEST_TMPDIR/stubs/launchctl"
  mkdir -p "$GROVE_STATE"
}

# ta_ready: what a finished apply leaves.
ta_ready() {
  load_module
  mkdir -p "$APP/Contents/MacOS"
  printf '#!/bin/sh\n' > "$APP/Contents/MacOS/GroveThemes"
  chmod +x "$APP/Contents/MacOS/GroveThemes"
  _ta_source_hash > "$GROVE_STATE/themes-app.stamp"
  _ta_agent_plist > "$AGENT"
  touch "$BATS_TEST_TMPDIR/loaded"
}

@test "themes-app: about names it" {
  load_module
  [ "$(about)" = "Grove Themes in the menu bar" ]
}

@test "themes-app: failed without swift" {
  load_module
  export GROVE_SWIFT="$BATS_TEST_TMPDIR/no-such-swift"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"command line tools"* ]] || false
}

@test "themes-app: needs work when the app is missing" {
  ta_ready
  rm -rf "$APP"
  run check
  [ "$status" -eq 3 ]
}

@test "themes-app: needs work when the source changed" {
  ta_ready
  echo stale > "$GROVE_STATE/themes-app.stamp"
  run check
  [ "$status" -eq 3 ]
}

@test "themes-app: needs work when the agent file differs" {
  ta_ready
  echo other > "$AGENT"
  run check
  [ "$status" -eq 3 ]
}

@test "themes-app: needs work when the agent isn't loaded" {
  ta_ready
  rm "$BATS_TEST_TMPDIR/loaded"
  run check
  [ "$status" -eq 3 ]
}

@test "themes-app: ok when built, current and loaded" {
  ta_ready
  run check
  [ "$status" -eq 0 ]
}

@test "themes-app: check changes nothing" {
  ta_ready
  rm "$BATS_TEST_TMPDIR/loaded"
  before="$(find "$BATS_TEST_TMPDIR" -not -name '*-args' | sort)"
  run check
  [ "$status" -eq 3 ]
  after="$(find "$BATS_TEST_TMPDIR" -not -name '*-args' | sort)"
  [ "$before" = "$after" ]
}

@test "themes-app: agent plist runs the app with a PATH that finds the CLI" {
  load_module
  out="$(_ta_agent_plist)"
  printf '%s' "$out" > "$BATS_TEST_TMPDIR/a.plist"
  [ "$(plutil -extract Label raw "$BATS_TEST_TMPDIR/a.plist")" = com.projectgrove.themes ]
  [ "$(plutil -extract ProgramArguments.0 raw "$BATS_TEST_TMPDIR/a.plist")" = "$APP/Contents/MacOS/GroveThemes" ]
  [ "$(plutil -extract RunAtLoad raw "$BATS_TEST_TMPDIR/a.plist")" = true ]
  [ "$(plutil -extract ProcessType raw "$BATS_TEST_TMPDIR/a.plist")" = Interactive ]
  [ "$(plutil -extract EnvironmentVariables.PATH raw "$BATS_TEST_TMPDIR/a.plist")" = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" ]
}

@test "themes-app: apply builds, assembles, signs, installs and loads" {
  load_module
  run apply
  [ "$status" -eq 0 ]
  [ -x "$APP/Contents/MacOS/GroveThemes" ]
  [ -f "$APP/Contents/Resources/AppIcon.icns" ]
  [ "$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")" = com.projectgrove.themes ]
  [ "$(plutil -extract LSUIElement raw "$APP/Contents/Info.plist")" = true ]
  # The CLI child's Apple events count as the app's: without this key macOS
  # refuses them without asking.
  [ "$(plutil -extract NSAppleEventsUsageDescription raw "$APP/Contents/Info.plist")" = "Grove Themes switches macOS between light and dark and sets the wallpaper to match your scheme." ]
  grep -q -- "^--force --sign - .*/Grove Themes.app$" "$BATS_TEST_TMPDIR/codesign-args"
  [ "$(cat "$GROVE_STATE/themes-app.stamp")" = "$(_ta_source_hash)" ]
  [ "$(cat "$AGENT")" = "$(_ta_agent_plist)" ]
  grep -q "^bootstrap gui/$UID_ $AGENT\$" "$BATS_TEST_TMPDIR/launchctl-args"
  run check
  [ "$status" -eq 0 ]
}

@test "themes-app: apply restarts a running app" {
  load_module
  touch "$BATS_TEST_TMPDIR/loaded"
  _ta_agent_plist > "$AGENT"
  run apply
  [ "$status" -eq 0 ]
  grep -q "^kickstart -k gui/$UID_/com.projectgrove.themes\$" "$BATS_TEST_TMPDIR/launchctl-args"
  run grep -q '^bootstrap' "$BATS_TEST_TMPDIR/launchctl-args"
  [ "$status" -ne 0 ]
}

@test "themes-app: apply reloads a loaded agent whose plist changed" {
  load_module
  touch "$BATS_TEST_TMPDIR/loaded"
  echo old > "$AGENT"
  run apply
  [ "$status" -eq 0 ]
  [ "$(cat "$AGENT")" = "$(_ta_agent_plist)" ]
  grep -q "^bootout gui/$UID_/com.projectgrove.themes\$" "$BATS_TEST_TMPDIR/launchctl-args"
  grep -q "^bootstrap gui/$UID_ $AGENT\$" "$BATS_TEST_TMPDIR/launchctl-args"
  [ "$(grep -n '^bootout' "$BATS_TEST_TMPDIR/launchctl-args" | cut -d: -f1)" -lt "$(grep -n '^bootstrap' "$BATS_TEST_TMPDIR/launchctl-args" | cut -d: -f1)" ]
}

@test "themes-app: apply waits for a bootout to finish before bootstrapping" {
  load_module
  touch "$BATS_TEST_TMPDIR/loaded"
  echo old > "$AGENT"
  export FAKE_LINGER=3
  run apply
  [ "$status" -eq 0 ]
  [ -e "$BATS_TEST_TMPDIR/loaded" ]
  # bootout, then print until the job is gone (3 lingering + 1 that fails), then one bootstrap.
  [ "$(cut -d' ' -f1 "$BATS_TEST_TMPDIR/launchctl-args" | sed 1,/^bootout/d | tr '\n' ' ')" = "print print print print bootstrap " ]
}

@test "themes-app: apply retries a bootstrap that fails once" {
  load_module
  export FAKE_BOOTSTRAP_FAILS=1
  run apply
  [ "$status" -eq 0 ]
  [ -e "$BATS_TEST_TMPDIR/loaded" ]
  [ "$(grep -c "^bootstrap gui/$UID_ $AGENT\$" "$BATS_TEST_TMPDIR/launchctl-args")" -eq 2 ]
}

@test "themes-app: apply fails when bootstrap keeps failing" {
  load_module
  export FAKE_BOOTSTRAP_FAILS=5
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"launchctl bootstrap"* ]] || false
  [ "$(grep -c '^bootstrap' "$BATS_TEST_TMPDIR/launchctl-args")" -eq 2 ]
}

@test "themes-app: a failed build leaves the installed app and stamp" {
  ta_ready
  echo old > "$APP/Contents/MacOS/GroveThemes"
  echo oldstamp > "$GROVE_STATE/themes-app.stamp"
  export FAKE_SWIFT_FAIL=1
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: boom.swift:1: cannot find x"* ]] || false
  [ "$(cat "$APP/Contents/MacOS/GroveThemes")" = old ]
  [ "$(cat "$GROVE_STATE/themes-app.stamp")" = oldstamp ]
}

@test "themes-app: the README lists the module" {
  grep -q '^| `97-themes-app` | Grove Themes in the menu bar: builds the app, installs it to ~/Applications and starts it at login |$' "$GROVE_ROOT/README.md"
}

@test "themes-app: swift test passes" {
  # The real swift: setup puts a fake one first on PATH, which would "build"
  # a fake app into the real source tree.
  local path="/usr/bin:/bin:/usr/sbin:/sbin"
  PATH="$path" command -v swift >/dev/null || skip "swift isn't installed"
  cd "$GROVE_ROOT/../grove-themes/app"
  run env PATH="$path" swift test
  [ "$status" -eq 0 ]
  # The real suite ran (not a fake swift that "builds" into this source tree).
  [[ "$output" == *"Test run with"* ]] || false
}

@test "themes-app: the bundle registers the grovethemes URL scheme for the bar's Themes… item" {
  local plist="$GROVE_ROOT/../grove-themes/app/Resources/Info.plist"
  grep -q '<key>CFBundleURLTypes</key>' "$plist"
  grep -q '<string>grovethemes</string>' "$plist"
  plutil -lint "$plist" >/dev/null
}
