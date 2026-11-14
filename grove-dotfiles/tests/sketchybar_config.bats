#!/usr/bin/env bats
# config/sketchybar: sketchybarrc and its plugins. Each plugin runs under an
# empty environment (as SketchyBar starts it), with faked data commands on
# SB_PATH and a fake sketchybar that records its arguments. The bar they
# describe: groups of items in orange-outlined pills, symbol icons, and a click
# on a pill sending Grove Keys the link of its panel (the bar has no popups).
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
  # Links are recorded, never opened.
  OPENS="$BATS_TEST_TMPDIR/open-calls"
  fake open 'printf "%s\n" "$*" >> "'"$OPENS"'"'
  # Where Grove Keys names the open panel's pill.
  PANEL="$GROVE_STATE/bar-panel"
  mkdir -p "$GROVE_STATE"
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

# click ITEM: run ITEM's click_script as sketchybarrc set it.
click() {
  local script
  script="$(calls | sed -n "s/.*--set $1 .*click_script=\\(open [^ ]* *[^ ]*\\).*/\\1/p" | tail -1)"
  [ -n "$script" ] || { echo "no click_script for $1"; return 1; }
  run env -i HOME="$HOME" PATH="$FAKES:/usr/bin:/bin" /bin/bash -c "$script"
}

opens() { cat "$OPENS" 2>/dev/null; }
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
    for n in BG0 BG1 FG GREY2 BORDER ON_ACCENT HOVER_FILL MUTED GREEN AQUA BLUE ORANGE YELLOW RED; do
      grep -qE "^export $n=0xff[0-9A-F]{6}\$" "$out" || { echo "$s $n"; false; }
    done
    # No fill is the one colour that isn't the palette's; the icon set follows the appearance.
    grep -qx 'export TRANSPARENT=0x00000000' "$out" || { echo "$s TRANSPARENT"; false; }
    grep -qx "export ICON_SET=${s%%-*}" "$out" || { echo "$s ICON_SET"; false; }
    grep -q "^export PINE_ICON=\"\$CONFIG_DIR/icons/pine-${s%%-*}.png\"\$" "$out"
  done
}

# argb SCHEME NAME: the palette's colour as colors.sh writes it (0xffRRGGBB).
argb() {
  local hex
  hex="$(sed -n "s/^$2 *= *#\\([0-9A-Fa-f]\\{6\\}\\)\$/\\1/p" "$GROVE_ROOT/theme/everforest-$1" | tr '[:lower:]' '[:upper:]')"
  [ -n "$hex" ] && echo "0xff$hex"
}

@test "sketchybar: lines take the border role, text on the green fill the on_accent role" {
  local s c out
  for s in $(gt_schemes); do
    c="${s#*-}"
    out="$BATS_TEST_TMPDIR/roles-$s.sh"
    gt_render_file "$s" "$GROVE_ROOT/theme" "$SB/colors.sh.tmpl" "$out"
    if [ "${s%%-*}" = dark ]; then
      # The dark schemes keep the colours the bar always had.
      grep -qx "export BORDER=$(argb "$s" bg3)" "$out" || { echo "$s BORDER"; false; }
      grep -qx "export ON_ACCENT=$(argb "$s" bg0)" "$out" || { echo "$s ON_ACCENT"; false; }
    else
      # Light: bg5 for lines (bg3 can't be seen on bg0), the dark sibling's bg0 as ink.
      grep -qx "export BORDER=$(argb "$s" bg5)" "$out" || { echo "$s BORDER"; false; }
      grep -qx "export ON_ACCENT=$(argb "dark-$c" bg0)" "$out" || { echo "$s ON_ACCENT"; false; }
      ! grep -qx "export BORDER=$(argb "$s" bg3)" "$out" || { echo "$s BORDER is bg3"; false; }
      ! grep -qx "export ON_ACCENT=$(argb "$s" bg0)" "$out" || { echo "$s ON_ACCENT is bg0"; false; }
    fi
    # bg3 only drew lines: nothing else needs it.
    ! grep -q '^export BG3=' "$out" || { echo "$s BG3"; false; }
  done
  # Outside comments, BG3 is only the fallback for an older colors.sh.
  ! grep -nE '^[^#]*BG3' "$SB/sketchybarrc" "$SB"/plugins/*.sh | grep -v 'BORDER:-'
}

@test "sketchybar: the pine icon exists for dark and light" {
  [ -s "$SB/icons/pine-dark.png" ] && [ -s "$SB/icons/pine-light.png" ]
}

# icon_names: every symbol icon a plugin or sketchybarrc can name.
icon_names() {
  local i
  echo wifi-off eth vpn vol-mute cpu mem bt-off bt-on bt-connected vpn-off vpn-connecting vpn-on
  echo cloud-checking cloud-synced cloud-syncing cloud-problem cloud-off
  for i in 1 2 3; do echo "wifi-$i"; done
  for i in 0 1 2 3 4 5 6 7 8 9 10; do echo "vol-$i bolt-$i"; done
  for i in 0 1 2; do echo "bolt-low-$i"; done
}

@test "icons: every symbol the bar can name exists in the dark and the light set, and nothing else does" {
  local name set want have
  for name in $(icon_names); do
    for set in dark light; do
      [ -s "$SB/icons/$name-$set.png" ] || { echo "$name-$set"; false; }
    done
  done
  want="$(for name in $(icon_names) pine; do echo "$name-dark.png"; echo "$name-light.png"; done | sort)"
  have="$(cd "$SB/icons" && ls -- *.png | sort)"
  [ "$want" = "$have" ] || { diff <(echo "$want") <(echo "$have"); false; }
}

@test "icons: make.swift draws the same names" {
  local gen="$SB/icons/make.swift" name file drawn
  # Each family is written once, its level and the set filled in.
  for name in $(icon_names); do
    case "$name" in
      wifi-[0-9]) file='wifi-\(level)-\(appearance).png' ;;
      vol-[0-9]*) file='vol-\(step)-\(appearance).png' ;;
      bolt-low-[0-9]) file='bolt-low-\(step)-\(appearance).png' ;;
      bolt-[0-9]*) file='bolt-\(step)-\(appearance).png' ;;
      *) file="$name"'-\(appearance).png' ;;
    esac
    grep -qF "to: \"$file\"" "$gen" || { echo "$name"; false; }
  done
  # And nothing the bar doesn't use: twenty-one families.
  drawn="$(grep -oE 'to: "[a-z-]+' "$gen" | sed -e 's/to: "//' -e 's/-$//' | LC_ALL=C sort -u | tr '\n' ' ')"
  [ "$drawn" = "bolt bolt-low bt-connected bt-off bt-on cloud-checking cloud-off cloud-problem cloud-synced cloud-syncing cpu eth mem vol vol-mute vpn vpn-connecting vpn-off vpn-on wifi wifi-off " ] || { echo "$drawn"; false; }
  # The levels it loops over are the ones the plugins ask for.
  grep -q 'for step in 0...10' "$gen"
  grep -q 'if step <= 2' "$gen"
  grep -q '\[(1, 0.2), (2, 0.5), (3, 1.0)\]' "$gen"
}

# rc: run sketchybarrc against the fake sketchybar (one recorded line per call).
rc() {
  run env -i HOME="$HOME" TMPDIR="$BATS_TEST_TMPDIR" CONFIG_DIR="$CFG" SB_PATH="$FAKES:/usr/bin:/bin" /bin/bash "$CFG/sketchybarrc"
}

@test "sketchybar: no Grove Keys glyph on the right (it lives in the pine's menu)" {
  rc
  ! calls | grep -qE -- '--add item keys '
}

@test "sketchybar: the items are added left and right in order, gaps between the groups" {
  local left right
  rc
  [ "$status" -eq 0 ]
  left="$(calls | grep -oE -- '--add item [a-z_.0-9]+ left' | awk '{print $3}' | tr '\n' ' ')"
  right="$(calls | grep -oE -- '--add item [a-z_.0-9]+ right' | awk '{print $3}' | tr '\n' ' ')"
  local want="gap.l0 grove gap.l1 " n
  for n in 1 2 3 4 5 6 7 8 9; do want+="ws.$n ws.$n.1 ws.$n.2 ws.$n.3 ws.$n.4 ws.$n.5 ws.$n.6 ws.$n.end gap.ws.$n "; done
  [ "$left" = "${want}front_app " ] || { echo "$left"; false; }
  # The first added is the rightmost: left to right, CPU and memory, the
  # cloud, the grove-lab VPN, Wi-Fi and Bluetooth, sound, power, the clock.
  [ "$right" = "gap.r0 clock gap.r1 battery gap.r2 volume gap.r3 bt wifi gap.r4 vpn.lab gap.r5 cloud gap.r6 mem cpu " ] || { echo "$right"; false; }
  [ "$(printf '%s' "$right" | tr ' ' '\n' | grep -v '^gap' | tr '\n' ' ')" = "clock battery volume bt wifi vpn.lab cloud mem cpu " ]
  calls | grep -q -- '--add event aerospace_workspace_change'
  calls | grep -q -- '--subscribe ws.1 aerospace_workspace_change'
  # A gap is empty room of a fixed width.
  calls | grep -qx -- '--add item gap.r1 right --set gap.r1 width=6 icon.drawing=off label.drawing=off padding_left=0 padding_right=0'
  calls | grep -qx -- '--add item gap.l1 left --set gap.l1 width=8 icon.drawing=off label.drawing=off padding_left=0 padding_right=0'
}

@test "sketchybar: no separators and no bar bracket" {
  rc
  ! calls | grep -qE -- '--add (item|bracket) (sep\.|bar( |$))'
  ! calls | grep -q -- '│'
  ! grep -q -- '│' "$SB/sketchybarrc"
  # The app's name follows the last workspace's gap, text alone.
  calls | grep -q -- '--set front_app .*icon.drawing=off'
}

# pills: "NAME MEMBER…" for each bracket sketchybarrc adds.
pills() {
  calls | sed -n 's/^--add bracket \(.*\) --set .*/\1/p'
}

