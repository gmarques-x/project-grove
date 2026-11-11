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

# click ITEM: a click on an item with a popup, as its click_script runs.
click() {
  run env -i HOME="$HOME" TMPDIR="$BATS_TEST_TMPDIR" CONFIG_DIR="$CFG" NAME="$1" SENDER=mouse.clicked \
    SB_PATH="$FAKES:/usr/bin:/bin" SKETCHYBAR_BIN="$FAKES/sketchybar" /bin/bash "$CFG/plugins/popup.sh" "$1"
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
  run env -i HOME="$HOME" TMPDIR="$BATS_TEST_TMPDIR" CONFIG_DIR="$CFG" SB_PATH="$FAKES:/usr/bin:/bin" /bin/bash "$CFG/sketchybarrc"
}

@test "sketchybar: no Grove Keys glyph on the right (it lives in the pine's menu)" {
  rc
  ! calls | grep -qE -- '--add item keys '
}

@test "sketchybar: the items are added left and right in order" {
  local left right
  rc
  [ "$status" -eq 0 ]
  left="$(calls | grep -oE -- '--add item [a-z_.0-9]+ left' | awk '{print $3}' | tr '\n' ' ')"
  right="$(calls | grep -oE -- '--add item [a-z_.0-9]+ right' | awk '{print $3}' | tr '\n' ' ')"
  local want="grove sep.l1 " n
  for n in 1 2 3 4 5 6 7 8 9; do want+="ws.$n ws.$n.1 ws.$n.2 ws.$n.3 ws.$n.4 ws.$n.5 ws.$n.6 sep.ws.$n "; done
  [ "$left" = "${want}front_app " ] || { echo "$left"; false; }
  [ "$right" = "clock sep.r1 volume sep.r2 wifi sep.r3 battery sep.r4 net.up net.down sep.r5 mem cpu sep.r6 " ] || { echo "$right"; false; }
  calls | grep -q -- '--add event aerospace_workspace_change'
  calls | grep -q -- '--subscribe ws.1 aerospace_workspace_change'
}

@test "sketchybar: separators are a bg3 bar; each workspace ends with one, hidden until it's in use" {
  rc
  local n
  for n in 1 2 3 4 5 6 7 8 9; do
    calls | grep -qx -- "--set sep.ws.$n drawing=off" || { echo "sep.ws.$n"; false; }
  done
  for n in sep.l1 sep.ws.1 sep.ws.9 sep.r1 sep.r2 sep.r3 sep.r4 sep.r5 sep.r6; do
    calls | grep -q -- "--set $n icon=│ icon.color=$(. "$CFG/colors.sh"; echo "$BG3")" || { echo "$n"; false; }
  done
  # The app's name follows the last workspace's separator: none of its own.
  calls | grep -q -- '--set front_app .*icon.drawing=off'
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

@test "sketchybar: the pine button is 52 pt wide, the tree centred in it" {
  rc
  calls | grep -qE -- '--set grove .*icon.width=18 .*width=52 align=center '
}

@test "sketchybar: clickable items subscribe to hover" {
  rc
  local item
  for item in grove net.up net.down clock; do
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
  # The floating bar's edges line up with the windows' 8 pt outer gaps.
  grep -q -- 'padding_left=8 padding_right=8 shadow=off' "$SB/sketchybarrc"
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

@test "workspaces: each one shows its apps' icons, once per app, then a separator" {
  fake aerospace 'case "$*" in
    *--focused*) echo 1 ;;
    *list-windows*) printf "1|com.google.Chrome|50\n1|com.mitchellh.ghostty|27\n1|com.google.Chrome|51\n2|com.microsoft.VSCode|60\n" ;;
    *) printf "1\n2\n" ;;
  esac'
  plugin workspaces
  [ "$status" -eq 0 ]
  [ "$(ncalls)" -eq 1 ]
  [[ "$(calls)" == *"--set ws.1.1 drawing=on icon.background.image=app.com.google.Chrome click_script=aerospace focus --window-id 50"* ]] || false
  [[ "$(calls)" == *"--set ws.1.2 drawing=on icon.background.image=app.com.mitchellh.ghostty click_script=aerospace focus --window-id 27"* ]] || false
  [[ "$(calls)" == *"--set ws.1.3 drawing=off"* ]] || false
  [[ "$(calls)" == *"--set ws.2.1 drawing=on icon.background.image=app.com.microsoft.VSCode"* ]] || false
  [[ "$(calls)" == *"--set sep.ws.1 drawing=on"* ]] || false
  [[ "$(calls)" == *"--set sep.ws.2 drawing=on"* ]] || false
  [[ "$(calls)" == *"--set ws.3 drawing=off --set sep.ws.3 drawing=off --set ws.3.1 drawing=off"* ]] || false
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
  fake iostat 'cat "'"$FX"'/iostat.txt"'
  fake vm_stat 'cat "'"$FX"'/vm_stat.txt"'
  fake sysctl 'echo 25769803776'
  plugin cpu
  [ "$(ncalls)" -eq 1 ]
  . "$CFG/colors.sh"
  [ "$(calls)" = "--set cpu label=9% label.color=$FG --set mem label=52% label.color=$FG" ]
}

