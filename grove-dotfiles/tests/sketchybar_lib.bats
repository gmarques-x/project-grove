#!/usr/bin/env bats
# config/sketchybar/lib.sh: the parsers and formatters every bar plugin uses,
# against output recorded from macOS (anonymised) in fixtures/sketchybar/.

load helpers

setup() {
  grove_test_setup
  FX="$GROVE_ROOT/tests/fixtures/sketchybar"
  # shellcheck source=/dev/null
  . "$GROVE_ROOT/config/sketchybar/lib.sh"
}

@test "sb_cpu: used percentage (100 − idle) from the last iostat sample" {
  [ "$(sb_cpu < "$FX/iostat.txt")" = 9 ]
  [ "$(echo nonsense | sb_cpu)" = "—" ]
  [ "$(printf '      cpu    load average\n us sy id   1m   5m   15m\n' | sb_cpu)" = "—" ]
}

@test "sb_mem: active + wired + compressed pages over the memory size" {
  [ "$(sb_mem 25769803776 < "$FX/vm_stat.txt")" = 52 ]
  [ "$(sb_mem "" < "$FX/vm_stat.txt")" = "—" ]
  [ "$(echo nonsense | sb_mem 25769803776)" = "—" ]
}

@test "sb_battery: level and whether it's charging, nothing without a battery" {
  [ "$(sb_battery < "$FX/pmset-charging.txt")" = "87 charging" ]
  [ "$(sb_battery < "$FX/pmset-battery.txt")" = "100 discharging" ]
  [ "$(sb_battery < "$FX/pmset-none.txt")" = "" ]
}

@test "sb_conn: vpn for a tunnel, wifi or eth from the interface type, off without a route" {
  [ "$(sb_conn utun3 < /dev/null)" = "vpn" ]
  [ "$(sb_conn ipsec0 < /dev/null)" = "vpn" ]
  [ "$(sb_conn en0 < "$FX/ipconfig-wifi.txt")" = "wifi" ]
  [ "$(sb_conn en5 < "$FX/ipconfig-eth.txt")" = "eth" ]
  [ "$(sb_conn "" < /dev/null)" = "off" ]
}

@test "sb_icon: the symbol's file in the scheme's set; without ICON_SET the pine's file says which" {
  CONFIG_DIR=/cfg
  [ "$(ICON_SET=dark sb_icon wifi-2)" = "/cfg/icons/wifi-2-dark.png" ]
  [ "$(ICON_SET=light sb_icon vol-mute)" = "/cfg/icons/vol-mute-light.png" ]
  [ "$(ICON_SET='' PINE_ICON=/cfg/icons/pine-light.png sb_icon cpu)" = "/cfg/icons/cpu-light.png" ]
  [ "$(ICON_SET='' PINE_ICON=/cfg/icons/pine-dark.png sb_icon cpu)" = "/cfg/icons/cpu-dark.png" ]
  [ "$(unset ICON_SET PINE_ICON; sb_icon cpu)" = "/cfg/icons/cpu-dark.png" ]
}

@test "sb_wifi_level: three arcs from -60 dBm, two down to -72, one below; three when it can't be read" {
  [ "$(sb_wifi_level -40)" = 3 ]
  [ "$(sb_wifi_level -60)" = 3 ]
  [ "$(sb_wifi_level -61)" = 2 ]
  [ "$(sb_wifi_level -72)" = 2 ]
  [ "$(sb_wifi_level -73)" = 1 ]
  [ "$(sb_wifi_level -95)" = 1 ]
  [ "$(sb_wifi_level "")" = 3 ]
  [ "$(sb_wifi_level 0)" = 3 ]
  [ "$(sb_wifi_level -6x)" = 3 ]
  [ "$(sb_wifi_level nonsense)" = 3 ]
}

@test "sb_vol_level: tenths, rounded; anything above silence is at least 1" {
  [ "$(sb_vol_level 0)" = 0 ]
  [ "$(sb_vol_level 1)" = 1 ]
  [ "$(sb_vol_level 9)" = 1 ]
  [ "$(sb_vol_level 14)" = 1 ]
  [ "$(sb_vol_level 15)" = 2 ]
  [ "$(sb_vol_level 56)" = 6 ]
  [ "$(sb_vol_level 94)" = 9 ]
  [ "$(sb_vol_level 95)" = 10 ]
  [ "$(sb_vol_level 100)" = 10 ]
  [ "$(sb_vol_level "")" = 0 ]
  [ "$(sb_vol_level loud)" = 0 ]
}