@test "pills: every group of items sits in one, an orange outline with no fill" {
  local n want line name members item count
  rc
  [ "$status" -eq 0 ]
  want="pill.grove grove"$'\n'
  for n in 1 2 3 4 5 6 7 8 9; do want+="pill.ws.$n ws.$n ws.$n.1 ws.$n.2 ws.$n.3 ws.$n.4 ws.$n.5 ws.$n.6 ws.$n.end"$'\n'; done
  want+="pill.sys cpu mem"$'\n'"pill.cloud cloud"$'\n'"pill.vpn vpn.lab"$'\n'"pill.wifi wifi bt"$'\n'"pill.volume volume"$'\n'"pill.battery battery"$'\n'"pill.clock clock"
  [ "$(pills)" = "$want" ] || { pills; false; }
  . "$CFG/colors.sh"
  [ "$TRANSPARENT" = 0x00000000 ]
  while read -r name members; do
    calls | grep -qx -- "--add bracket $name $members --set $name background.color=$TRANSPARENT background.height=24 background.corner_radius=12 background.border_width=1 background.border_color=$ORANGE background.drawing=on" || { echo "$name"; false; }
  done <<< "$(pills)"
  # Every item drawn on the bar is in exactly one pill; the app's name and the
  # gaps are in none.
  for item in $(calls | grep -oE -- '--add item [a-z_.0-9]+ (left|right)' | awk '{print $3}'); do
    count="$(pills | cut -d ' ' -f 2- | tr ' ' '\n' | grep -cx -- "$item" || true)"
    case "$item" in
      gap.* | front_app) [ "$count" -eq 0 ] || { echo "$item in a pill"; false; } ;;
      *) [ "$count" -eq 1 ] || { echo "$item in $count pills"; false; } ;;
    esac
  done
}

@test "pills: the outline is the scheme's orange in a light scheme too" {
  gt_render_file light-medium "$GROVE_ROOT/theme" "$SB/colors.sh.tmpl" "$CFG/colors.sh"
  rc
  calls | grep -qE -- "--set pill.sys background.color=0x00000000 .*background.border_color=$(argb light-medium orange) "
  calls | grep -qE -- "--set pill.ws.3 background.color=0x00000000 .*background.border_color=$(argb light-medium orange) "
}

@test "pills: a workspace's pill ends with 4 pt of room and is followed by a gap, both hidden until it's in use" {
  rc
  local n
  for n in 1 2 3 4 5 6 7 8 9; do
    calls | grep -qx -- "--add item ws.$n.end left --set ws.$n.end width=4 icon.drawing=off label.drawing=off padding_left=0 padding_right=0" || { echo "ws.$n.end"; false; }
    calls | grep -qx -- "--add item gap.ws.$n left --set gap.ws.$n width=6 icon.drawing=off label.drawing=off padding_left=0 padding_right=0" || { echo "gap.ws.$n"; false; }
    calls | grep -qx -- "--set ws.$n.end drawing=off --set gap.ws.$n drawing=off" || { echo "ws.$n hidden"; false; }
  done
}

@test "sketchybar: values have fixed widths, so the pills never resize" {
  rc
  local pair item width
  # JetBrains Mono 13 is 7.8 pt a character: each width fits the item's longest value.
  for pair in cpu:32 mem:32 cloud:39 clock:134; do
    item="${pair%%:*}"; width="${pair#*:}"
    calls | grep -qE -- "--set $item .*label.width=$width( |\$)" || { echo "$item"; false; }
  done
  for item in cpu mem; do
    calls | grep -qE -- "--set $item .*label.align=right" || { echo "$item align"; false; }
  done
  # The cloud's count, "2000+" at most, sits beside its icon, hidden until
  # there is one (cloud.sh): the pill is still while the count changes.
  calls | grep -qE -- "--set cloud .*label.drawing=off( |\$)"
  # The icons are images in a 22 pt slot, whatever the state; five items are an icon alone
  # (battery, wifi, bt, vpn.lab, volume).
  for item in cpu mem cloud battery wifi bt vpn.lab volume; do
    calls | grep -qE -- "--set $item icon.background.image=[^ ]+ icon.background.image.scale=0.5 icon.background.drawing=on icon.width=22 icon.padding_left=0 icon.padding_right=0\$" || { echo "$item icon"; false; }
  done
  for item in battery wifi bt vpn.lab volume; do
    calls | grep -qE -- "--set $item label.drawing=off " || { echo "$item label"; false; }
  done
}

# prop ITEM KEY DEFAULT: the last value sketchybarrc gave ITEM's KEY.
prop() {
  local v
  v="$(calls | awk -v item="$1" -v key="$2" '{
    n = split(" " $0, seg, " --")
    for (i = 1; i <= n; i++) {
      m = split(seg[i], w, " ")
      if (w[1] != "set" || w[2] != item) continue
      for (j = 3; j <= m; j++) if (index(w[j], key "=") == 1) v = substr(w[j], length(key) + 2)
    }
  } END { print v }')"
  echo "${v:-$3}"
}

