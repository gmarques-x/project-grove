#!/usr/bin/env bats
# config/sketchybar: sketchybarrc and its plugins. Each plugin runs under an
# empty environment (as SketchyBar starts it), with faked data commands on
# SB_PATH and a fake sketchybar that records its arguments.
# shellcheck disable=SC1090,SC1091,SC2016

load helpers

setup() {
  grove_test_setup
  SB="$GROVE_ROOT/config/sketchybar"
  FX="$GROVE_ROOT/tests/fixtures/sketchybar"
  . "$GROVE_ROOT/../grove-themes/lib/render.sh"
  # The config folder as SketchyBar sees it: the tracked files + a rendered colors.sh.
  CFG="$BATS_TEST_TMPDIR/sketchybar"
  mkdir -p "$CFG"
  cp -R "$SB/." "$CFG/"
  gt_render_file dark-medium "$GROVE_ROOT/theme" "$SB/colors.sh.tmpl" "$CFG/colors.sh"
  FAKES="$BATS_TEST_TMPDIR/fakes"
  mkdir -p "$FAKES"
  CALLS="$BATS_TEST_TMPDIR/sketchybar-calls"
  fake sketchybar 'printf "%s\n" "$*" >> "'"$CALLS"'"'
}

# fake NAME BODY: a bash command in $FAKES.
fake() {
  printf '#!/bin/bash\n%s\n' "$2" > "$FAKES/$1"
  chmod +x "$FAKES/$1"
}

# plugin NAME [VAR=VALUE…]: run plugins/NAME.sh the way SketchyBar does.
plugin() {
  local name="$1"; shift
  run env -i HOME="$HOME" TMPDIR="$BATS_TEST_TMPDIR" CONFIG_DIR="$CFG" NAME="$name" \
    SB_PATH="$FAKES:/usr/bin:/bin" SKETCHYBAR_BIN="$FAKES/sketchybar" GROVE_STATE="$GROVE_STATE" \
    "$@" /bin/bash "$CFG/plugins/$name.sh"
}

calls() { cat "$CALLS" 2>/dev/null; }
ncalls() { if [ -f "$CALLS" ]; then wc -l < "$CALLS" | tr -d ' '; else echo 0; fi; }