@test "fixtures: nothing recorded from this Mac names its serial numbers" {
  ! grep -nE '"Serial(String)?" ?= ?"[^X"]' "$FX/ioreg-battery.txt"
  ! grep -nE 'Serial Number: [^X]' "$FX/system_profiler-power.txt"
}

@test "sb_load: high above 70, critical above 90" {
  [ "$(sb_load 12)" = "normal" ]
  [ "$(sb_load 70)" = "normal" ]
  [ "$(sb_load 71)" = "high" ]
  [ "$(sb_load 90)" = "high" ]
  [ "$(sb_load 91)" = "critical" ]
  [ "$(sb_load —)" = "normal" ]
}

@test "locale: a decimal-comma, Portuguese locale changes neither numbers nor dates" {
  locale -a | grep -qx 'pt_PT.UTF-8' || skip "no pt_PT.UTF-8 locale"
  # The locale does change both without lib.sh, so the test means something.
  [ "$(LC_ALL=pt_PT.UTF-8 awk 'BEGIN { printf "%.1f", 1.2 }')" = "1,2" ]
  local lib="$GROVE_ROOT/config/sketchybar/lib.sh" how
  for how in LC_ALL LANG; do
    run env -i "$how=pt_PT.UTF-8" /bin/bash -c '. "$1"; printf "100 pages of page size of 16384\nPages active: 300000.\nPages wired down: 200000.\nPages occupied by compressor: 318000.\n" | sb_mem 25769803776; date -j -f %Y-%m-%d 2026-11-11 "+%a %-d %b"; echo "${LC_ALL:-unset}"' _ "$lib"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "52" ] || { echo "$how: ${lines[0]}"; false; }
    [ "${lines[1]}" = "Wed 11 Nov" ] || { echo "$how: ${lines[1]}"; false; }
    [ "${lines[2]}" = "unset" ]
  done
}

@test "sb_transparent: no fill, from colors.sh or bg0 without its alpha" {
  [ "$(TRANSPARENT=0x00000000 BG0=0xff2D353B sb_transparent)" = 0x00000000 ]
  [ "$(unset TRANSPARENT; BG0=0xff2D353B sb_transparent)" = 0x002D353B ]
}

@test "sb_pill: the pill each item of the bar sits in" {
  [ "$(sb_pill grove)" = pill.grove ]
  [ "$(sb_pill cpu)" = pill.sys ]
  [ "$(sb_pill mem)" = pill.sys ]
  [ "$(sb_pill battery)" = pill.battery ]
  [ "$(sb_pill wifi)" = pill.wifi ]
  [ "$(sb_pill bt)" = pill.wifi ]
  [ "$(sb_pill vpn.lab)" = pill.vpn ]
  [ "$(sb_pill cloud)" = pill.cloud ]
  [ "$(sb_pill tray)" = pill.tray ]
  [ "$(sb_pill volume)" = pill.volume ]
  [ "$(sb_pill clock)" = pill.clock ]
  [ "$(sb_pill ws.3)" = pill.ws.3 ]
  [ "$(sb_pill ws.7.2)" = pill.ws.7 ]
  [ "$(sb_pill ws.7.end)" = pill.ws.7 ]
  [ "$(sb_pill front_app)" = "" ]
  [ "$(sb_pill gap.r1)" = "" ]
  [ "$(sb_pill "")" = "" ]
}

@test "sb_hover: fills the item's pill on enter, clears it on exit; any other event is not a hover" {
  SB="$BATS_TEST_TMPDIR/sketchybar"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$BATS_TEST_TMPDIR/calls" > "$SB"
  chmod +x "$SB"
  BG0=0xff2D353B BG1=0xff343F44 HOVER_FILL=0xffE6E2CC TRANSPARENT=0x00000000
  NAME=cpu SENDER=mouse.entered sb_hover
  NAME=cpu SENDER=mouse.exited sb_hover
  NAME=front_app SENDER=mouse.entered sb_hover
  NAME=front_app SENDER=mouse.exited sb_hover
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "--set pill.sys background.color=0xffE6E2CC
--set pill.sys background.color=0x00000000
--set front_app background.drawing=on background.color=0xffE6E2CC
--set front_app background.drawing=off" ]
  : > "$BATS_TEST_TMPDIR/calls"
  # A colors.sh without the hover role: bg1.
  unset HOVER_FILL
  NAME=clock SENDER=mouse.entered sb_hover
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "--set pill.clock background.color=0xff343F44" ]
  : > "$BATS_TEST_TMPDIR/calls"
  local sender
  for sender in "" routine mouse.clicked front_app_switched; do
    ! NAME=cpu SENDER="$sender" sb_hover || { echo "$sender"; false; }
  done
  [ ! -s "$BATS_TEST_TMPDIR/calls" ]
}

