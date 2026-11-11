#!/usr/bin/env bats
# grove present (the Grove window), its runner, grove --version and grove about.
# No test opens a window: `open` and `osascript` are fakes.

load helpers
bats_require_minimum_version 1.5.0

setup() {
  grove_test_setup
  export GROVE_MODULES="$GROVE_ROOT/tests/fixtures/modules"
  mkdir -p "$(dirname "$GROVE_LOCAL")"
  printf 'GROVE_NAME=T\nGROVE_EMAIL=t@e.x\nGROVE_GITHUB_USER=t\n' > "$GROVE_LOCAL"
  GROVE="$GROVE_ROOT/bin/grove"
  # The runner starts a login zsh: keep it away from the real zsh config.
  unset ZDOTDIR
  export GROVE_GHOSTTY_APP="$BATS_TEST_TMPDIR/Ghostty.app"
  mkdir -p "$GROVE_GHOSTTY_APP"
  # open: record the arguments, one per line; keep a copy of a .command file.
  stub open 'printf "%s\n" "$@" > "$HOME/open.args"
for a in "$@"; do case "$a" in *.command) cp -p "$a" "$HOME/opened.command" ;; esac; done'
  # The screen in front: 1920 x 1206 points.
  stub osascript 'echo "1920 1206"'
  # recorder: a command that writes its arguments down and exits 7.
  stub recorder 'printf "[%s]\n" "$@" > "$HOME/recorded"; echo "recorder ran"; exit 7'
  stub git 'echo abc1234'
  VERSION="$(cat "$GROVE_ROOT/VERSION")"
  # For about: no real fastfetch or grove-themes, only the fakes.
  BARE_PATH="$BATS_TEST_TMPDIR/stubs:/usr/bin:/bin"
}

open_arg() { sed -n "${1}p" "$HOME/open.args"; }

# ---- grove present

