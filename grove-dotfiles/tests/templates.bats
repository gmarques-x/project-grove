#!/usr/bin/env bats
# Colour-carrying configs are templates (config/<path>.tmpl), rendered by
# grove-themes for any of the six schemes. Spec §5.
# shellcheck disable=SC1090,SC1091

load helpers

setup() {
  grove_test_setup
  . "$GROVE_ROOT/../grove-themes/lib/render.sh"
  PALETTES="$GROVE_ROOT/theme"
}

# The fifteen generated files, one per line.
GENERATED="borders/bordersrc
chrome-theme/manifest.json
eza/theme.yml
fastfetch/config.jsonc
ghostty/config
sketchybar/colors.sh
starship-plain.toml
starship.toml
vscode/settings.json
yazi/init.lua
yazi/theme.toml
zsh/conf.d/40-tools.zsh
zsh/conf.d/85-autosuggest.zsh
zsh/conf.d/95-fetch.zsh
zsh/conf.d/98-highlight.zsh"

@test "the templates are the fifteen colour-carrying configs" {
  local want
  want="$(printf '%s\n' "$GENERATED" | sed 's/$/.tmpl/' | LC_ALL=C sort)"
  [ "$(gt_templates "$GROVE_ROOT/config")" = "$want" ] || { diff <(echo "$want") <(gt_templates "$GROVE_ROOT/config"); false; }
}

@test "templates use only palette and computed names" {
  local names t n
  names="$(gt_values dark-medium "$PALETTES" | cut -f1)"
  [ -n "$(gt_templates "$GROVE_ROOT/config")" ]
  for t in $(gt_templates "$GROVE_ROOT/config"); do
    for n in $(grep -o '{{[a-z0-9_]*}}' "$GROVE_ROOT/config/$t" | sed 's/[{}]//g' | sort -u); do
      printf '%s\n' "$names" | grep -qx "$n" || { echo "$t: unknown name $n"; false; }
    done
  done
}

@test "every template renders for all six schemes" {
  local s f out n=0
  for s in $(gt_schemes); do
    for f in $GENERATED; do
      out="$BATS_TEST_TMPDIR/$s/$f"
      mkdir -p "$(dirname "$out")"
      gt_render_file "$s" "$PALETTES" "$GROVE_ROOT/config/$f.tmpl" "$out" || { echo "$s: $f failed"; false; }
      [ -s "$out" ] || { echo "$s: $f empty"; false; }
      n=$((n + 1))
    done
  done
  [ "$n" -eq 90 ]
}

@test "the Dark Medium render is today's config" {
  local f out
  for f in $GENERATED; do
    [ -f "$GROVE_ROOT/tests/fixtures/dark-medium/$f" ] || { echo "no fixture: $f"; false; }
    out="$BATS_TEST_TMPDIR/out/$f"
    mkdir -p "$(dirname "$out")"
    gt_render_file dark-medium "$PALETTES" "$GROVE_ROOT/config/$f.tmpl" "$out" || { echo "render failed: $f"; false; }
    cmp "$GROVE_ROOT/tests/fixtures/dark-medium/$f" "$out" || { diff "$GROVE_ROOT/tests/fixtures/dark-medium/$f" "$out"; false; }
  done
}

@test "GROVE_RENDERED is a Dark Medium render of the tracked config" {
  local f
  [ -n "$GROVE_RENDERED" ] && [ -d "$GROVE_RENDERED" ] || false
  for f in $GENERATED; do
    cmp "$GROVE_ROOT/tests/fixtures/dark-medium/$f" "$GROVE_RENDERED/$f" || false
  done
  [ -f "$GROVE_RENDERED/zsh/.zshrc" ] || false
}

@test "grove_copy_tracked_config renders Dark Medium into the copy" {
  local f d="$BATS_TEST_TMPDIR/copy"
  grove_copy_tracked_config "$d"
  for f in $GENERATED; do
    cmp "$GROVE_ROOT/tests/fixtures/dark-medium/$f" "$d/$f" || false
  done
}

# chrome_color SCHEME KEY: the manifest's colour array as "R, G, B" text.
chrome_color() {
  jq -r --arg k "$2" '.theme.colors[$k] | map(tostring) | join(", ")' "$BATS_TEST_TMPDIR/$1/chrome-theme/manifest.json"
}