@test "sb_hover: the pill of the open panel stays filled when the pointer leaves" {
  SB="$BATS_TEST_TMPDIR/sketchybar"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$BATS_TEST_TMPDIR/calls" > "$SB"
  chmod +x "$SB"
  SB_PANEL="$BATS_TEST_TMPDIR/bar-panel"
  BG0=0xff2D353B BG1=0xff343F44 HOVER_FILL=0xffE6E2CC TRANSPARENT=0x00000000
  echo pill.sys > "$SB_PANEL"
  NAME=cpu SENDER=mouse.exited sb_hover
  NAME=mem SENDER=mouse.exited sb_hover
  [ ! -s "$BATS_TEST_TMPDIR/calls" ]
  # Entering fills as ever; another pill clears as ever.
  NAME=mem SENDER=mouse.entered sb_hover
  NAME=clock SENDER=mouse.exited sb_hover
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "--set pill.sys background.color=0xffE6E2CC
--set pill.clock background.color=0x00000000" ]
  : > "$BATS_TEST_TMPDIR/calls"
  rm "$SB_PANEL"
  NAME=cpu SENDER=mouse.exited sb_hover
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "--set pill.sys background.color=0x00000000" ]
}

@test "sb_panel_open: the pill whose panel is open, nothing when none is" {
  SB_PANEL="$BATS_TEST_TMPDIR/bar-panel"
  [ "$(sb_panel_open)" = "" ]
  echo pill.wifi > "$SB_PANEL"
  [ "$(sb_panel_open)" = "pill.wifi" ]
  echo 'x; rm -rf y' > "$SB_PANEL"
  [ "$(sb_panel_open)" = "" ]
  : > "$SB_PANEL"
  [ "$(sb_panel_open)" = "" ]
}

@test "sb_panel_open: the file is Grove Keys', beside the theme state" {
  local lib="$GROVE_ROOT/config/sketchybar/lib.sh"
  [ "$(env -i HOME=/Users/someone /bin/bash -c '. "$1"; echo "$SB_PANEL"' _ "$lib")" = /Users/someone/.local/state/grove/bar-panel ]
  [ "$(env -i HOME=/Users/someone GROVE_STATE=/tmp/state /bin/bash -c '. "$1"; echo "$SB_PANEL"' _ "$lib")" = /tmp/state/bar-panel ]
}

@test "sb_bluetooth: the icon Grove Keys names (off, on, connected); off without the file or with anything else" {
  SB_BLUETOOTH="$BATS_TEST_TMPDIR/bluetooth"
  [ "$(sb_bluetooth)" = bt-off ]
  local word
  for word in off on connected; do
    echo "$word" > "$SB_BLUETOOTH"
    [ "$(sb_bluetooth)" = "bt-$word" ] || { echo "$word"; false; }
  done
  : > "$SB_BLUETOOTH"
  [ "$(sb_bluetooth)" = bt-off ]
  echo 'on; rm -rf y' > "$SB_BLUETOOTH"
  [ "$(sb_bluetooth)" = bt-off ]
  echo ON > "$SB_BLUETOOTH"
  [ "$(sb_bluetooth)" = bt-off ]
  # Only the first line counts.
  printf 'connected\non\n' > "$SB_BLUETOOTH"
  [ "$(sb_bluetooth)" = bt-connected ]
}

@test "sb_bluetooth: the file is Grove Keys', beside the theme state" {
  local lib="$GROVE_ROOT/config/sketchybar/lib.sh"
  [ "$(env -i HOME=/Users/someone /bin/bash -c '. "$1"; echo "$SB_BLUETOOTH"' _ "$lib")" = /Users/someone/.local/state/grove/bluetooth ]
  [ "$(env -i HOME=/Users/someone GROVE_STATE=/tmp/state /bin/bash -c '. "$1"; echo "$SB_BLUETOOTH"' _ "$lib")" = /tmp/state/bluetooth ]
}