@test "sketchybar: every script is valid bash and passes shellcheck" {
  local f
  for f in "$SB/sketchybarrc" "$SB/lib.sh" "$SB"/plugins/*.sh; do
    bash -n "$f" || { echo "$f"; false; }
  done
  command -v shellcheck >/dev/null || skip "no shellcheck"
  shellcheck -x "$SB/sketchybarrc" "$SB/lib.sh" "$SB"/plugins/*.sh
}

@test "sketchybar: colours only come from colors.sh" {
  ! grep -rnE '0x[0-9A-Fa-f]{8}' "$SB" --include='*.sh' --include=sketchybarrc | grep -vE '/colors\.sh(\.tmpl)?:'
}

@test "sketchybar: colors.sh renders every colour for all six schemes" {
  local s out n
  for s in $(gt_schemes); do
    out="$BATS_TEST_TMPDIR/colors-$s.sh"
    gt_render_file "$s" "$GROVE_ROOT/theme" "$SB/colors.sh.tmpl" "$out"
    for n in BG0 BG1 BG3 FG GREY2 GREEN AQUA BLUE ORANGE YELLOW RED; do
      grep -qE "^export $n=0xff[0-9A-F]{6}\$" "$out" || { echo "$s $n"; false; }
    done
    grep -q "^export PINE_ICON=\"\$CONFIG_DIR/icons/pine-${s%%-*}.png\"\$" "$out"
  done
}

@test "sketchybar: the pine icon exists for dark and light" {
  [ -s "$SB/icons/pine-dark.png" ] && [ -s "$SB/icons/pine-light.png" ]
}

# rc: run sketchybarrc against the fake sketchybar (one recorded line per call).
rc() {
  run env -i HOME="$HOME" CONFIG_DIR="$CFG" SB_PATH="$FAKES:/usr/bin:/bin" /bin/bash "$CFG/sketchybarrc"
}

@test "sketchybar: the items are added left and right in order" {
  local left right
  rc
  [ "$status" -eq 0 ]
  left="$(calls | grep -oE -- '--add item [a-z_.0-9]+ left' | awk '{print $3}' | tr '\n' ' ')"
  right="$(calls | grep -oE -- '--add item [a-z_.0-9]+ right' | awk '{print $3}' | tr '\n' ' ')"
  [ "$left" = "grove sep.l1 ws.1 ws.2 ws.3 ws.4 ws.5 ws.6 ws.7 ws.8 ws.9 front_app " ] || { echo "$left"; false; }
  [ "$right" = "keys sep.r1 clock sep.r2 volume sep.r3 wifi sep.r4 battery sep.r5 net.up net.down sep.r6 mem cpu sep.r7 " ] || { echo "$right"; false; }
  calls | grep -q -- '--add event aerospace_workspace_change'
  calls | grep -q -- '--subscribe ws.1 aerospace_workspace_change'
}

@test "sketchybar: separators are a bg3 bar, the same as the one before the app" {
  rc
  local n
  for n in sep.l1 sep.r1 sep.r2 sep.r3 sep.r4 sep.r5 sep.r6 sep.r7; do
    calls | grep -q -- "--set $n icon=│ icon.color=$(. "$CFG/colors.sh"; echo "$BG3")" || { echo "$n"; false; }
  done
  calls | grep -q -- '--set front_app .*icon=│'
}

@test "sketchybar: values have fixed widths, so the separators never move" {
  rc
  local pair item width
  # JetBrains Mono 13 is 7.8 pt a character: each width fits the item's longest value.
  for pair in cpu:32 mem:32 net.down:40 net.up:40 battery:32 wifi:32 volume:32 clock:134; do
    item="${pair%%:*}"; width="${pair#*:}"
    calls | grep -qE -- "--set $item .*label.width=$width( |\$)" || { echo "$item"; false; }
  done
  for item in cpu mem net.down net.up volume; do
    calls | grep -qE -- "--set $item .*label.align=right" || { echo "$item align"; false; }
  done
}

@test "sketchybar: the right side's value slots fit beside the notch" {
  rc
  # The built-in screen is 1920 pt wide with a ~200 pt notch in the middle,
  # so the right side has ~860 pt; labels may take at most 380 of it (icons,
  # padding and separators take ~420).
  local total
  total="$(calls | grep -oE -- '--set [a-z.]+ [^-]*label.width=[0-9]+' | grep -vE 'ws\.|front_app' | grep -oE 'label.width=[0-9]+' | cut -d= -f2 | paste -sd+ - | bc)"
  [ "$total" -le 380 ] || { echo "$total"; false; }
}

@test "sketchybar: the Grove tree is the item's icon image, so its background can show hover" {
  rc
  calls | grep -qE -- '--set grove .*icon.background.image=.*/icons/pine-dark.png'
}

@test "sketchybar: clickable items subscribe to hover" {
  rc
  local item
  for item in grove net.up net.down keys clock; do
    calls | grep -qE -- "--subscribe $item .*mouse.entered mouse.exited" || { echo "$item"; false; }
  done
}

@test "hover: a soft bg1 background under the pointer, gone when it leaves" {
  plugin net.down SENDER=mouse.entered
  . "$CFG/colors.sh"
  [ "$(calls)" = "--set net.down background.drawing=on background.color=$BG1" ]
  : > "$CALLS"
  plugin net.down SENDER=mouse.exited
  [ "$(calls)" = "--set net.down background.drawing=off" ]
}

@test "sketchybar: the bar is a 48 pt bg0 strip above the menu bar with one floating bracket" {
  grep -q -- '--bar height=48 color="\$BG0" topmost=on sticky=on' "$SB/sketchybarrc"
  grep -q -- '--add bracket bar ' "$SB/sketchybarrc"
  grep -q 'background.height=32 background.corner_radius=10 background.border_width=1 background.border_color="\$BG3"' "$SB/sketchybarrc"
}

@test "workspaces: the ones in use are drawn, the focused one is a green pill" {
  fake aerospace 'case "$*" in *--focused*) echo 3 ;; *) printf "1\n3\n5\n" ;; esac'
  plugin workspaces
  [ "$status" -eq 0 ]
  [ "$(ncalls)" -eq 1 ]
  [[ "$(calls)" == *"--set ws.1 drawing=on background.drawing=off"* ]] || false
  [[ "$(calls)" == *"--set ws.3 drawing=on background.drawing=on"* ]] || false
  [[ "$(calls)" == *"--set ws.2 drawing=off"* ]] || false
}

@test "workspaces: FOCUSED from the AeroSpace trigger wins" {
  fake aerospace 'case "$*" in *--focused*) echo 1 ;; *) printf "1\n3\n" ;; esac'
  plugin workspaces FOCUSED=3
  [[ "$(calls)" == *"--set ws.3 drawing=on background.drawing=on"* ]] || false
  [[ "$(calls)" == *"--set ws.1 drawing=on background.drawing=off"* ]] || false
}