@test "sketchybar: the right side's pills fit beside the notch" {
  rc
  # An item is as wide as its paddings, its icon slot and its label slot
  # (checked against `sketchybar --query <item>` bounding rects on the live
  # bar, where the right side measured 434 pt with the old ends, 4 + the
  # bar's 8; the end is now one 5 pt gap and no bar padding: 427; Bluetooth
  # beside Wi-Fi, the two padded as CPU and memory are: 32 more, 459; the
  # VPN's pill, an icon padded as the volume's, and its gap: 44 more, 503;
  # the cloud's, the same with its count hidden: 44 more, 547; with the
  # count, its 39 pt label, 586).
  local item total=0 w
  [ "$(prop cpu padding_right 5)" = 5 ]
  for item in $(calls | grep -oE -- '--add item [a-z_.0-9]+ right' | awk '{print $3}'); do
    [ "$(prop "$item" drawing on)" = on ] || continue
    w="$(prop "$item" width "")"
    if [ -z "$w" ]; then
      w=$(($(prop "$item" padding_left 5) + $(prop "$item" padding_right 5)))
      [ "$(prop "$item" icon.drawing on)" = off ] || w=$((w + $(prop "$item" icon.width 0)))
      [ "$(prop "$item" label.drawing on)" = off ] || w=$((w + $(prop "$item" label.width 0)))
    fi
    total=$((total + w))
  done
  [ "$total" -eq 547 ] || { echo "$total"; false; }
  [ $((total + 39)) -le 860 ]
  # The built-in screen is 1920 pt wide with a ~200 pt notch in the middle:
  # the right side has ~860 pt.
  [ "$total" -le 860 ]
}

@test "sketchybar: the Grove tree is the item's icon image, so its background can show hover" {
  rc
  calls | grep -qE -- '--set grove .*icon.background.image=.*/icons/pine-dark.png'
}

@test "sketchybar: the pine button is 44 pt wide, the tree centred in it" {
  rc
  calls | grep -qE -- '--set grove .*icon.width=18 .*width=44 align=center '
}

@test "sketchybar: clickable items subscribe to hover; only the app's name, in no pill, has a fill of its own" {
  rc
  local item
  for item in grove front_app clock volume wifi bt vpn.lab cloud battery cpu mem; do
    calls | grep -qE -- "--subscribe $item .*mouse.entered mouse.exited" || { echo "$item"; false; }
    calls | grep -qE -- "--set $item .*script=[^ ]*/plugins/[a-z_]+\\.sh" || { echo "$item script"; false; }
  done
  # An item's own background would be drawn over its pill's outline: the pill
  # itself is what fills (sb_hover).
  for item in grove clock wifi bt vpn.lab cloud battery cpu mem volume; do
    ! calls | grep -qE -- "--set $item (.* )?background\\.(height|corner_radius|drawing|color)=" || { echo "$item has a background"; false; }
  done
  calls | grep -qE -- "--set front_app .*background.height=24 background.corner_radius=12 background.drawing=off"
  # Memory has no plugin of its own (cpu.sh fills it): hover.sh lights it.
  calls | grep -qE -- '--set mem .*script=[^ ]*/plugins/hover.sh '
}

# hover ITEM EVENT: the pointer entering or leaving ITEM, as its plugin gets it.
hover() {
  local script
  case "$1" in grove | mem) script=hover ;; bt) script=bluetooth ;; vpn.lab) script=vpn ;; *) script="$1" ;; esac
  : > "$CALLS"
  run env -i HOME="$HOME" TMPDIR="$BATS_TEST_TMPDIR" CONFIG_DIR="$CFG" NAME="$1" SENDER="$2" \
    SB_PATH="$FAKES:/usr/bin:/bin" SKETCHYBAR_BIN="$FAKES/sketchybar" GROVE_STATE="$GROVE_STATE" \
    /bin/bash "$CFG/plugins/$script.sh"
}

@test "hover: the item's pill fills with the hover colour (bg1 in dark, bg3 in light) and clears when the pointer leaves" {
  local s fill pair item pill
  for s in dark-medium light-medium; do
    gt_render_file "$s" "$GROVE_ROOT/theme" "$SB/colors.sh.tmpl" "$CFG/colors.sh"
    if [ "$s" = dark-medium ]; then fill="$(argb "$s" bg1)"; else fill="$(argb "$s" bg3)"; fi
    # CPU and memory share a pill: either lights the whole of it.
    for pair in grove:pill.grove clock:pill.clock volume:pill.volume wifi:pill.wifi bt:pill.wifi vpn.lab:pill.vpn cloud:pill.cloud battery:pill.battery cpu:pill.sys mem:pill.sys; do
      item="${pair%%:*}"; pill="${pair#*:}"
      hover "$item" mouse.entered
      [ "$status" -eq 0 ]
      # Only the pill's fill changes: its orange outline stays, and the item gets no background over it.
      [ "$(calls)" = "--set $pill background.color=$fill" ] || { echo "$s $item"; calls; false; }
      hover "$item" mouse.exited
      [ "$(calls)" = "--set $pill background.color=0x00000000" ] || { echo "$s $item"; calls; false; }
    done
  done
}

@test "hover: the app's name is in no pill, it lights a fill of its own" {
  . "$CFG/colors.sh"
  hover front_app mouse.entered
  [ "$(calls)" = "--set front_app background.drawing=on background.color=$BG1" ]
  hover front_app mouse.exited
  [ "$(calls)" = "--set front_app background.drawing=off" ]
}

@test "hover: with a colors.sh from before the pills, a pill clears to bg0 without its alpha" {
  grep -vE '^export (TRANSPARENT|HOVER_FILL)=' "$CFG/colors.sh" > "$CFG/colors.sh.old"
  mv "$CFG/colors.sh.old" "$CFG/colors.sh"
  hover clock mouse.entered
  [ "$(calls)" = "--set pill.clock background.color=$(argb dark-medium bg1)" ]
  hover clock mouse.exited
  [ "$(calls)" = "--set pill.clock background.color=0x00$(argb dark-medium bg0 | cut -c 5-)" ]
}