@test "sb_cloud: the icon and the count for the line Grove Keys keeps; a grey cloud without the file or with anything else" {
  SB_CLOUD="$BATS_TEST_TMPDIR/cloud"
  # No file: Grove Keys isn't running.
  [ "$(sb_cloud)" = cloud-off ]
  echo checking > "$SB_CLOUD"
  [ "$(sb_cloud)" = cloud-checking ]
  echo synced > "$SB_CLOUD"
  [ "$(sb_cloud)" = cloud-synced ]
  echo problem > "$SB_CLOUD"
  [ "$(sb_cloud)" = cloud-problem ]
  echo "syncing 3" > "$SB_CLOUD"
  [ "$(sb_cloud)" = "cloud-syncing 3" ]
  echo "syncing 1999" > "$SB_CLOUD"
  [ "$(sb_cloud)" = "cloud-syncing 1999" ]
  echo "syncing 2000+" > "$SB_CLOUD"
  [ "$(sb_cloud)" = "cloud-syncing 2000+" ]
  # Only the first line counts.
  printf 'synced\nproblem\n' > "$SB_CLOUD"
  [ "$(sb_cloud)" = cloud-synced ]
  # Anything else is no state: grey.
  local bad
  for bad in "" "syncing" "syncing 0" "syncing x" "syncing 3; rm -rf y" "syncing 12345678" "SYNCED" "synced now" "problem 2" "syncing  3" "syncing 03"; do
    printf '%s\n' "$bad" > "$SB_CLOUD"
    [ "$(sb_cloud)" = cloud-off ] || { echo "$bad: $(sb_cloud)"; false; }
  done
  # Unreadable: grey.
  echo synced > "$SB_CLOUD"
  chmod 000 "$SB_CLOUD"
  if [ ! -r "$SB_CLOUD" ]; then [ "$(sb_cloud)" = cloud-off ]; fi
  chmod 600 "$SB_CLOUD"
}

@test "sb_cloud: the file is Grove Keys', beside the theme state" {
  local lib="$GROVE_ROOT/config/sketchybar/lib.sh"
  [ "$(env -i HOME=/Users/someone /bin/bash -c '. "$1"; echo "$SB_CLOUD"' _ "$lib")" = /Users/someone/.local/state/grove/cloud ]
  [ "$(env -i HOME=/Users/someone GROVE_STATE=/tmp/state /bin/bash -c '. "$1"; echo "$SB_CLOUD"' _ "$lib")" = /tmp/state/cloud ]
}

@test "sb_tray: the count for the bar from the line Grove Keys keeps; nothing at 0, without the file or with anything else" {
  SB_TRAY="$BATS_TEST_TMPDIR/tray"
  # No file: Grove Keys isn't running (or can't see the menu bar).
  [ "$(sb_tray)" = "" ]
  echo 1 > "$SB_TRAY"
  [ "$(sb_tray)" = 1 ]
  echo 7 > "$SB_TRAY"
  [ "$(sb_tray)" = 7 ]
  echo 99 > "$SB_TRAY"
  [ "$(sb_tray)" = 99 ]
  # Past what the fixed width holds.
  echo 100 > "$SB_TRAY"
  [ "$(sb_tray)" = 99+ ]
  echo 123456 > "$SB_TRAY"
  [ "$(sb_tray)" = 99+ ]
  # Only the first line counts.
  printf '4\n9\n' > "$SB_TRAY"
  [ "$(sb_tray)" = 4 ]
  # 0, and anything else, is no count.
  local bad
  for bad in 0 "" x "-2" "3; rm -rf y" "03" " 3" "3 " "3x" "1e3" "1234567890123"; do
    printf '%s\n' "$bad" > "$SB_TRAY"
    [ "$(sb_tray)" = "" ] || { echo "$bad: $(sb_tray)"; false; }
  done
  # Unreadable: no count.
  echo 5 > "$SB_TRAY"
  chmod 000 "$SB_TRAY"
  if [ ! -r "$SB_TRAY" ]; then [ "$(sb_tray)" = "" ]; fi
  chmod 600 "$SB_TRAY"
}