@test "present opens one Ghostty window of its own process on the runner" {
  run "$GROVE" present --title "Check it" recorder 'two words' "it's \"q\"" '$HOME;x'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  local q="'" cmd
  cmd="'$GROVE' __present 'Check it' 'recorder' 'two words' 'it'\\''s \"q\"' '\$HOME;x'"
  [ "$(cat "$HOME/open.args")" = "-na
$GROVE_GHOSTTY_APP
--args
--title=Grove · Check it
--initial-command=shell:$cmd
--window-width=128
--window-height=32
--quit-after-last-window-closed=true
--window-position-x=464
--window-position-y=292" ]
  # -e opens a second window in Ghostty 1.4; --initial-command does not.
  ! grep -qx -- '-e' "$HOME/open.args"
}

@test "present: the command reaches the runner intact, spaces and quotes included" {
  run "$GROVE" present --title "Check it" recorder 'two words' "it's \"q\"" '$HOME;x' ''
  local line
  line="$(grep '^--initial-command=shell:' "$HOME/open.args")"
  # As Ghostty runs a shell: command, with a key waiting on stdin.
  run /bin/sh -c "${line#--initial-command=shell:}" <<< "x"
  [ "$status" -eq 7 ]
  [ "$(cat "$HOME/recorded")" = "[two words]
[it's \"q\"]
[\$HOME;x]
[]" ]
  [[ "$output" == *"Grove · Check it"*"recorder ran"*"Failed (7)"* ]] || false
}

@test "present: the title defaults to the command's first word, without its folder" {
  run "$GROVE" present /usr/bin/true x
  [ "$(open_arg 4)" = "--title=Grove · true" ]
  run "$GROVE" present 'grove check'
  [ "$(open_arg 4)" = "--title=Grove · grove" ]
  run "$GROVE" present --title=Named true
  [ "$(open_arg 4)" = "--title=Grove · Named" ]
}

@test "present: options of the presented command are not grove's" {
  run "$GROVE" present --title T grove --quiet check --help --version
  [ "$status" -eq 0 ]
  [[ "$(open_arg 5)" == *"__present 'T' 'grove' '--quiet' 'check' '--help' '--version'" ]] || false
}

@test "present: the window is not centred when the screen size is unknown" {
  stub osascript 'exit 1'
  run "$GROVE" present true
  [ "$status" -eq 0 ]
  ! grep -q 'window-position' "$HOME/open.args"
  grep -qx -- '--window-width=128' "$HOME/open.args"
}

@test "present: the Grove window's process drops the user's global Ghostty keybinds" {
  mkdir -p "$HOME/.config/ghostty"
  printf 'font-size = 12\nkeybind = global:ctrl+grave_accent=toggle_quick_terminal\nkeybind = super+k=clear_screen\n' > "$HOME/.config/ghostty/config"
  run "$GROVE" present true
  [ "$(grep -- '^--keybind' "$HOME/open.args")" = "--keybind=global:ctrl+grave_accent=unbind" ]
}

@test "present without Ghostty: Terminal.app opens a .command file that starts the runner" {
  export GROVE_GHOSTTY_APP="$BATS_TEST_TMPDIR/none.app"
  run "$GROVE" present --title "Check it" recorder 'two words' "it's"
  [ "$status" -eq 0 ]
  [ "$(open_arg 1)" = "-a" ]
  [ "$(open_arg 2)" = "Terminal" ]
  local f; f="$(open_arg 3)"
  [[ "$f" == *.command ]] || false
  [ "$(sed -n 4p "$HOME/open.args")" = "" ]
  [ -x "$f" ]
  run "$f" <<< "x"
  [ "$status" -eq 7 ]
  [ "$(cat "$HOME/recorded")" = "[two words]
[it's]" ]
  [[ "$output" == *"Grove · Check it"*"Failed (7)"* ]] || false
  # The file cleans up after itself.
  [ ! -e "$(dirname "$f")" ]
}

@test "present: no command or an unknown option is a usage error and opens nothing" {
  run "$GROVE" present
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: grove present"* ]] || false
  run "$GROVE" present --title
  [ "$status" -eq 2 ]
  run "$GROVE" present --bogus true
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/open.args" ]
}

@test "present returns open's failure" {
  stub open 'exit 1'
  run "$GROVE" present true
  [ "$status" -eq 1 ]
}

# ---- the runner inside the window

@test "runner: header, the command, Done, exit 0" {
  run "$GROVE" __present "My title" /bin/echo "hello  there" <<< "x"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Grove · My title" ]
  [[ "$output" == *"hello  there"*"Done"*"Press any key to close"* ]] || false
  [[ "$output" != *"Failed"* ]] || false
}

@test "runner: Failed (N) and the command's exit code" {
  run "$GROVE" __present T /bin/sh -c 'echo out; exit 7' <<< "x"
  [ "$status" -eq 7 ]
  [[ "$output" == *"out"*"Failed (7)"* ]] || false
  [[ "$output" != *"Done"* ]] || false
  run -127 "$GROVE" __present T no-such-command-here <<< "x"
  [ "$status" -eq 127 ]
  [[ "$output" == *"Failed (127)"* ]] || false
}

@test "runner: a single argument is a shell command line" {
  run "$GROVE" __present T 'echo one && echo two | tr t T' <<< "x"
  [ "$status" -eq 0 ]
  [[ "$output" == *"one"*"Two"*"Done"* ]] || false
}

@test "runner: the command runs in a login shell and can read the terminal" {
  run "$GROVE" __present T /bin/sh -c 'read -r l; echo "got $l"' <<< "typed
x"
  [ "$status" -eq 0 ]
  [[ "$output" == *"got typed"*"Done"* ]] || false
  run "$GROVE" __present T 'print -r -- "login=$options[login]"' <<< "x"
  [[ "$output" == *"login=on"* ]] || false
}

@test "runner: waits for a key before it ends" {
  local key="$BATS_TEST_TMPDIR/key" out="$BATS_TEST_TMPDIR/out" pid i=0
  mkfifo "$key"
  "$GROVE" __present T true < "$key" > "$out" 2>&1 3>&- &
  pid=$!
  exec 9> "$key"   # the keyboard: nothing typed yet
  until grep -q 'Press any key' "$out" || [ "$i" -ge 100 ]; do sleep 0.1; i=$((i + 1)); done
  grep -q 'Done' "$out"
  sleep 0.5
  kill -0 "$pid"   # still there, waiting
  printf 'x' >&9
  wait "$pid"
  exec 9>&-
}

# ---- grove --version

@test "--version prints the version and the short commit" {
  [ "$VERSION" = "0.9.0" ]
  run "$GROVE" --version
  [ "$status" -eq 0 ]
  [ "$output" = "grove 0.9.0 (abc1234)" ]
}

@test "--version without git, or outside a checkout, prints the version alone" {
  stub git 'echo "fatal: not a git repository" >&2; exit 128'
  run "$GROVE" --version
  [ "$status" -eq 0 ]
  [ "$output" = "grove 0.9.0" ]
}

@test "--version needs no modules and asks git about grove's own folder" {
  stub git 'echo "$*" > "$HOME/git.args"; echo abc1234'
  GROVE_MODULES="$BATS_TEST_TMPDIR/none" run "$GROVE" --version
  [ "$output" = "grove 0.9.0 (abc1234)" ]
  [ "$(cat "$HOME/git.args")" = "-C $GROVE_ROOT rev-parse --short HEAD" ]
}

# ---- grove about

@test "about: the fetch, then version, scheme and never updated" {
  mkdir -p "$HOME/.config/fastfetch"; echo '{}' > "$HOME/.config/fastfetch/config.jsonc"
  stub fastfetch 'echo "FETCH $*"'
  stub grove-themes '[ "$1" = current ] && echo light-soft'
  PATH="$BARE_PATH" run "$GROVE" about
  [ "$status" -eq 0 ]
  # Not a terminal: the fetch without a logo.
  [[ "$output" == *"FETCH --logo none"*"Grove    0.9.0 (abc1234)"* ]] || false
  [ "${lines[${#lines[@]}-3]}" = "Grove    0.9.0 (abc1234)" ]
  [ "${lines[${#lines[@]}-2]}" = "Scheme   light-soft" ]
  [ "${lines[${#lines[@]}-1]}" = "Updated  never" ]
}

@test "about without fastfetch and grove-themes skips the fetch and the scheme" {
  mkdir -p "$HOME/.config/fastfetch"; echo '{}' > "$HOME/.config/fastfetch/config.jsonc"
  PATH="$BARE_PATH" run "$GROVE" about
  [ "$status" -eq 0 ]
  [ "$output" = "
Grove    0.9.0 (abc1234)
Updated  never" ]
}

@test "about without the rendered fastfetch config skips the fetch" {
  stub fastfetch 'echo "FETCH $*"'
  PATH="$BARE_PATH" run "$GROVE" about
  [ "$status" -eq 0 ]
  [[ "$output" != *FETCH* ]] || false
  [[ "$output" == *"Updated  never"* ]] || false
}

@test "about: Updated is when install or update last finished" {
  run "$GROVE" check
  run "$GROVE" list
  run "$GROVE" install 40-broken
  [ "$status" -eq 1 ]
  [ ! -e "$GROVE_STATE/updated" ]
  run "$GROVE" install 10-ok
  [ "$status" -eq 0 ]
  [[ "$(cat "$GROVE_STATE/updated")" =~ ^20[0-9][0-9]-[01][0-9]-[0-3][0-9]\ [0-2][0-9]:[0-5][0-9]$ ]] || false
  echo '2026-01-02 03:04' > "$GROVE_STATE/updated"
  PATH="$BARE_PATH" run "$GROVE" about
  [ "${lines[${#lines[@]}-1]}" = "Updated  2026-01-02 03:04" ]
  # A run that left modules for you (exit 3) and an update count too.
  rm "$GROVE_STATE/updated"
  run "$GROVE" --yes install 30-you
  [ "$status" -eq 3 ]
  [ -e "$GROVE_STATE/updated" ]
  rm "$GROVE_STATE/updated"
  run "$GROVE" update 20-work
  [ "$status" -eq 0 ]
  [ -e "$GROVE_STATE/updated" ]
}

# ---- read-only

@test "present, the runner, about and --version write no run log" {
  run "$GROVE" present true
  run "$GROVE" __present T true <<< "x"
  PATH="$BARE_PATH" run "$GROVE" about
  run "$GROVE" --version
  [ ! -e "$GROVE_STATE" ]
}

@test "usage lists about, present and --version" {
  run "$GROVE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"  about "*"  present [--title T] <command...>"*"  --version "* ]] || false
  # The runner is internal.
  [[ "$output" != *"__present"* ]] || false
}