@test "hover: one helper in lib.sh, called only by the plugins of items that subscribe to the pointer" {
  local f
  ! grep -n 'mouse\.entered' "$SB"/plugins/*.sh
  for f in hover front_app clock volume wifi bluetooth vpn cloud battery cpu; do
    grep -qx 'sb_hover && exit 0' "$SB/plugins/$f.sh" || { echo "$f"; false; }
  done
  ! grep -q 'sb_hover' "$SB/plugins/workspaces.sh"
  # A hover does nothing else: no readings, no other call.
  fake pmset 'echo called >> "'"$BATS_TEST_TMPDIR"'/reads"'
  fake iostat 'echo called >> "'"$BATS_TEST_TMPDIR"'/reads"'
  fake osascript 'echo called >> "'"$BATS_TEST_TMPDIR"'/reads"'
  hover battery mouse.entered
  hover cpu mouse.entered
  [ "$(ncalls)" -eq 1 ]
  hover volume mouse.entered
  [ "$(ncalls)" -eq 1 ]
  # Bluetooth's hover lights the pill and sets no icon.
  echo connected > "$GROVE_STATE/bluetooth"
  hover bt mouse.entered
  [ "$status" -eq 0 ]
  [ "$(calls)" = "--set pill.wifi background.color=$(argb dark-medium bg1)" ]
  # The VPN's hover asks scutil nothing.
  fake scutil 'echo called >> "'"$BATS_TEST_TMPDIR"'/reads"'
  hover vpn.lab mouse.entered
  [ "$status" -eq 0 ]
  [ "$(calls)" = "--set pill.vpn background.color=$(argb dark-medium bg1)" ]
  # The cloud's hover lights the pill and sets no icon.
  echo "syncing 4" > "$GROVE_STATE/cloud"
  hover cloud mouse.entered
  [ "$status" -eq 0 ]
  [ "$(calls)" = "--set pill.cloud background.color=$(argb dark-medium bg1)" ]
  [ ! -e "$BATS_TEST_TMPDIR/reads" ]
  [ -z "$(opens)" ]
}

@test "open pill: the pill of the open panel stays filled when the pointer leaves it; the others clear as ever" {
  local fill
  fill="$(argb dark-medium bg1)"
  # Grove Keys names the open panel's pill in the state folder.
  echo pill.clock > "$PANEL"
  hover clock mouse.entered
  [ "$(calls)" = "--set pill.clock background.color=$fill" ]
  hover clock mouse.exited
  [ "$(ncalls)" -eq 0 ] || { calls; false; }
  hover wifi mouse.exited
  [ "$(calls)" = "--set pill.wifi background.color=0x00000000" ]
  # CPU and memory share the pill and the panel.
  echo pill.sys > "$PANEL"
  hover mem mouse.exited
  [ "$(ncalls)" -eq 0 ]
  hover cpu mouse.exited
  [ "$(ncalls)" -eq 0 ]
  hover clock mouse.exited
  [ "$(calls)" = "--set pill.clock background.color=0x00000000" ]
  # Closed (the file is gone): the pill clears again.
  rm "$PANEL"
  hover cpu mouse.exited
  [ "$(calls)" = "--set pill.sys background.color=0x00000000" ]
  # Something that isn't a pill's name is no open panel.
  echo 'pill.clock; rm -rf x' > "$PANEL"
  hover clock mouse.exited
  [ "$(calls)" = "--set pill.clock background.color=0x00000000" ]
}

@test "open pill: a reload fills the open panel's pill again, and no pill when none is open" {
  rc
  [ "$status" -eq 0 ]
  ! calls | grep -qE -- "background.color=$(argb dark-medium bg1)"
  : > "$CALLS"
  echo pill.battery > "$PANEL"
  run env -i HOME="$HOME" TMPDIR="$BATS_TEST_TMPDIR" CONFIG_DIR="$CFG" SB_PATH="$FAKES:/usr/bin:/bin" \
    GROVE_STATE="$GROVE_STATE" /bin/bash "$CFG/sketchybarrc"
  [ "$status" -eq 0 ]
  # After its bracket is added (the last call before the update).
  [ "$(calls | tail -2 | head -1)" = "--set pill.battery background.color=$(argb dark-medium bg1)" ] || { calls | tail -3; false; }
  [ "$(calls | tail -1)" = "--update" ]
  # The Wi-Fi and Bluetooth dropdown open: its pill, Bluetooth in it too.
  : > "$CALLS"
  echo pill.wifi > "$PANEL"
  run env -i HOME="$HOME" TMPDIR="$BATS_TEST_TMPDIR" CONFIG_DIR="$CFG" SB_PATH="$FAKES:/usr/bin:/bin" \
    GROVE_STATE="$GROVE_STATE" /bin/bash "$CFG/sketchybarrc"
  [ "$(calls | tail -2 | head -1)" = "--set pill.wifi background.color=$(argb dark-medium bg1)" ] || { calls | tail -3; false; }
  calls | grep -q -- "--add bracket pill.wifi wifi bt --set"
  # The VPN's dropdown open: its own pill.
  : > "$CALLS"
  echo pill.vpn > "$PANEL"
  run env -i HOME="$HOME" TMPDIR="$BATS_TEST_TMPDIR" CONFIG_DIR="$CFG" SB_PATH="$FAKES:/usr/bin:/bin" \
    GROVE_STATE="$GROVE_STATE" /bin/bash "$CFG/sketchybarrc"
  [ "$status" -eq 0 ]
  [ "$(calls | tail -2 | head -1)" = "--set pill.vpn background.color=$(argb dark-medium bg1)" ] || { calls | tail -3; false; }
  calls | grep -q -- "--add bracket pill.vpn vpn.lab --set"
  # The cloud's dropdown open: its own pill.
  : > "$CALLS"
  echo pill.cloud > "$PANEL"
  run env -i HOME="$HOME" TMPDIR="$BATS_TEST_TMPDIR" CONFIG_DIR="$CFG" SB_PATH="$FAKES:/usr/bin:/bin" \
    GROVE_STATE="$GROVE_STATE" /bin/bash "$CFG/sketchybarrc"
  [ "$status" -eq 0 ]
  [ "$(calls | tail -2 | head -1)" = "--set pill.cloud background.color=$(argb dark-medium bg1)" ] || { calls | tail -3; false; }
  calls | grep -q -- "--add bracket pill.cloud cloud --set"
}

@test "sketchybar: the bar is a 48 pt bg0 strip above the menu bar, nothing drawn around it" {
  grep -q -- '--bar height=48 color="\$BG0" topmost=on sticky=on' "$SB/sketchybarrc"
  rc
  . "$CFG/colors.sh"
  calls | grep -qx -- "--bar height=48 color=$BG0 topmost=on sticky=on position=top padding_left=0 padding_right=0 shadow=off"
  # The only brackets are the pills.
  ! calls | grep -E -- '--add bracket' | grep -qvE -- '--add bracket pill\.'
}

# old_colors: a colors.sh rendered before the theme had roles (no BORDER, no ON_ACCENT).
old_colors() {
  gt_render_file dark-medium "$GROVE_ROOT/theme" "$SB/colors.sh.tmpl" "$CFG/colors.sh"
  grep -vE '^export (BORDER|ON_ACCENT)=' "$CFG/colors.sh" > "$CFG/colors.sh.old"
  echo "export BG3=0xff123456" >> "$CFG/colors.sh.old"
  mv "$CFG/colors.sh.old" "$CFG/colors.sh"
}

@test "sketchybar: with a colors.sh from before the roles, the focused number falls back to BG0 and nothing is drawn in its BG3" {
  old_colors
  rc
  [ "$status" -eq 0 ]
  # The bar draws no lines of its own any more (the popups' outlines were the last).
  ! calls | grep -q -- '0xff123456'
  ! calls | grep -qE -- 'color=( |$)'
  : > "$CALLS"
  fake aerospace 'case "$*" in *--focused*) echo 3 ;; *) printf "1\n3\n" ;; esac'
  plugin workspaces
  . "$CFG/colors.sh"
  [[ "$(calls)" == *"--set ws.3 drawing=on background.drawing=on label.color=$BG0 "* ]] || false
}

@test "sketchybar: with a colors.sh from before the pills, no fill is bg0 without its alpha and the icon set follows the pine" {
  local s
  for s in dark-medium light-medium; do
    gt_render_file "$s" "$GROVE_ROOT/theme" "$SB/colors.sh.tmpl" "$CFG/colors.sh"
    grep -vE '^export (TRANSPARENT|ICON_SET)=' "$CFG/colors.sh" > "$CFG/colors.sh.old"
    mv "$CFG/colors.sh.old" "$CFG/colors.sh"
    : > "$CALLS"
    rc
    [ "$status" -eq 0 ]
    ! calls | grep -qE -- 'color=( |$)'
    calls | grep -qE -- "--set pill.clock background.color=0x00$(argb "$s" bg0 | cut -c 5-) " || { echo "$s pill"; false; }
    calls | grep -qE -- "--set wifi icon.background.image=$CFG/icons/wifi-3-${s%%-*}.png " || { echo "$s rc icon"; false; }
    # The plugins pick the same set.
    : > "$CALLS"
    fake osascript 'case "$*" in *muted*) echo false ;; *) echo 33 ;; esac'
    plugin volume INFO=60
    [ "$(calls)" = "--set volume icon.background.image=$CFG/icons/vol-6-${s%%-*}.png" ] || { echo "$s plugin icon"; calls; false; }
  done
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

@test "workspaces: the number on the green pill is in the on_accent colour, the others muted (grey2 in dark, fg in light)" {
  local s
  fake aerospace 'case "$*" in *--focused*) echo 3 ;; *) printf "1\n3\n5\n" ;; esac'
  for s in dark-medium light-medium; do
    gt_render_file "$s" "$GROVE_ROOT/theme" "$SB/colors.sh.tmpl" "$CFG/colors.sh"
    : > "$CALLS"
    plugin workspaces
    [ "$status" -eq 0 ]
    (
      . "$CFG/colors.sh"
      [ "$ON_ACCENT" = "$(argb dark-medium bg0)" ]
      [[ "$(calls)" == *"--set ws.3 drawing=on background.drawing=on label.color=$ON_ACCENT "* ]] || { echo "$s pill"; false; }
      [[ "$(calls)" == *"--set ws.1 drawing=on background.drawing=off label.color=$MUTED "* ]] || { echo "$s muted"; false; }
      if [ "$s" = dark-medium ]; then [ "$MUTED" = "$GREY2" ]; else [ "$MUTED" = "$FG" ]; fi
    )
  done
  # Light: the pill's text is no longer the bar's own background.
  [[ "$(calls)" != *"background.drawing=on label.color=$(argb light-medium bg0)"* ]] || false
  # The pill itself is the scheme's green.
  rc
  calls | grep -qE -- "--set ws.3 .*background.color=$(argb light-medium green) "
}

@test "workspaces: FOCUSED from the AeroSpace trigger wins" {
  fake aerospace 'case "$*" in *--focused*) echo 1 ;; *) printf "1\n3\n" ;; esac'
  plugin workspaces FOCUSED=3
  [[ "$(calls)" == *"--set ws.3 drawing=on background.drawing=on"* ]] || false
  [[ "$(calls)" == *"--set ws.1 drawing=on background.drawing=off"* ]] || false
}

@test "workspaces: each one shows its apps' icons, once per app; its pill's end and the gap after it show with it" {
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
  # With an app shown, the pill ends with its 4 pt of room.
  [[ "$(calls)" == *"--set ws.1.end drawing=on width=4 --set gap.ws.1 drawing=on"* ]] || false
  [[ "$(calls)" == *"--set ws.2.end drawing=on width=4 --set gap.ws.2 drawing=on"* ]] || false
  [[ "$(calls)" == *"--set ws.3 drawing=off --set ws.3.end drawing=off --set gap.ws.3 drawing=off --set ws.3.1 drawing=off"* ]] || false
  # A workspace that empties takes its pill's end and its gap with it.
  : > "$CALLS"
  fake aerospace 'case "$*" in *--focused*) echo 1 ;; *list-windows*) printf "1|com.google.Chrome|50\n" ;; *) printf "1\n" ;; esac'
  plugin workspaces
  [[ "$(calls)" == *"--set ws.2 drawing=off --set ws.2.end drawing=off --set gap.ws.2 drawing=off --set ws.2.1 drawing=off"* ]] || false
}

@test "workspaces: one in use but empty keeps the room of one app icon, so its pill is as wide as one with an app" {
  # 3 is focused and empty (AeroSpace keeps the focused one); 1 has a window.
  fake aerospace 'case "$*" in
    *--focused*) echo 3 ;;
    *list-windows*) printf "1|com.google.Chrome|50\n" ;;
    *) printf "1\n" ;;
  esac'
  plugin workspaces
  [ "$status" -eq 0 ]
  # A 24 pt slot plus the 4 pt of room.
  [[ "$(calls)" == *"--set ws.3 drawing=on background.drawing=on "*"--set ws.3.end drawing=on width=28 --set gap.ws.3 drawing=on --set ws.3.1 drawing=off"* ]] || { calls; false; }
  [[ "$(calls)" == *"--set ws.1.end drawing=on width=4 --set gap.ws.1 drawing=on"* ]] || { calls; false; }
  # It gets an app: back to 4.
  : > "$CALLS"
  fake aerospace 'case "$*" in
    *--focused*) echo 3 ;;
    *list-windows*) printf "1|com.google.Chrome|50\n3|com.mitchellh.ghostty|27\n" ;;
    *) printf "1\n3\n" ;;
  esac'
  plugin workspaces
  [[ "$(calls)" == *"--set ws.3.end drawing=on width=4 --set gap.ws.3 drawing=on"* ]] || { calls; false; }
  # A workspace not in use isn't given a width: it is hidden.
  [[ "$(calls)" == *"--set ws.2 drawing=off --set ws.2.end drawing=off --set gap.ws.2 drawing=off"* ]] || false
}

@test "workspaces: without AeroSpace every workspace is hidden" {
  fake aerospace 'exit 2'
  plugin workspaces
  [ "$status" -eq 0 ]
  [[ "$(calls)" == *"--set ws.1 drawing=off --set ws.1.end drawing=off --set gap.ws.1 drawing=off"* ]] || false
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

@test "cpu and mem: one call sets both, and nothing else" {
  fake iostat 'cat "'"$FX"'/iostat.txt"'
  fake vm_stat 'cat "'"$FX"'/vm_stat.txt"'
  fake sysctl 'echo 25769803776'
  fake osascript 'echo called >> "'"$BATS_TEST_TMPDIR"'/osascript-calls"'
  plugin cpu
  [ "$(ncalls)" -eq 1 ]
  . "$CFG/colors.sh"
  [ "$(calls)" = "--set cpu label=9% label.color=$FG --set mem label=52% label.color=$FG" ] || { calls; false; }
  # The cores, the processes and the charts are the panel's (Grove Keys): nothing measures them here.
  [ ! -e "$BATS_TEST_TMPDIR/osascript-calls" ]
}

@test "cpu and mem: a failing source shows —" {
  fake iostat 'exit 1'
  fake vm_stat 'exit 1'
  fake sysctl 'exit 1'
  plugin cpu
  . "$CFG/colors.sh"
  [ "$(calls)" = "--set cpu label=— label.color=$FG --set mem label=— label.color=$FG" ] || { calls; false; }
}

@test "cpu and mem: yellow above 70%, red above 90%" {
  fake iostat 'printf "      cpu    load average\n us sy id   1m   5m   15m\n 50 30 20  1.00 1.00 1.00\n"'
  fake vm_stat 'cat "'"$FX"'/vm_stat.txt"'
  fake sysctl 'echo 14033844547'
  plugin cpu
  . "$CFG/colors.sh"
  [[ "$(calls)" == "--set cpu label=80% label.color=$YELLOW --set mem label=95% label.color=$RED" ]] || { calls; false; }
}

# battery_icon PMSET_LINE: the icon battery.sh picks for a `pmset -g batt` battery line.
battery_icon() {
  : > "$CALLS"
  fake pmset 'printf "x\n -InternalBattery-0 (id=1)\t%s present: true\n" "'"$1"'"'
  plugin battery
  calls
}

@test "battery: a bolt filled with the charge in tenths, red under 20% when not charging" {
  local s set
  for s in dark-medium light-medium; do
    gt_render_file "$s" "$GROVE_ROOT/theme" "$SB/colors.sh.tmpl" "$CFG/colors.sh"
    set="${s%%-*}"
    : > "$CALLS"
    fake pmset 'cat "'"$FX"'/pmset-charging.txt"'
    plugin battery
    [ "$(calls)" = "--set battery drawing=on icon.background.image=$CFG/icons/bolt-9-$set.png" ] || { calls; false; }
    : > "$CALLS"
    fake pmset 'cat "'"$FX"'/pmset-battery.txt"'
    plugin battery
    [ "$(calls)" = "--set battery drawing=on icon.background.image=$CFG/icons/bolt-10-$set.png" ]
    [ "$(battery_icon "20%; discharging; 1:30 remaining")" = "--set battery drawing=on icon.background.image=$CFG/icons/bolt-2-$set.png" ]
    [ "$(battery_icon "19%; discharging; 1:20 remaining")" = "--set battery drawing=on icon.background.image=$CFG/icons/bolt-low-2-$set.png" ]
    [ "$(battery_icon "9%; discharging; 0:20 remaining")" = "--set battery drawing=on icon.background.image=$CFG/icons/bolt-low-1-$set.png" ]
    [ "$(battery_icon "4%; discharging; (no estimate)")" = "--set battery drawing=on icon.background.image=$CFG/icons/bolt-low-0-$set.png" ]
    # Low but charging: the yellow bolt.
    [ "$(battery_icon "15%; charging; 1:00 remaining")" = "--set battery drawing=on icon.background.image=$CFG/icons/bolt-2-$set.png" ]
    [ "$(battery_icon "4%; AC attached; not charging")" = "--set battery drawing=on icon.background.image=$CFG/icons/bolt-0-$set.png" ]
  done
}

@test "battery: every level names an icon that exists" {
  local level state file
  for level in 0 1 4 5 9 10 14 15 19 20 44 45 94 95 99 100; do
    for state in discharging charging; do
      file="$(battery_icon "$level%; $state; 1:00 remaining" | sed 's/.*icon.background.image=//')"
      [ -s "$file" ] || { echo "$level $state: $file"; false; }
    done
  done
}

@test "battery: hidden without a battery" {
  fake pmset 'cat "'"$FX"'/pmset-none.txt"'
  plugin battery
  [ "$(calls)" = '--set battery drawing=off' ]
}

# battery_fakes: this Mac on its charger, as recorded.
battery_fakes() {
  fake pmset 'case "$*" in *batt*) cat "'"$FX"'/pmset-finishing.txt" ;; *) cat "'"$FX"'/pmset-g.txt" ;; esac'
  fake ioreg 'cat "'"$FX"'/ioreg-battery.txt"'
  fake system_profiler 'cat "'"$FX"'/system_profiler-power.txt"'
}

# wifi_icon RSSI: the icon wifi.sh picks on Wi-Fi with that signal.
wifi_icon() {
  : > "$CALLS"
  fake osascript 'echo "'"$1"'"'
  plugin wifi
  calls
}

@test "connection: an icon alone: the Wi-Fi fan by signal, a cable, a tunnel, or off" {
  local s set
  for s in dark-medium light-medium; do
    gt_render_file "$s" "$GROVE_ROOT/theme" "$SB/colors.sh.tmpl" "$CFG/colors.sh"
    set="${s%%-*}"
    fake route 'printf "  interface: en0\n"'
    fake ipconfig 'cat "'"$FX"'/ipconfig-wifi.txt"'
    [ "$(wifi_icon -52)" = "--set wifi icon.background.image=$CFG/icons/wifi-3-$set.png" ] || { calls; false; }
    [ "$(wifi_icon -66)" = "--set wifi icon.background.image=$CFG/icons/wifi-2-$set.png" ]
    [ "$(wifi_icon -80)" = "--set wifi icon.background.image=$CFG/icons/wifi-1-$set.png" ]
    # A signal that can't be read: the whole fan.
    [ "$(wifi_icon "")" = "--set wifi icon.background.image=$CFG/icons/wifi-3-$set.png" ]
    fake ipconfig 'cat "'"$FX"'/ipconfig-eth.txt"'
    [ "$(wifi_icon -52)" = "--set wifi icon.background.image=$CFG/icons/eth-$set.png" ]
    fake route 'printf "  interface: utun3\n"'
    [ "$(wifi_icon -52)" = "--set wifi icon.background.image=$CFG/icons/vpn-$set.png" ]
    fake route 'exit 1'
    [ "$(wifi_icon -52)" = "--set wifi icon.background.image=$CFG/icons/wifi-off-$set.png" ]
  done
}

@test "connection: the signal is asked of CoreWLAN, and only on Wi-Fi" {
  fake route 'printf "  interface: en0\n"'
  fake ipconfig 'cat "'"$FX"'/ipconfig-wifi.txt"'
  fake osascript 'echo "$*" >> "'"$BATS_TEST_TMPDIR"'/osascript-calls"; echo -70'
  plugin wifi
  grep -q -- '-l JavaScript -e .*CoreWLAN.*rssiValue' "$BATS_TEST_TMPDIR/osascript-calls"
  rm "$BATS_TEST_TMPDIR/osascript-calls"
  fake ipconfig 'cat "'"$FX"'/ipconfig-eth.txt"'
  plugin wifi
  [ ! -e "$BATS_TEST_TMPDIR/osascript-calls" ]
}

# bt_icon [WORD]: the call bluetooth.sh makes with $GROVE_STATE/bluetooth
# holding WORD (no file without one).
bt_icon() {
  : > "$CALLS"
  if [ "$#" -gt 0 ]; then printf '%s\n' "$1" > "$GROVE_STATE/bluetooth"; else rm -f "$GROVE_STATE/bluetooth"; fi
  run env -i HOME="$HOME" TMPDIR="$BATS_TEST_TMPDIR" CONFIG_DIR="$CFG" NAME=bt SENDER=bluetooth_change \
    SB_PATH="$FAKES:/usr/bin:/bin" SKETCHYBAR_BIN="$FAKES/sketchybar" GROVE_STATE="$GROVE_STATE" \
    /bin/bash "$CFG/plugins/bluetooth.sh"
  calls
}

@test "bluetooth: the icon Grove Keys names in the state file; off without one" {
  local s set
  for s in dark-medium light-medium; do
    gt_render_file "$s" "$GROVE_ROOT/theme" "$SB/colors.sh.tmpl" "$CFG/colors.sh"
    set="${s%%-*}"
    [ "$(bt_icon on)" = "--set bt icon.background.image=$CFG/icons/bt-on-$set.png" ] || { calls; false; }
    [ "$(bt_icon connected)" = "--set bt icon.background.image=$CFG/icons/bt-connected-$set.png" ]
    [ "$(bt_icon off)" = "--set bt icon.background.image=$CFG/icons/bt-off-$set.png" ]
    # Grove Keys not running (no file), or anything else in it: off.
    [ "$(bt_icon)" = "--set bt icon.background.image=$CFG/icons/bt-off-$set.png" ]
    [ "$(bt_icon 'connected; rm -rf x')" = "--set bt icon.background.image=$CFG/icons/bt-off-$set.png" ]
    [ "$(bt_icon "")" = "--set bt icon.background.image=$CFG/icons/bt-off-$set.png" ]
  done
}

@test "bluetooth: the bt item sits beside Wi-Fi, redrawn on Grove Keys' bluetooth_change and nothing timed" {
  rc
  calls | grep -qx -- '--add event bluetooth_change'
  calls | grep -qE -- '--subscribe bt bluetooth_change mouse.entered mouse.exited$'
  calls | grep -qE -- '--set bt .*script=[^ ]*/plugins/bluetooth.sh '
  # Grove Keys reads Bluetooth; the bar never polls it.
  ! calls | grep -qE -- '--set bt .*update_freq='
  ! grep -n 'system_profiler\|blueutil' "$SB/plugins/bluetooth.sh"
  # Off until Grove Keys says otherwise.
  calls | grep -qE -- "--set bt icon.background.image=$CFG/icons/bt-off-dark.png "
}