@test "workspaces: without AeroSpace every workspace is hidden" {
  fake aerospace 'exit 2'
  plugin workspaces
  [ "$status" -eq 0 ]
  [[ "$(calls)" == *"--set ws.1 drawing=off"* ]] || false
  [[ "$(calls)" != *"drawing=on"* ]] || false
}

@test "front_app: the app's name from INFO" {
  plugin front_app INFO=Ghostty
  [ "$(calls)" = '--set front_app label=Ghostty' ]
}

@test "front_app: without INFO (a reload, the first run) it asks macOS for the front app" {
  fake lsappinfo 'case "$1" in front) echo "ASN:0x0-0x46046:" ;; info) printf "%s\n" "\"Ghostty\" ASN:0x0-0x46046: (in front) " "    bundleID=[ NULL ] " ;; esac'
  plugin front_app
  [ "$(calls)" = '--set front_app label=Ghostty' ]
}

@test "cpu and mem: one call sets both" {
  fake top 'cat "'"$FX"'/top.txt"'
  fake vm_stat 'cat "'"$FX"'/vm_stat.txt"'
  fake sysctl 'echo 25769803776'
  plugin cpu
  [ "$(ncalls)" -eq 1 ]
  . "$CFG/colors.sh"
  [ "$(calls)" = "--set cpu label=13% label.color=$FG --set mem label=52% label.color=$FG" ]
}

@test "cpu and mem: a failing source shows —" {
  fake top 'exit 1'
  fake vm_stat 'exit 1'
  fake sysctl 'exit 1'
  plugin cpu
  . "$CFG/colors.sh"
  [ "$(calls)" = "--set cpu label=— label.color=$FG --set mem label=— label.color=$FG" ]
}

@test "cpu and mem: yellow above 70%, red above 90%" {
  fake top 'echo "CPU usage: 50.0% user, 30.0% sys, 20.0% idle"'
  fake vm_stat 'cat "'"$FX"'/vm_stat.txt"'
  fake sysctl 'echo 14033844547'
  plugin cpu
  . "$CFG/colors.sh"
  [ "$(calls)" = "--set cpu label=80% label.color=$YELLOW --set mem label=95% label.color=$RED" ]
}

@test "network: the first sample shows —, the next the rate on the default interface" {
  fake route 'printf "   route to: default\n  interface: en0\n"'
  fake netstat 'cat "'"$FX"'/netstat.txt"'
  plugin net.down
  [ "$(calls)" = '--set net.down label=— --set net.up label=—' ]
  # One second later the counters grew by 2048 in and 1024 out.
  sed -e 's/2456789012/2456791060/' -e 's/187654321/187655345/' "$FX/netstat.txt" > "$BATS_TEST_TMPDIR/netstat2.txt"
  fake netstat 'cat "'"$BATS_TEST_TMPDIR"'/netstat2.txt"'
  echo "en0 2456789012 187654321 1000" > "$BATS_TEST_TMPDIR/grove-sketchybar-net"
  : > "$CALLS"
  plugin net.down SB_NOW=1001
  [ "$(calls)" = '--set net.down label=2K --set net.up label=1K' ]
}

@test "network: an interface change shows — for one sample" {
  fake route 'printf "  interface: en5\n"'
  fake netstat 'cat "'"$FX"'/netstat.txt"'
  echo "en0 2456789012 187654321 1000" > "$BATS_TEST_TMPDIR/grove-sketchybar-net"
  plugin net.down SB_NOW=1002
  [ "$(calls)" = '--set net.down label=— --set net.up label=—' ]
}

@test "network popup: interface totals and the top apps" {
  fake netstat 'cat "'"$FX"'/netstat.txt"'
  fake nettop 'cat "'"$FX"'/nettop.csv"'
  plugin network_popup
  [ "$(ncalls)" -eq 1 ]
  [[ "$(calls)" == *"--set net.total.1 drawing=on label=en0  ↓ 2.3 GB  ↑ 179 MB"* ]] || false
  [[ "$(calls)" == *"--set net.app.1 drawing=on label=mDNSResponder  ↓ 8.9 MB  ↑ 1.8 MB"* ]] || false
  [[ "$(calls)" == *"--set net.app.5 drawing=on"* ]] || false
}

@test "network popup: a nettop that fails says top apps unavailable" {
  fake netstat 'cat "'"$FX"'/netstat.txt"'
  fake nettop 'exit 1'
  plugin network_popup
  [[ "$(calls)" == *"--set net.app.1 drawing=on label=top apps unavailable"* ]] || false
  [[ "$(calls)" == *"--set net.app.2 drawing=off"* ]] || false
}