@test "sb_tray: the file is Grove Keys', beside the theme state" {
  local lib="$GROVE_ROOT/config/sketchybar/lib.sh"
  [ "$(env -i HOME=/Users/someone /bin/bash -c '. "$1"; echo "$SB_TRAY"' _ "$lib")" = /Users/someone/.local/state/grove/tray ]
  [ "$(env -i HOME=/Users/someone GROVE_STATE=/tmp/state /bin/bash -c '. "$1"; echo "$SB_TRAY"' _ "$lib")" = /tmp/state/tray ]
}

@test "sb_vpn_icon: scutil's first line as the VPN icon: on, connecting, or off for anything else" {
  [ "$(echo Connected | sb_vpn_icon)" = vpn-on ]
  [ "$(printf 'Connected\nExtended Status <dictionary> {\n  Status : 2\n}\n' | sb_vpn_icon)" = vpn-on ]
  [ "$(echo Connecting | sb_vpn_icon)" = vpn-connecting ]
  [ "$(echo Disconnecting | sb_vpn_icon)" = vpn-connecting ]
  [ "$(echo Disconnected | sb_vpn_icon)" = vpn-off ]
  [ "$(echo "No service" | sb_vpn_icon)" = vpn-off ]
  [ "$(printf '' | sb_vpn_icon)" = vpn-off ]
  [ "$(echo Invalid | sb_vpn_icon)" = vpn-off ]
  [ "$(echo connected | sb_vpn_icon)" = vpn-off ]
  # Only the first line counts.
  [ "$(printf 'Disconnected\nConnected\n' | sb_vpn_icon)" = vpn-off ]
  # Spaces and tabs around the word are trimmed, as LabVPNStatus.parse does.
  [ "$(printf '  Connected\t \n' | sb_vpn_icon)" = vpn-on ]
  [ "$(printf '\tConnecting \n' | sb_vpn_icon)" = vpn-connecting ]
}

@test "sb_panel_close: sends Grove Keys the close link, in the background; nothing is run when none is open" {
  SB_PANEL="$BATS_TEST_TMPDIR/bar-panel"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$BATS_TEST_TMPDIR/opens" > "$BATS_TEST_TMPDIR/bin/open"
  chmod +x "$BATS_TEST_TMPDIR/bin/open"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  sb_panel_close
  [ ! -e "$BATS_TEST_TMPDIR/opens" ]
  echo pill.clock > "$SB_PANEL"
  sb_panel_close
  [ "$(cat "$BATS_TEST_TMPDIR/opens")" = "-g grovekeys://panel/close" ]
  # The file is Grove Keys' to remove: the bar only reads it.
  [ -e "$SB_PANEL" ]
}

@test "sb_workspaces: the numbers in use, space-separated" {
  [ "$(sb_workspaces < "$FX/workspaces.txt")" = "1 3 5" ]
  [ "$(sb_workspaces < "$FX/workspaces-none.txt")" = "" ]
}

@test "sb_ws_apps: each app once per workspace, numbered slots, six at most" {
  local out
  out="$(printf '1|com.google.Chrome|50\n1 | com.mitchellh.ghostty | 27\n1|com.google.Chrome|51\n2|com.google.Chrome|52\nx|bad|1\n1||9\n' | sb_ws_apps)"
  [ "$out" = "1 1 com.google.Chrome 50
1 2 com.mitchellh.ghostty 27
2 1 com.google.Chrome 52" ]
  out="$(for i in 1 2 3 4 5 6 7 8; do echo "3|app.n$i|$i"; done | sb_ws_apps | wc -l | tr -d ' ')"
  [ "$out" = 6 ]
}

@test "sb_pct: a whole number gets %, anything else is —" {
  [ "$(sb_pct 52)" = "52%" ]
  [ "$(sb_pct —)" = "—" ]
  [ "$(sb_pct "")" = "—" ]
}

@test "sb_timeout: a command that hangs is stopped after the limit" {
  local start=$SECONDS
  run sb_timeout 1 /bin/sleep 5
  [ "$status" -ne 0 ]
  [ $((SECONDS - start)) -lt 4 ]
  [ "$(sb_timeout 2 /bin/echo ok)" = ok ]
}

@test "lib.sh passes shellcheck" {
  command -v shellcheck >/dev/null || skip "no shellcheck"
  shellcheck "$GROVE_ROOT/config/sketchybar/lib.sh"
}