# cloud_set [LINE]: the call cloud.sh makes with $GROVE_STATE/cloud holding
# LINE (no file without one).
cloud_set() {
  : > "$CALLS"
  if [ "$#" -gt 0 ]; then printf '%s\n' "$1" > "$GROVE_STATE/cloud"; else rm -f "$GROVE_STATE/cloud"; fi
  run env -i HOME="$HOME" TMPDIR="$BATS_TEST_TMPDIR" CONFIG_DIR="$CFG" NAME=cloud SENDER=cloud_change \
    SB_PATH="$FAKES:/usr/bin:/bin" SKETCHYBAR_BIN="$FAKES/sketchybar" GROVE_STATE="$GROVE_STATE" \
    /bin/bash "$CFG/plugins/cloud.sh"
  calls
}

@test "cloud: the icon and count for Grove Keys' line; a grey cloud without the file" {
  local s set
  for s in dark-medium light-medium; do
    gt_render_file "$s" "$GROVE_ROOT/theme" "$SB/colors.sh.tmpl" "$CFG/colors.sh"
    set="${s%%-*}"
    [ "$(cloud_set checking)" = "--set cloud icon.background.image=$CFG/icons/cloud-checking-$set.png label= label.drawing=off" ] || { calls; false; }
    [ "$(cloud_set synced)" = "--set cloud icon.background.image=$CFG/icons/cloud-synced-$set.png label= label.drawing=off" ]
    [ "$(cloud_set problem)" = "--set cloud icon.background.image=$CFG/icons/cloud-problem-$set.png label= label.drawing=off" ]
    [ "$(cloud_set "syncing 12")" = "--set cloud icon.background.image=$CFG/icons/cloud-syncing-$set.png label=12 label.drawing=on" ]
    [ "$(cloud_set "syncing 2000+")" = "--set cloud icon.background.image=$CFG/icons/cloud-syncing-$set.png label=2000+ label.drawing=on" ]
    # Grove Keys not running (no file), or anything else in it: grey, no count.
    [ "$(cloud_set)" = "--set cloud icon.background.image=$CFG/icons/cloud-off-$set.png label= label.drawing=off" ]
    [ "$(cloud_set "syncing 3; rm -rf x")" = "--set cloud icon.background.image=$CFG/icons/cloud-off-$set.png label= label.drawing=off" ]
    [ "$(cloud_set "")" = "--set cloud icon.background.image=$CFG/icons/cloud-off-$set.png label= label.drawing=off" ]
  done
}