@test "battery: the level, coloured green while charging, yellow under 20%, red under 10%" {
  . "$CFG/colors.sh"
  fake pmset 'cat "'"$FX"'/pmset-charging.txt"'
  plugin battery
  [ "$(calls)" = "--set battery drawing=on label=87% label.color=$GREEN" ]
  : > "$CALLS"
  fake pmset 'cat "'"$FX"'/pmset-battery.txt"'
  plugin battery
  [ "$(calls)" = "--set battery drawing=on label=100% label.color=$FG" ]
  : > "$CALLS"
  fake pmset 'printf "x\n -InternalBattery-0 (id=1)\t15%%; discharging; 1:00 remaining present: true\n"'
  plugin battery
  [ "$(calls)" = "--set battery drawing=on label=15% label.color=$YELLOW" ]
  : > "$CALLS"
  fake pmset 'printf "x\n -InternalBattery-0 (id=1)\t9%%; discharging; 0:20 remaining present: true\n"'
  plugin battery
  [ "$(calls)" = "--set battery drawing=on label=9% label.color=$RED" ]
}

@test "battery: hidden without a battery" {
  fake pmset 'cat "'"$FX"'/pmset-none.txt"'
  plugin battery
  [ "$(calls)" = '--set battery drawing=off' ]
}

@test "connection: wifi, eth or vpn from the default route, grey when off" {
  . "$CFG/colors.sh"
  fake route 'printf "  interface: en0\n"'
  fake ipconfig 'cat "'"$FX"'/ipconfig-wifi.txt"'
  plugin wifi
  [ "$(calls)" = "--set wifi label=wifi label.color=$BLUE" ]
  : > "$CALLS"
  fake route 'printf "  interface: utun3\n"'
  plugin wifi
  [ "$(calls)" = "--set wifi label=vpn label.color=$BLUE" ]
  : > "$CALLS"
  fake route 'exit 1'
  plugin wifi
  [ "$(calls)" = "--set wifi label=off label.color=$GREY2" ]
}

@test "volume: the level from INFO, mute when muted" {
  fake osascript 'case "$*" in *muted*) echo false ;; *) echo 33 ;; esac'
  plugin volume INFO=60
  [ "$(calls)" = '--set volume label=60%' ]
  : > "$CALLS"
  fake osascript 'case "$*" in *muted*) echo true ;; *) echo 33 ;; esac'
  plugin volume INFO=60
  [ "$(calls)" = '--set volume label=mute' ]
}

@test "volume: without INFO (a reload, the first run) it reads the current level" {
  fake osascript 'case "$*" in *muted*) echo false ;; *) echo 56 ;; esac'
  plugin volume
  [ "$(calls)" = '--set volume label=56%' ]
}

@test "clock: weekday day month, two spaces, hours:minutes" {
  fake date 'echo "Tue 11 Nov  14:32"'
  plugin clock
  [ "$(calls)" = '--set clock label=Tue 11 Nov  14:32' ]
}

@test "keys: grey when Grove Keys is fine, orange when it needs attention" {
  mkdir -p "$GROVE_STATE"
  printf '{"accessibility": true, "input_monitoring": true, "mapping": true}\n' > "$GROVE_STATE/keys.json"
  plugin keys
  . "$CFG/colors.sh"
  [ "$(calls)" = "--set keys icon.color=$GREY2" ]
  : > "$CALLS"
  printf '{"accessibility": true, "input_monitoring": false, "mapping": false}\n' > "$GROVE_STATE/keys.json"
  plugin keys
  [ "$(calls)" = "--set keys icon.color=$ORANGE" ]
}

@test "calendar: the clock's popup shows this month, one line per row" {
  fake cal 'printf "   November 2026\nSu Mo Tu We Th Fr Sa\n 1  2  3  4  5  6  7\n 8  9 10 11 12 13 14\n"'
  plugin clock_popup
  [ "$(ncalls)" -eq 1 ]
  [[ "$(calls)" == *"--set cal.1 drawing=on label=   November 2026"* ]] || false
  [[ "$(calls)" == *"--set cal.4 drawing=on label= 8  9 10 11 12 13 14"* ]] || false
  [[ "$(calls)" == *"--set cal.5 drawing=off"* ]] || false
  [[ "$(calls)" == *"--set cal.8 drawing=off"* ]] || false
}

@test "clock: a click toggles the calendar popup" {
  rc
  calls | grep -qE -- '--set clock .*click_script=sketchybar --set clock popup.drawing=toggle; .*/plugins/clock_popup.sh'
  calls | grep -qE -- '--add item cal.1 popup.clock'
}