@test "cpu and mem: a failing source shows —" {
  fake iostat 'exit 1'
  fake vm_stat 'exit 1'
  fake sysctl 'exit 1'
  plugin cpu
  . "$CFG/colors.sh"
  [ "$(calls)" = "--set cpu label=— label.color=$FG --set mem label=— label.color=$FG" ]
}

@test "cpu and mem: yellow above 70%, red above 90%" {
  fake iostat 'printf "      cpu    load average\n us sy id   1m   5m   15m\n 50 30 20  1.00 1.00 1.00\n"'
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
  [[ "$(calls)" == *"--set net.app.2 drawing=on label=Google Chrome H  ↓ 2.0 MB  ↑ 74 KB"* ]] || false
  [[ "$(calls)" == *"--set net.app.5 drawing=on"* ]] || false
}

@test "network popup: nettop is asked not to resolve names (-n), or it outlasts its 2 s" {
  fake netstat 'cat "'"$FX"'/netstat.txt"'
  fake nettop 'case " $* " in *" -n "*) cat "'"$FX"'/nettop.csv" ;; *) exit 1 ;; esac'
  plugin network_popup
  [[ "$(calls)" == *"--set net.app.1 drawing=on label=mDNSResponder"* ]] || false
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

@test "calendar: the clock's popup shows this month, one line per row" {
  fake cal 'printf "   November 2026\nSu Mo Tu We Th Fr Sa\n 1  2  3  4  5  6  7\n 8  9 10 11 12 13 14\n"'
  plugin clock_popup
  [ "$(ncalls)" -eq 1 ]
  # Leading spaces are no-break spaces (SketchyBar would cut the row's end otherwise).
  local nb=$'\xc2\xa0'
  [[ "$(calls)" == *"--set cal.1 drawing=on label=$nb$nb${nb}November 2026"* ]] || false
  [[ "$(calls)" == *"--set cal.4 drawing=on label=${nb}8  9 10 11 12 13 14"* ]] || false
  [[ "$(calls)" == *"--set cal.5 drawing=off"* ]] || false
  [[ "$(calls)" == *"--set cal.8 drawing=off"* ]] || false
}

@test "clock: under a Portuguese locale the day and month stay English" {
  locale -a | grep -qx 'pt_PT.UTF-8' || skip "no pt_PT.UTF-8 locale"
  plugin clock LC_ALL=pt_PT.UTF-8
  calls | grep -qE -- '^--set clock label=(Mon|Tue|Wed|Thu|Fri|Sat|Sun) [0-9]+ (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)  [0-9]{2}:[0-9]{2}$' || { calls; false; }
}

@test "popups: a click on the clock or either network rate goes to popup.sh" {
  rc
  calls | grep -qE -- '--set clock .*click_script=[^ ]*/plugins/popup.sh clock( |$)'
  calls | grep -qE -- '--set net.up .*click_script=[^ ]*/plugins/popup.sh net.down( |$)'
  calls | grep -qE -- '--set net.down .*click_script=[^ ]*/plugins/popup.sh net.down( |$)'
  calls | grep -qE -- '--add item cal.1 popup.clock'
  calls | grep -qE -- '--add item net.app.1 popup.net.down'
  # Nothing toggles a popup directly: that would show it before it's filled.
  ! grep -q 'popup.drawing=toggle' "$SB/sketchybarrc" "$SB"/plugins/*.sh
}

@test "popups: a reload forgets the open popup" {
  echo clock > "$BATS_TEST_TMPDIR/grove-sketchybar-popup"
  rc
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/grove-sketchybar-popup" ]
}

@test "popups: a click fills the popup, then shows it; a second click closes it without filling" {
  fake cal 'printf "   November 2026\nSu Mo Tu We Th Fr Sa\n"'
  click clock
  [ "$status" -eq 0 ]
  [ "$(ncalls)" -eq 2 ]
  [[ "$(calls | sed -n 1p)" == "--set cal.1 drawing=on label="*"November 2026"* ]] || false
  [ "$(calls | sed -n 2p)" = "--set clock popup.drawing=on" ]
  : > "$CALLS"
  click clock
  [ "$(calls)" = "--set clock popup.drawing=off" ]
  : > "$CALLS"
  click clock
  [ "$(calls | sed -n 2p)" = "--set clock popup.drawing=on" ]
}

@test "popups: opening one closes the other" {
  fake cal 'echo "   November 2026"'
  fake netstat 'cat "'"$FX"'/netstat.txt"'
  fake nettop 'cat "'"$FX"'/nettop.csv"'
  click clock
  : > "$CALLS"
  click net.down
  [ "$(ncalls)" -eq 2 ]
  [[ "$(calls | sed -n 1p)" == "--set net.total.1 drawing=on"* ]] || false
  [ "$(calls | sed -n 2p)" = "--set clock popup.drawing=off --set net.down popup.drawing=on" ]
  : > "$CALLS"
  click clock
  [ "$(calls | sed -n 2p)" = "--set net.down popup.drawing=off --set clock popup.drawing=on" ]
}

@test "popups: an item without a popup does nothing" {
  click volume
  [ "$status" -eq 0 ]
  [ "$(ncalls)" -eq 0 ]
}

@test "popups: an app switch or a workspace change closes the open one, a timed refresh doesn't" {
  fake aerospace 'case "$*" in *--focused*) echo 1 ;; *) printf "1\n" ;; esac'
  fake cal 'echo "   November 2026"'
  local sender
  for sender in front_app_switched aerospace_workspace_change; do
    click clock
    : > "$CALLS"
    plugin workspaces SENDER="$sender"
    [ "$(calls | sed -n 1p)" = "--set clock popup.drawing=off" ] || { echo "$sender"; calls; false; }
    [ "$(ncalls)" -eq 2 ]
    # Closed: the next switch has nothing to close.
    : > "$CALLS"
    plugin workspaces SENDER="$sender"
    [ "$(ncalls)" -eq 1 ]
    [[ "$(calls)" != *"popup.drawing"* ]] || false
  done
  click clock
  : > "$CALLS"
  plugin workspaces SENDER=routine
  [[ "$(calls)" != *"popup.drawing"* ]] || false
  plugin workspaces
  [[ "$(calls)" != *"popup.drawing"* ]] || false
}

@test "sketchybar: the pine opens the grove menu, the app name the app's menus" {
  rc
  calls | grep -qE -- '--set grove .*click_script=open grovekeys://grove-menu'
  calls | grep -qE -- '--set front_app .*click_script=open grovekeys://app-menu'
  calls | grep -qE -- '--subscribe front_app front_app_switched mouse.entered mouse.exited'
}