@test "cloud: the cloud item in its own pill between CPU and memory and the VPN, redrawn on Grove Keys' cloud_change and nothing timed" {
  rc
  calls | grep -qx -- '--add event cloud_change'
  calls | grep -qE -- '--subscribe cloud cloud_change mouse.entered mouse.exited$'
  calls | grep -qE -- '--set cloud .*script=[^ ]*/plugins/cloud.sh '
  calls | grep -qE -- '--set cloud .*click_script=open -g grovekeys://panel/cloud( |$)'
  # Grove Keys follows the files; the bar never polls them or looks at them.
  [ -z "$(calls | grep -E -- '--set cloud .*update_freq=')" ]
  [ -z "$(grep -v '^ *#' "$SB/plugins/cloud.sh" | grep -nE 'CloudStorage|Mobile Documents|brctl|fileproviderctl|(^|[^a-z_])(find|ls|stat|xattr) ')" ]
  # Grey until Grove Keys says otherwise.
  calls | grep -qE -- "--set cloud icon.background.image=$CFG/icons/cloud-off-dark.png "
  # Coloured by meaning: grey checking and off, green synced, yellow syncing, red a problem.
  local gen="$SB/icons/make.swift"
  grep -qF 'to: "cloud-checking-\(appearance).png")' "$gen"
  grep -qE 'draw\("[a-z0-9.]+", color: off, to: "cloud-checking-' "$gen"
  grep -qE 'draw\("[a-z0-9.]+", color: green, to: "cloud-synced-' "$gen"
  grep -qE 'draw\("[a-z0-9.]+", color: yellow, to: "cloud-syncing-' "$gen"
  grep -qE 'draw\("[a-z0-9.]+", color: red, to: "cloud-problem-' "$gen"
  grep -qE 'draw\("[a-z0-9.]+", color: off, to: "cloud-off-' "$gen"
}