# palette_rgb SCHEME NAME: the palette's #RRGGBB as "R, G, B" decimal.
palette_rgb() {
  local hex
  hex="$(sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*#\\([0-9A-Fa-f]*\\).*/\\1/p" "$PALETTES/everforest-$1")"
  printf '%d, %d, %d' "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))"
}

@test "the Chrome theme manifest is valid JSON for every scheme, with the mapped palette colours" {
  local s k want n=0
  for s in $(gt_schemes); do
    n=$((n + 1))
    mkdir -p "$BATS_TEST_TMPDIR/$s/chrome-theme"
    gt_render_file "$s" "$PALETTES" "$GROVE_ROOT/config/chrome-theme/manifest.json.tmpl" "$BATS_TEST_TMPDIR/$s/chrome-theme/manifest.json" || false
    jq -e --arg v "1.0.$n" '.manifest_version == 3 and .name == "Grove" and .version == $v and .theme.properties.ntp_logo_alternate == 1' \
      "$BATS_TEST_TMPDIR/$s/chrome-theme/manifest.json" >/dev/null || { echo "$s: manifest"; false; }
    for k in "frame bg_dim" "frame_inactive bg_dim" "frame_incognito bg_dim" "frame_incognito_inactive bg_dim" \
             "toolbar bg0" "ntp_background bg0" "tab_text fg" "bookmark_text fg" "ntp_text fg" "toolbar_text fg" \
             "omnibox_text fg" "tab_background_text grey1" "tab_background_text_inactive grey1" \
             "toolbar_button_icon grey2" "omnibox_background bg1" "ntp_link green" "button_background bg1"; do
      set -- $k
      want="$(palette_rgb "$s" "$2")"
      [ "$(chrome_color "$s" "$1")" = "$want" ] || { echo "$s $1: got $(chrome_color "$s" "$1"), want $want ($2)"; false; }
    done
    [ "$(jq '.theme.colors | length' "$BATS_TEST_TMPDIR/$s/chrome-theme/manifest.json")" -eq 17 ] || false
  done
}

@test "bordersrc colours the borders for every scheme" {
  local s out green border want
  for s in $(gt_schemes); do
    out="$BATS_TEST_TMPDIR/$s-bordersrc"
    gt_render_file "$s" "$PALETTES" "$GROVE_ROOT/config/borders/bordersrc.tmpl" "$out"
    green="$(sed -n 's/^green *= *#\(......\)$/\1/p' "$PALETTES/everforest-$s" | tr '[:lower:]' '[:upper:]')"
    # Unfocused windows take the border role: bg3 in dark, bg5 in light.
    border="$(sed -n 's/^border *= *#\(......\)$/\1/p' "$PALETTES/everforest-$s" | tr '[:lower:]' '[:upper:]')"
    [ -n "$green" ] && [ -n "$border" ]
    want="borders active_color=0xff$green inactive_color=0xff$border width=5.0 style=round hidpi=on"
    [ "$(grep -v '^#' "$out" | grep -v '^$')" = "$want" ] || { echo "$s:"; cat "$out"; false; }
  done
}

@test "with the avatar logo, the fetch config and hook take its image, size and threshold" {
  local out="$BATS_TEST_TMPDIR/avatar"
  mkdir -p "$out" "$GROVE_STATE"
  echo avatar > "$GROVE_STATE/fetch-logo"
  gt_render_file dark-medium "$PALETTES" "$GROVE_ROOT/config/fastfetch/config.jsonc.tmpl" "$out/config.jsonc"
  gt_render_file light-soft "$PALETTES" "$GROVE_ROOT/config/zsh/conf.d/95-fetch.zsh.tmpl" "$out/95-fetch.zsh"
  grep -q '"source": "~/.config/fastfetch/avatar.png"' "$out/config.jsonc"
  grep -q '"width": 46,' "$out/config.jsonc"
  grep -q '"height": 17,' "$out/config.jsonc"
  grep -q '"top": 2 }' "$out/config.jsonc"
  grep -q 'COLUMNS >= 108' "$out/95-fetch.zsh"
  grep -q 'avatar-light-soft.png' "$out/95-fetch.zsh"
}

@test "every avatar image the renderer can name is tracked" {
  local f
  for f in avatar.png avatar-light-hard.png avatar-light-medium.png avatar-light-soft.png; do
    git -C "$GROVE_ROOT" ls-files --error-unmatch "config/fastfetch/$f" >/dev/null || { echo "untracked: $f"; false; }
  done
}
