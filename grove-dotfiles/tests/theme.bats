#!/usr/bin/env bats
# The Grove palette and the colors every config uses.
# shellcheck disable=SC2016

load helpers

setup() { grove_test_setup; }

PALETTE_REL=theme/everforest-dark-medium

# palette_hexes: every #RRGGBB in the palette file, uppercased, one per line.
palette_hexes() {
  grep -v '^[[:space:]]*#' "$GROVE_ROOT/$PALETTE_REL" | grep -oE '#[0-9A-Fa-f]{6}' | tr '[:lower:]' '[:upper:]' | sort -u
}

# config_hexes FILE...: every #RRGGBB in the files that exist, uppercased.
config_hexes() {
  local f
  for f in "$@"; do [ -f "$f" ] && grep -oE '#[0-9A-Fa-f]{6}' "$f"; done | tr '[:lower:]' '[:upper:]' | sort -u
  return 0
}

# palette_value NAME: the hex for NAME in the palette.
palette_value() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\(#[0-9A-Fa-f]\{6\}\).*/\1/p" "$GROVE_ROOT/$PALETTE_REL" | head -1
}

@test "the palette has every upstream Dark Medium color" {
  local pair name want
  for pair in bg_dim=#232A2E bg0=#2D353B bg1=#343F44 bg2=#3D484D bg3=#475258 bg4=#4F585E \
              bg5=#56635F bg_visual=#543A48 bg_red=#514045 bg_yellow=#4D4C43 bg_green=#425047 \
              bg_blue=#3A515D bg_purple=#4A444E fg=#D3C6AA red=#E67E80 orange=#E69875 \
              yellow=#DBBC7F green=#A7C080 aqua=#83C092 blue=#7FBBB3 purple=#D699B6 \
              grey0=#7A8478 grey1=#859289 grey2=#9DA9A0; do
    name="${pair%%=*}"; want="${pair#*=}"
    [ "$(palette_value "$name")" = "$want" ] || { echo "$name: got '$(palette_value "$name")', want $want"; false; }
  done
}

@test "the palette's Grove additions are only the fill color, the roles and the terminal roles" {
  run sed -n '/^# Grove additions/,$p' "$GROVE_ROOT/$PALETTE_REL"
  [ "$status" -eq 0 ]
  [ -z "$(printf '%s\n' "$output" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | grep -vE '^(fill|border|on_accent|dim|hover|muted|lockup_ink|term([0-9]|1[0-5]))[[:space:]]*=[[:space:]]*#[0-9A-F]{6}$')" ]
}