# vpn_icon [FIRST_LINE]: the call vpn.sh makes when `scutil --nc status
# "grove-lab"` prints FIRST_LINE (and an extended status after a connected
# one); scutil fails without an argument. "No service" goes to standard
# error with status 1, as scutil does for a missing service.
vpn_icon() {
  : > "$CALLS"
  if [ "${1:-}" = "No service" ]; then
    fake scutil 'printf "%s\n" "$*" >> "'"$BATS_TEST_TMPDIR"'/scutil-calls"; echo "No service" >&2; exit 1'
  elif [ "$#" -gt 0 ]; then
    fake scutil 'printf "%s\n" "$*" >> "'"$BATS_TEST_TMPDIR"'/scutil-calls"; printf "%s\n" "'"$1"'"; [ "'"$1"'" != Connected ] || printf "Extended Status <dictionary> {\n  Status : 2\n}\n"'
  else
    fake scutil 'exit 1'
  fi
  run env -i HOME="$HOME" TMPDIR="$BATS_TEST_TMPDIR" CONFIG_DIR="$CFG" NAME=vpn.lab SENDER="${VPN_SENDER:-routine}" \
    SB_PATH="$FAKES:/usr/bin:/bin" SKETCHYBAR_BIN="$FAKES/sketchybar" GROVE_STATE="$GROVE_STATE" \
    /bin/bash "$CFG/plugins/vpn.sh"
  calls
}

@test "vpn: the shield by the grove-lab service's state: on, connecting, or off (not set up too)" {
  local s set
  for s in dark-medium light-medium; do
    gt_render_file "$s" "$GROVE_ROOT/theme" "$SB/colors.sh.tmpl" "$CFG/colors.sh"
    set="${s%%-*}"
    [ "$(vpn_icon Connected)" = "--set vpn.lab icon.background.image=$CFG/icons/vpn-on-$set.png" ] || { calls; false; }
    [ "$(vpn_icon Connecting)" = "--set vpn.lab icon.background.image=$CFG/icons/vpn-connecting-$set.png" ]
    [ "$(vpn_icon Disconnecting)" = "--set vpn.lab icon.background.image=$CFG/icons/vpn-connecting-$set.png" ]
    [ "$(vpn_icon Disconnected)" = "--set vpn.lab icon.background.image=$CFG/icons/vpn-off-$set.png" ]
    # No service: the pill stays, grey.
    [ "$(vpn_icon "No service")" = "--set vpn.lab icon.background.image=$CFG/icons/vpn-off-$set.png" ]
    [ "$(vpn_icon)" = "--set vpn.lab icon.background.image=$CFG/icons/vpn-off-$set.png" ]
  done
  # It asks for the grove-lab service by name, and only its status.
  [ "$(sort -u "$BATS_TEST_TMPDIR/scutil-calls")" = "--nc status grove-lab" ]
}

@test "vpn: scutil is run through sb_timeout, never started or stopped from the bar" {
  grep -qE '^status="\$\(sb_timeout [0-9]+ scutil --nc status "grove-lab"' "$SB/plugins/vpn.sh"
  # Outside comments, every scutil is behind the timeout.
  [ "$(grep -v '^ *#' "$SB/plugins/vpn.sh" | grep -c 'scutil')" -eq "$(grep -c 'sb_timeout [0-9]* scutil' "$SB/plugins/vpn.sh")" ]
  ! grep -nE 'scutil --nc (start|stop)' "$SB/plugins/vpn.sh" "$SB/sketchybarrc" "$SB/lib.sh"
  # A scutil that hangs is stopped: the plugin still sets the icon, off.
  fake scutil 'exec /bin/sleep 30'
  local started=$SECONDS
  : > "$CALLS"
  run env -i HOME="$HOME" TMPDIR="$BATS_TEST_TMPDIR" CONFIG_DIR="$CFG" NAME=vpn.lab \
    SB_PATH="$FAKES:/usr/bin:/bin" SKETCHYBAR_BIN="$FAKES/sketchybar" GROVE_STATE="$GROVE_STATE" \
    /bin/bash "$CFG/plugins/vpn.sh"
  [ $((SECONDS - started)) -lt 10 ]
  [ "$(calls)" = "--set vpn.lab icon.background.image=$CFG/icons/vpn-off-dark.png" ] || { calls; false; }
}

@test "vpn: the vpn.lab item in its own pill, read every 10 s, on wake and on Grove Keys' vpn_change" {
  rc
  calls | grep -qx -- '--add event vpn_change'
  calls | grep -qE -- '--subscribe vpn.lab vpn_change system_woke mouse.entered mouse.exited$'
  calls | grep -qE -- '--set vpn.lab .*script=[^ ]*/plugins/vpn.sh '
  calls | grep -qE -- '--set vpn.lab .*update_freq=10 '
  calls | grep -qE -- '--set vpn.lab .*click_script=open -g grovekeys://panel/vpn( |$)'
  # Off until the plugin first reads it.
  calls | grep -qE -- "--set vpn.lab icon.background.image=$CFG/icons/vpn-off-dark.png "
  # The Wi-Fi pill's own tunnel icon is untouched.
  grep -qF 'draw("lock.shield", color: blue, to: "vpn-\(appearance).png")' "$SB/icons/make.swift"
}

@test "volume: a speaker filled with the level from INFO in tenths, struck out when muted" {
  local s set
  for s in dark-medium light-medium; do
    gt_render_file "$s" "$GROVE_ROOT/theme" "$SB/colors.sh.tmpl" "$CFG/colors.sh"
    set="${s%%-*}"
    : > "$CALLS"
    fake osascript 'case "$*" in *muted*) echo false ;; *) echo 33 ;; esac'
    plugin volume INFO=60
    [ "$(calls)" = "--set volume icon.background.image=$CFG/icons/vol-6-$set.png" ] || { calls; false; }
    : > "$CALLS"
    plugin volume INFO=0
    [ "$(calls)" = "--set volume icon.background.image=$CFG/icons/vol-0-$set.png" ]
    : > "$CALLS"
    # Anything above silence shows.
    plugin volume INFO=3
    [ "$(calls)" = "--set volume icon.background.image=$CFG/icons/vol-1-$set.png" ]
    : > "$CALLS"
    plugin volume INFO=100
    [ "$(calls)" = "--set volume icon.background.image=$CFG/icons/vol-10-$set.png" ]
    : > "$CALLS"
    fake osascript 'case "$*" in *muted*) echo true ;; *) echo 33 ;; esac'
    plugin volume INFO=60
    [ "$(calls)" = "--set volume icon.background.image=$CFG/icons/vol-mute-$set.png" ]
  done
}

@test "volume: without INFO (a reload, the first run) it reads the current level" {
  fake osascript 'case "$*" in *muted*) echo false ;; *) echo 56 ;; esac'
  plugin volume
  [ "$(calls)" = "--set volume icon.background.image=$CFG/icons/vol-6-dark.png" ]
}

@test "clock: weekday day month, two spaces, hours:minutes" {
  fake date 'echo "Tue 11 Nov  14:32"'
  plugin clock
  [ "$(calls)" = '--set clock label=Tue 11 Nov  14:32' ]
}

@test "clock: under a Portuguese locale the day and month stay English" {
  locale -a | grep -qx 'pt_PT.UTF-8' || skip "no pt_PT.UTF-8 locale"
  plugin clock LC_ALL=pt_PT.UTF-8
  calls | grep -qE -- '^--set clock label=(Mon|Tue|Wed|Thu|Fri|Sat|Sun) [0-9]+ (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)  [0-9]{2}:[0-9]{2}$' || { calls; false; }
}

@test "comments: nothing still describes the separators, the floating bar or the rates on the bar" {
  ! grep -nEi 'separator|floating bar|net\.(down|up)([^a-z]|$)|sep\.' "$SB/sketchybarrc" "$SB/lib.sh" "$SB"/plugins/*.sh "$SB/colors.sh.tmpl"
}

@test "panels: a click on a pill sends Grove Keys the link of its panel, without bringing it forward" {
  rc
  local pair item name
  # CPU and memory share one panel; the volume's is the sound panel; the
  # pine's is the Grove menu.
  # Wi-Fi and Bluetooth share one too: a click on either opens it.
  for pair in grove:grove clock:clock volume:sound wifi:wifi bt:wifi vpn.lab:vpn cloud:cloud battery:battery cpu:system mem:system; do
    item="${pair%%:*}"; name="${pair#*:}"
    calls | grep -qE -- "--set $item .*click_script=open -g grovekeys://panel/$name( |\$)" || { echo "$item"; false; }
    : > "$OPENS"
    click "$item"
    [ "$status" -eq 0 ]
    [ "$(opens)" = "-g grovekeys://panel/$name" ] || { echo "$item: $(opens)"; false; }
  done
}

@test "panels: the bar has no popups, charts or sampler of its own left" {
  rc
  ! calls | grep -qE -- 'popup|--add graph|--push|net\.sample'
  ! calls | grep -qE -- '--add item (cal|net|batt|sys)\.'
  ! grep -nE 'popup\.|sb_popup|SB_POPUP|--push|--add graph' "$SB/sketchybarrc" "$SB/lib.sh" "$SB"/plugins/*.sh
  local f
  for f in popup clock_popup network_popup system_popup battery_popup net_sample; do
    [ ! -e "$SB/plugins/$f.sh" ] || { echo "$f.sh"; false; }
  done
  # Every item still added is on the bar itself.
  ! calls | grep -E -- '--add item [^ ]+ ' | grep -qvE -- '--add item [^ ]+ (left|right) '
}

@test "panels: a workspace change puts the open panel away through Grove Keys; nothing is sent when none is open" {
  fake aerospace 'case "$*" in *--focused*) echo 1 ;; *) printf "1\n" ;; esac'
  # None open: one file test, no link.
  plugin workspaces SENDER=aerospace_workspace_change
  [ "$status" -eq 0 ]
  [ -z "$(opens)" ]
  echo pill.clock > "$PANEL"
  plugin workspaces SENDER=aerospace_workspace_change
  [ "$(opens)" = "-g grovekeys://panel/close" ]
  # The bar still redraws the workspaces, and touches no pill's fill itself.
  [ "$(ncalls)" -eq 2 ]
  [[ "$(calls)" != *"background.color"* ]] || false
  # An app switch is Grove Keys' own to see; a timed refresh closes nothing.
  : > "$OPENS"
  plugin workspaces SENDER=front_app_switched
  plugin workspaces SENDER=routine
  plugin workspaces
  [ -z "$(opens)" ]
}

@test "ends: the pine pill's left outline and the clock pill's right outline are 5 pt from the screen's sides, on the window borders' lines" {
  rc
  # No bar padding: the end gaps are all of it.
  calls | grep -qE -- '--bar .*padding_left=0 padding_right=0( |$)'
  calls | grep -qx -- '--add item gap.l0 left --set gap.l0 width=5 icon.drawing=off label.drawing=off padding_left=0 padding_right=0'
  calls | grep -qx -- '--add item gap.r0 right --set gap.r0 width=5 icon.drawing=off label.drawing=off padding_left=0 padding_right=0'
  # Nothing before the pine or after the clock but that gap, and neither item
  # has padding of its own outside its pill: the pill starts where the gap ends.
  [ "$(calls | grep -oE -- '--add item [a-z_.0-9]+ left' | sed -n 1p)" = "--add item gap.l0 left" ]
  [ "$(calls | grep -oE -- '--add item [a-z_.0-9]+ right' | sed -n 1p)" = "--add item gap.r0 right" ]
  [ "$(prop grove padding_left 5)" = 0 ]
  # The line they sit on: AeroSpace's outer gap less what the border shows
  # outside its window (half its width): 5 pt, a whole point.
  local gap width
  gap="$(sed -n 's/^gaps\.outer\.left = \([0-9]*\)$/\1/p' "$GROVE_ROOT/config/aerospace/aerospace.base.toml")"
  [ "$gap" = "$(sed -n 's/^gaps\.outer\.right = \([0-9]*\)$/\1/p' "$GROVE_ROOT/config/aerospace/aerospace.base.toml")" ]
  width="$(sed -n 's/.* width=\([0-9.]*\) .*/\1/p' "$GROVE_ROOT/config/borders/bordersrc.tmpl")"
  [ "$(awk -v g="$gap" -v w="$width" 'BEGIN { print g - w / 2 }')" = 5 ] || { echo "$gap $width"; false; }
}

@test "sketchybar: the app name opens the app's menus" {
  rc
  calls | grep -qE -- '--set front_app .*click_script=open grovekeys://app-menu'
  calls | grep -qE -- '--subscribe front_app front_app_switched mouse.entered mouse.exited'
}