# scheme_value SCHEME NAME: the hex for NAME in theme/everforest-SCHEME.
scheme_value() {
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\(#[0-9A-Fa-f]\{6\}\).*/\1/p" "$GROVE_ROOT/theme/everforest-$1" | head -1
}

SCHEMES="dark-hard dark-medium dark-soft light-hard light-medium light-soft"

@test "each palette has every upstream color" {
  local scheme name hex
  while read -r scheme name hex; do
    [ "$(scheme_value "$scheme" "$name")" = "$hex" ] || { echo "$scheme $name: got '$(scheme_value "$scheme" "$name")', want $hex"; false; }
  done < "$GROVE_ROOT/tests/fixtures/everforest-upstream.txt"
}

@test "terminal roles follow upstream" {
  local s v black white i
  for s in $SCHEMES; do
    if [[ $s == dark-* ]]; then black=bg3; white=fg; else black=fg; white=bg3; fi
    v() { scheme_value "$s" "$1"; }
    [ "$(v term0)" = "$(v $black)" ] || { echo "$s term0"; false; }
    [ "$(v term7)" = "$(v $white)" ] || { echo "$s term7"; false; }
    i=1
    for n in red green yellow blue purple aqua; do
      [ "$(v term$i)" = "$(v $n)" ] || { echo "$s term$i"; false; }
      i=$((i + 1))
    done
    [ "$(v term8)" = "$(v grey1)" ] || { echo "$s term8"; false; }
    for i in 1 2 3 4 5 6; do
      [ "$(v term$((i + 8)))" = "$(v term$i)" ] || { echo "$s term$((i + 8))"; false; }
    done
    # Bright white: upstream's in the dark schemes; fg in the light ones, where
    # upstream's bg3 can't be read on bg0.
    if [[ $s == dark-* ]]; then white=term7; else white=fg; fi
    [ "$(v term15)" = "$(v $white)" ] || { echo "$s term15"; false; }
  done
}

@test "roles: the dark schemes keep their colours; the light ones pick readable ones" {
  local s c
  for s in $SCHEMES; do
    c="${s#*-}"
    if [[ $s == dark-* ]]; then
      [ "$(scheme_value "$s" border)" = "$(scheme_value "$s" bg3)" ] || { echo "$s border"; false; }
      [ "$(scheme_value "$s" on_accent)" = "$(scheme_value "$s" bg0)" ] || { echo "$s on_accent"; false; }
      [ "$(scheme_value "$s" dim)" = "$(scheme_value "$s" grey1)" ] || { echo "$s dim"; false; }
      [ "$(scheme_value "$s" hover)" = "$(scheme_value "$s" bg1)" ] || { echo "$s hover"; false; }
      [ "$(scheme_value "$s" muted)" = "$(scheme_value "$s" grey2)" ] || { echo "$s muted"; false; }
      # The wordmark's ink is the branding's, not the scheme's: one paper
      # tone on every dark scheme, one dark ink on every light one.
      [ "$(scheme_value "$s" lockup_ink)" = "#DAC7A2" ] || { echo "$s lockup_ink"; false; }
    else
      [ "$(scheme_value "$s" border)" = "$(scheme_value "$s" bg5)" ] || { echo "$s border"; false; }
      [ "$(scheme_value "$s" on_accent)" = "$(scheme_value "dark-$c" bg0)" ] || { echo "$s on_accent"; false; }
      [ "$(scheme_value "$s" dim)" = "$(scheme_value "$s" grey2)" ] || { echo "$s dim"; false; }
      [ "$(scheme_value "$s" hover)" = "$(scheme_value "$s" bg3)" ] || { echo "$s hover"; false; }
      [ "$(scheme_value "$s" muted)" = "$(scheme_value "$s" fg)" ] || { echo "$s muted"; false; }
      [ "$(scheme_value "$s" lockup_ink)" = "#27332A" ] || { echo "$s lockup_ink"; false; }
    fi
  done
}

@test "fill is Grove's" {
  local s
  for s in $SCHEMES; do
    if [[ $s == dark-* ]]; then
      [ "$(scheme_value "$s" fill)" = "#596763" ] || { echo "$s fill"; false; }
    else
      [ "$(scheme_value "$s" fill)" = "$(scheme_value "$s" bg5)" ] || { echo "$s fill"; false; }
    fi
  done
}

# contrast A B: the WCAG contrast ratio of two #RRGGBB colours, two decimals.
contrast() {
  awk -v a="$1" -v b="$2" '
    function ch(h, i,   v) {
      v = (index("0123456789ABCDEF", toupper(substr(h, i, 1))) - 1) * 16 + index("0123456789ABCDEF", toupper(substr(h, i + 1, 1))) - 1
      v /= 255
      return v <= 0.03928 ? v / 12.92 : exp(2.4 * log((v + 0.055) / 1.055))
    }
    function lum(h) { return 0.2126 * ch(h, 2) + 0.7152 * ch(h, 4) + 0.0722 * ch(h, 6) }
    BEGIN { x = lum(a); y = lum(b); if (x < y) { t = x; x = y; y = t }; printf "%.2f\n", (x + 0.05) / (y + 0.05) }'
}

# at_least RATIO MIN: 0 when RATIO >= MIN.
at_least() { awk -v r="$1" -v m="$2" 'BEGIN { exit !(r >= m) }'; }

@test "contrast is the WCAG ratio" {
  [ "$(contrast '#000000' '#FFFFFF')" = "21.00" ]
  [ "$(contrast '#FFFFFF' '#000000')" = "21.00" ]
  [ "$(contrast '#2d353b' '#2D353B')" = "1.00" ]
  [ "$(contrast '#2D353B' '#DFA000')" = "5.44" ]
}

@test "light schemes: text on the prompt's and yazi's accent blocks is at least 3:1, the border at least 1.5:1 on bg0" {
  local s f d pairs bg fg r n ink
  # shellcheck source=/dev/null
  . "$GROVE_ROOT/../grove-themes/lib/render.sh"
  for s in light-hard light-medium light-soft; do
    d="$BATS_TEST_TMPDIR/$s"
    mkdir -p "$d"
    for f in starship.toml starship-plain.toml yazi/theme.toml yazi/init.lua; do
      gt_render_file "$s" "$GROVE_ROOT/theme" "$GROVE_ROOT/config/$f.tmpl" "$d/${f##*/}" || false
    done
    ink="$(scheme_value "$s" on_accent)"
    # The prompts: every block style is "bg:<accent> fg:<text>".
    for f in starship.toml starship-plain.toml; do
      pairs="$(sed -n 's/^[a-z_]*style[a-z_]* = "bg:\(#[0-9A-Fa-f]\{6\}\) fg:\(#[0-9A-Fa-f]\{6\}\)"$/\1 \2/p' "$d/$f")"
      n=0
      while read -r bg fg; do
        r="$(contrast "$fg" "$bg")"
        at_least "$r" 3 || { echo "$s $f: $fg on $bg is $r:1"; false; }
        n=$((n + 1))
      done <<< "$pairs"
      [ "$n" -eq 7 ] || { echo "$s $f: $n block styles"; false; }
    done
    # yazi's blocks: every { fg, bg } pair whose bg is an accent (the marker_*
    # rows are solid, fg = bg, and the *_alt rows sit on bg2).
    pairs="$(sed -n 's/^[a-z_]* *= { fg = "\(#[0-9A-Fa-f]\{6\}\)", bg = "\(#[0-9A-Fa-f]\{6\}\)".*/\1 \2/p' "$d/theme.toml" | awk '$1 != $2')"
    n=0
    while read -r fg bg; do
      case "$bg" in
        "$(scheme_value "$s" green)"|"$(scheme_value "$s" red)"|"$(scheme_value "$s" yellow)"|"$(scheme_value "$s" orange)"|"$(scheme_value "$s" aqua)") ;;
        *) continue ;;
      esac
      [ "$fg" = "$ink" ] || { echo "$s yazi: $fg on $bg is not on_accent"; false; }
      r="$(contrast "$fg" "$bg")"
      at_least "$r" 3 || { echo "$s yazi: $fg on $bg is $r:1"; false; }
      n=$((n + 1))
    done <<< "$pairs"
    [ "$n" -eq 7 ] || { echo "$s yazi: $n accent blocks"; false; }
    # yazi's top bar writes its text in on_accent and its rule in border.
    grep -q "\"$ink\", \"$(scheme_value "$s" border)\"\$" "$d/init.lua" || { echo "$s yazi bar"; false; }
    for bg in aqua green yellow; do
      at_least "$(contrast "$ink" "$(scheme_value "$s" "$bg")")" 3 || { echo "$s yazi bar on $bg"; false; }
    done
    r="$(contrast "$(scheme_value "$s" border)" "$(scheme_value "$s" bg0)")"
    at_least "$r" 1.5 || { echo "$s: border on bg0 is $r:1"; false; }
  done
}

@test "lines and quiet text use the roles: yazi's and fzf's borders, fastfetch's empty marks and separator, eza, zsh" {
  local c="$GROVE_ROOT/config"
  grep -qx 'border_style = { fg = "{{border}}" }' "$c/yazi/theme.toml.tmpl"
  grep -q 'info:{{dim}},.*border:{{border}}"$' "$c/zsh/conf.d/40-tools.zsh.tmpl"
  grep -q '"separator": "{{dim}}"' "$c/fastfetch/config.jsonc.tmpl"
  grep -q '"total": "{{border}}"' "$c/fastfetch/config.jsonc.tmpl"
  grep -q "fg={{dim}}" "$c/zsh/conf.d/85-autosuggest.zsh.tmpl"
  grep -q "\[comment\]='fg={{dim}}'" "$c/zsh/conf.d/98-highlight.zsh.tmpl"
  grep -q '^punctuation: {foreground: "{{dim}}"}$' "$c/eza/theme.yml.tmpl"
  # No text or line in these still names the colours the roles replaced.
  run grep -lE '\{\{(bg3|grey1)\}\}|fg:\{\{bg0\}\}|fg = "\{\{bg0\}\}"' "$c/starship.toml.tmpl" "$c/starship-plain.toml.tmpl" \
    "$c/yazi/init.lua.tmpl" "$c/fastfetch/config.jsonc.tmpl" "$c/eza/theme.yml.tmpl" \
    "$c/zsh/conf.d/40-tools.zsh.tmpl" "$c/zsh/conf.d/85-autosuggest.zsh.tmpl" "$c/zsh/conf.d/98-highlight.zsh.tmpl"
  [ -z "$output" ] || { echo "$output"; false; }
  # yazi's theme keeps grey1 only for file icons, and bg0 nowhere as text.
  run grep -E '\{\{(bg3|grey1)\}\}|fg = "\{\{bg0\}\}"' "$c/yazi/theme.toml.tmpl"
  [ -z "$(printf '%s\n' "$output" | grep -v 'text = "')" ] || { echo "$output"; false; }
}

# scheme_hexes SCHEME: every #RRGGBB in theme/everforest-SCHEME, uppercased.
scheme_hexes() {
  grep -v '^[[:space:]]*#' "$GROVE_ROOT/theme/everforest-$1" | grep -oE '#[0-9A-Fa-f]{6}' | tr '[:lower:]' '[:upper:]' | sort -u
}

@test "every scheme's render uses only that scheme's palette colours" {
  local s t out missing
  # shellcheck source=/dev/null
  . "$GROVE_ROOT/../grove-themes/lib/render.sh"
  for s in $SCHEMES; do
    out="$BATS_TEST_TMPDIR/$s"
    for t in $(gt_templates "$GROVE_ROOT/config"); do
      mkdir -p "$(dirname "$out/$t")"
      gt_render_file "$s" "$GROVE_ROOT/theme" "$GROVE_ROOT/config/$t" "$out/${t%.tmpl}" || false
    done
    [ -n "$(config_hexes $(find "$out" -type f))" ] || { echo "$s: no colours rendered"; false; }
    missing="$(comm -23 <(config_hexes $(find "$out" -type f)) <(scheme_hexes "$s"))"
    [ -z "$missing" ] || { echo "$s: not in its palette: $missing"; false; }
  done
}

@test "every scheme's Chrome theme RGB arrays are that scheme's palette colours" {
  local s out c hex missing
  # shellcheck source=/dev/null
  . "$GROVE_ROOT/../grove-themes/lib/render.sh"
  for s in $SCHEMES; do
    out="$BATS_TEST_TMPDIR/$s-chrome"
    mkdir -p "$out"
    gt_render_file "$s" "$GROVE_ROOT/theme" "$GROVE_ROOT/config/chrome-theme/manifest.json.tmpl" "$out/manifest.json" || false
    hex="$(jq -r '.theme.colors[] | map(.) | @sh' "$out/manifest.json" | while read -r r g b; do printf '#%02X%02X%02X\n' "$r" "$g" "$b"; done | sort -u)"
    [ -n "$hex" ] || { echo "$s: no colours"; false; }
    missing="$(comm -23 <(printf '%s\n' "$hex") <(scheme_hexes "$s"))"
    [ -z "$missing" ] || { echo "$s: not in its palette: $missing"; false; }
  done
}

@test "configs that aren't templates use only Dark Medium colours; the icon theme's light set, Light Medium's" {
  local missing
  missing="$(comm -23 <(config_hexes $(git -C "$GROVE_ROOT" ls-files ':(glob)config/zsh/conf.d/*.zsh' | sed "s|^|$GROVE_ROOT/|")) <(palette_hexes))"
  [ -z "$missing" ] || { echo "not in the palette: $missing"; false; }
  # Grove Icons holds a dark set and a light one (grove-icons/build.py).
  missing="$(comm -23 <(config_hexes "$GROVE_ROOT/config/vscode/grove-icons/grove-icon-theme.json") \
      <({ palette_hexes; scheme_hexes light-medium; } | sort -u))"
  [ -z "$missing" ] || { echo "icon theme, not in Dark Medium or Light Medium: $missing"; false; }
}

# ghostty_value KEY: values of KEY in the Ghostty config, one per line.
ghostty_value() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$GROVE_RENDERED/ghostty/config"
}

@test "ghostty config sets the spec's keys" {
  [ "$(ghostty_value font-family)" = "JetBrains Mono" ]
  [ "$(ghostty_value font-size)" = "12" ]
  [ "$(ghostty_value background)" = "#2D353B" ]
  [ "$(ghostty_value foreground)" = "#D3C6AA" ]
  [ "$(ghostty_value selection-background)" = "#543A48" ]
  [ "$(ghostty_value background-opacity)" = "1" ]
  [ "$(ghostty_value keybind)" = "global:ctrl+grave_accent=toggle_quick_terminal" ]
  [ "$(ghostty_value quick-terminal-position)" = "top" ]
  [ "$(ghostty_value macos-titlebar-style)" = "transparent" ]
  [ "$(ghostty_value window-padding-x)" = "24" ]
  [ "$(ghostty_value window-padding-y)" = "20" ]
  [ "$(ghostty_value window-width)" = "150" ]
  [ "$(ghostty_value window-height)" = "40" ]
  ghostty_value palette | grep -qx '0=#475258'
  ghostty_value palette | grep -qx '8=#859289'
  [ "$(ghostty_value palette | wc -l | tr -d ' ')" -eq 16 ]
  [ "$(ghostty_value palette | cut -d= -f1 | sort -n | tr '\n' ' ')" = "0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 " ]
}

# fzf's ⌥C and zsh's ⌥B/⌥F need Alt; the Portuguese layout's [ ] { } | @ need right ⌥.
@test "ghostty treats left Option as Alt and leaves right Option to the layout" {
  [ "$(ghostty_value macos-option-as-alt)" = "left" ]
}

@test "ghostty validates the config" {
  local g="${GROVE_GHOSTTY:-/Applications/Ghostty.app/Contents/MacOS/ghostty}"
  [ -x "$g" ] || skip "Ghostty not installed"
  run "$g" +validate-config --config-file="$GROVE_RENDERED/ghostty/config"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# prompt_styles FILE: "[table] key = value" for every style, toggle and time setting.
prompt_styles() {
  awk '/^\[/ { t = $0 } /^[[:space:]]*(style[a-z_]*|show_always|disabled|time_format)[[:space:]]*=/ { print t " " $0 }' "$1"
}

@test "the two prompts have the same blocks and colors" {
  [ -f "$GROVE_RENDERED/starship-plain.toml" ]
  diff <(prompt_styles "$GROVE_RENDERED/starship.toml") <(prompt_styles "$GROVE_RENDERED/starship-plain.toml")
}

@test "the icon prompt uses the spec's glyphs" {
  local f="$GROVE_RENDERED/starship.toml"
  grep -q $'\xee\x82\xb6' "$f"          # U+E0B6 rounded left end
  grep -q $'\xee\x82\xb4' "$f"          # U+E0B4 rounded right end
  grep -q $'\xee\x82\xa0' "$f"          # U+E0A0 git branch
  grep -q $'\xf3\xb0\x8c\xbe' "$f"      # U+F033E lock
  grep -q $'\xee\x82\xb0' "$f"          # U+E0B0 arrow between blocks
  grep -q $'\xef\x85\xb9' "$f"          # U+F179 before the user
  grep -q $'\xef\x80\x97' "$f"          # U+F017 clock before the time
}

@test "the plain prompt has no Nerd Font glyphs" {
  # grep: 1 = no match (wanted), 2 = file missing.
  LC_ALL=C run grep -q $'\xee\x82\|\xf3\xb0' "$GROVE_RENDERED/starship-plain.toml"
  [ "$status" -eq 1 ]
}

# ff_json EXPR: a value from the fastfetch config (JSONC, // comments dropped),
# as JSON. EXPR is Python, with the config as c.
ff_json() {
  python3 -c 'import json,re,sys; c=json.loads(re.sub(r"^\s*//.*$","",open(sys.argv[1]).read(),flags=re.M)); print(json.dumps(eval(sys.argv[2]),ensure_ascii=False))' \
    "$GROVE_RENDERED/fastfetch/config.jsonc" "$1"
}

@test "fastfetch shows the spec's readouts in order" {
  run ff_json '[m["type"] for m in c["modules"] if m["type"] != "custom"]'
  [ "$output" = '["title", "host", "kernel", "os", "wm", "packages", "terminal", "shell", "localip", "brightness", "display", "uptime", "cpu", "cpuusage", "memory", "battery", "colors"]' ]
}

@test "fastfetch shows the image beside the box: kitty-direct, 76 by 15, centred on the box's 22 rows" {
  run ff_json '[c["logo"][k] for k in ("type", "source", "width", "height", "preserveAspectRatio")] + [c["logo"]["padding"]["top"]]'
  [ "$output" = '["kitty-direct", "~/.config/fastfetch/grove.png", 76, 15, true, 3]' ]
}

@test "fastfetch's bars are green on the border colour, ten marks, no brackets" {
  run ff_json 'c["display"]["bar"]'
  [ "$output" = '{"char": {"elapsed": "▮ ", "total": "▮ "}, "border": {"left": "", "right": ""}, "width": 10, "color": {"elapsed": "#A7C080", "total": "#475258"}}' ]
}

@test "fastfetch's labels are green and not bold, the separator dim, values fg" {
  local sep=$'\xef\x86\xb2'   # U+F1B2, as in macchina
  run ff_json '[c["display"]["brightColor"], c["display"]["separator"], c["display"]["color"]["keys"], c["display"]["color"]["separator"], c["display"]["color"]["output"]]'
  [ "$output" = "[false, \"$sep  \", \"#A7C080\", \"#859289\", \"#D3C6AA\"]" ]
}

@test "fastfetch's config writes colors as palette hex, never raw RGB" {
  run grep -c '38;2' "$GROVE_RENDERED/fastfetch/config.jsonc"
  [ "$output" = 0 ]
}

# ff_screen COLS [ARGS...]: fastfetch with the Grove config on a COLS-wide
# terminal, replayed to plain text.
ff_screen() {
  local cols="$1"; shift
  local h="$BATS_TEST_TMPDIR/ffhome"
  mkdir -p "$h"; [ -L "$h/.config" ] || ln -s "$GROVE_RENDERED" "$h/.config"
  env -i HOME="$h" PATH="/opt/homebrew/bin:/usr/bin:/bin" TERM=xterm-256color \
    script -q "$BATS_TEST_TMPDIR/ff.out" /bin/sh -c "stty cols $cols rows 50; fastfetch $*" </dev/null >/dev/null 2>&1
  python3 "$GROVE_ROOT/tests/vt.py" "$BATS_TEST_TMPDIR/ff.out" "$cols" | sed 's/^\^D//'   # script echoes ^D for the empty stdin
}

@test "fastfetch accepts its config" {
  [ -x /opt/homebrew/bin/fastfetch ] || skip "fastfetch not installed"
  run ff_screen 160 --logo none
  [[ "$output" == *Kernel* ]] || false
  [[ "$output" != *rror* ]] || false
}

@test "fastfetch draws the stats in a 58-column box titled Grove, with the color dots" {
  [ -x /opt/homebrew/bin/fastfetch ] || skip "fastfetch not installed"
  run ff_screen 160 --logo none
  local box
  box="$(printf '%s\n' "$output" | sed -n '/┌/,/└/p')"
  [ "$(printf '%s\n' "$box" | head -1)" = "┌ Grove $(printf '─%.0s' $(seq 49))┐" ]
  [ "$(printf '%s\n' "$box" | tail -1)" = "└$(printf '─%.0s' $(seq 56))┘" ]
  printf '%s\n' "$box" | sed '1d;$d' | python3 -c '
import sys
bad = [l for l in sys.stdin.read().split("\n") if l and not (len(l) == 58 and l[0] == "│" and l[-1] == "│")]
print("\n".join(bad)); sys.exit(1 if bad else 0)'
  [[ "$box" == *"● ● ● ● ● ● ● ●"* ]] || false
}

@test "the image is a 1004 by 426 PNG with transparency (logo and lettering only)" {
  local f="$GROVE_ROOT/config/fastfetch/grove.png"
  [ "$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$f" | awk 'NR > 1 { print $2 }' | tr '\n' ' ')" = "1004 426 yes " ]
}

@test "each light scheme has its own image, the dark one's shape; the old grove-light.png is gone" {
  local c f
  for c in hard medium soft; do
    f="$GROVE_ROOT/config/fastfetch/grove-light-$c.png"
    [ -f "$f" ] || { echo "missing $f"; false; }
    [ "$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$f" | awk 'NR > 1 { print $2 }' | tr '\n' ' ')" = "1004 426 yes " ] || { echo "$f"; false; }
  done
  [ ! -e "$GROVE_ROOT/config/fastfetch/grove-light.png" ] || false
  [ -z "$(git -C "$GROVE_ROOT" ls-files config/fastfetch/grove-light.png)" ] || false
}

@test "the fetch check tests the image the scheme shows: grove.png dark, grove-light-<contrast>.png light" {
  local d="$BATS_TEST_TMPDIR/fetch" c
  . "$GROVE_ROOT/../grove-themes/lib/render.sh"
  gt_render_file dark-medium "$GROVE_ROOT/theme" "$GROVE_ROOT/config/zsh/conf.d/95-fetch.zsh.tmpl" "$d-dark" || false
  grep -q '\[\[ -r "\$dir/grove.png" \]\]' "$d-dark" || false
  for c in hard medium soft; do
    gt_render_file "light-$c" "$GROVE_ROOT/theme" "$GROVE_ROOT/config/zsh/conf.d/95-fetch.zsh.tmpl" "$d-light-$c" || false
    grep -q "\\[\\[ -r \"\\\$dir/grove-light-$c.png\" \\]\\]" "$d-light-$c" || { cat "$d-light-$c"; false; }
  done
}

# render_prompt FILE [plain]: the prompt Starship draws in a temp git repo (or,
# with `plain`, in a temp folder outside any repo), colors stripped.
render_prompt() {
  local r="$BATS_TEST_TMPDIR/repo"
  if [ "${2:-}" = plain ]; then
    r="$BATS_TEST_TMPDIR/folder"; mkdir -p "$r"
  else
    mkdir -p "$r" && git -C "$r" init -q -b main && touch "$r/new"
  fi
  (cd "$r" && env STARSHIP_CONFIG="$1" /opt/homebrew/bin/starship prompt --status 0) | sed $'s/\033\\[[0-9;]*m//g; s/%{//g; s/%}//g' | sed '/^$/d'
}

# arrows TEXT: how many U+E0B0 arrows TEXT has.
arrows() {
  printf '%s' "$1" | LC_ALL=C grep -o $'\xee\x82\xb0' | wc -l | tr -d ' '
}

@test "the prompt bar reads user, folder, git, time, joined by arrows with rounded ends" {
  [ -x /opt/homebrew/bin/starship ] || skip "starship not installed"
  run render_prompt "$GROVE_RENDERED/starship.toml"
  local me; me="$(id -un)" A=$'\xee\x82\xb0'
  [[ "$output" =~ ^$'\xee\x82\xb6'.*$me\ $A\ .*repo\ $A\ .*main\ .*\?.*$A.*[0-9]{2}:[0-9]{2}\ $'\xee\x82\xb4'\ \ ?❯ ]] || { echo "$output"; false; }
  [[ "$output" == *$'\xef\x85\xb9'* ]] || false   # U+F179 before the user
}

@test "in a repo the bar has one arrow per join: user, folder, git, time" {
  [ -x /opt/homebrew/bin/starship ] || skip "starship not installed"
  run render_prompt "$GROVE_RENDERED/starship.toml"
  local A=$'\xee\x82\xb0'
  [ "$(arrows "$output")" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" != *"$A$A"* ]] || { echo "$output"; false; }
  # after the git block, only the arrow into the time
  [ "$(arrows "${output#*main}")" -eq 1 ] || { echo "$output"; false; }
}

@test "outside a repo a two-arrow fade (green, yellow, orange) leads from the folder into the time" {
  [ -x /opt/homebrew/bin/starship ] || skip "starship not installed"
  run render_prompt "$GROVE_RENDERED/starship.toml" plain
  local A=$'\xee\x82\xb0'
  [ "$(arrows "$output")" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"folder $A$A "* ]] || { echo "$output"; false; }
  # the fade's colors: green on yellow, then yellow on orange
  local raw="$BATS_TEST_TMPDIR/folder"
  raw="$(cd "$raw" && env STARSHIP_CONFIG="$GROVE_RENDERED/starship.toml" /opt/homebrew/bin/starship prompt --status 0)"
  [[ "$raw" == *"48;2;219;188;127;38;2;167;192;128m"*"$A"*"48;2;230;152;117;38;2;219;188;127m"*"$A"* ]] || false
}

@test "the prompt has no duration or exit-code blocks" {
  [ -x /opt/homebrew/bin/starship ] || skip "starship not installed"
  local r="$BATS_TEST_TMPDIR/repo3"; mkdir -p "$r"
  run bash -c "cd '$r' && STARSHIP_CONFIG='$GROVE_RENDERED/starship.toml' /opt/homebrew/bin/starship prompt --status 1 --cmd-duration 9000"
  [[ "$output" != *"✗"* ]] || false
  [[ "$output" != *"9s"* ]] || false
}

@test "prompts are separated by an empty line" {
  grep -qx 'add_newline = true' "$GROVE_RENDERED/starship.toml"
  grep -qx 'add_newline = true' "$GROVE_RENDERED/starship-plain.toml"
}

@test "the plain prompt bar has the same blocks without rounded ends" {
  [ -x /opt/homebrew/bin/starship ] || skip "starship not installed"
  run render_prompt "$GROVE_RENDERED/starship-plain.toml"
  local me; me="$(id -un)"
  [[ "$output" =~ ^\ \ $me\ .*repo\ .*main\ .*\?.*\ [0-9]{2}:[0-9]{2}\ +❯ ]] || { echo "$output"; false; }
  [[ "$output" != *$'\xee\x82'* ]] || false
}

@test "a failed command turns the prompt character red" {
  [ -x /opt/homebrew/bin/starship ] || skip "starship not installed"
  local r="$BATS_TEST_TMPDIR/repo2"; mkdir -p "$r"
  run bash -c "cd '$r' && STARSHIP_CONFIG='$GROVE_RENDERED/starship.toml' /opt/homebrew/bin/starship prompt --status 1"
  [[ "$output" == *"38;2;230;126;128m"*"❯"* ]] || false
}

@test "the art is light plain text: at most 20 lines by 58 to 64 columns, no color codes" {
  local f="$GROVE_ROOT/config/fastfetch/grove.ascii" w
  [ "$(wc -l < "$f" | tr -d ' ')" -le 20 ]
  w="$(awk '{ if (length > m) m = length } END { print m + 0 }' "$f")"
  [ "$w" -ge 58 ] && [ "$w" -le 64 ]
  run grep -c $'\033' "$f"
  [ "$output" = 0 ]
  [ "$(grep -c '█\|▀\|▄' "$f")" -eq 0 ]
  grep -q '"Project Grove"' "$f"
}

