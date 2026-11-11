load helpers
setup() { gt_test_setup; gt_toy_palettes; source "$GT_ROOT/lib/render.sh"; }

@test "render fills names with the scheme's values" {
  printf 'fg={{fg}} bg={{bg0}}\n' > "$BATS_TEST_TMPDIR/t.tmpl"
  run gt_render_file dark-hard "$PALETTES" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = "fg=#D3C6A1 bg=#27E31" ]
  gt_render_file light-soft "$PALETTES" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = "fg=#D3C6A6 bg=#27E36" ]
}

@test "render fills the computed names" {
  printf '{{appearance}}|{{contrast}}|{{vscode_theme}}|{{fetch_image}}\n' > "$BATS_TEST_TMPDIR/t.tmpl"
  gt_render_file light-soft "$PALETTES" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = "light|soft|Everforest Light|grove-light-soft.png" ]
  gt_render_file dark-hard "$PALETTES" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = "dark|hard|Everforest Dark|grove.png" ]
}

@test "fetch_image: grove.png for every dark scheme, grove-light-<contrast>.png for each light one" {
  local s want
  for s in $(gt_schemes); do
    case "$s" in
      dark-*) want=grove.png ;;
      *) want="grove-light-${s#light-}.png" ;;
    esac
    [ "$(gt_values "$s" "$PALETTES" | awk -F"\t" '$1 == "fetch_image" { print $2 }')" = "$want" ] || { echo "$s"; false; }
  done
  [ "$(gt_values light-hard "$PALETTES" | awk -F"\t" '$1 == "fetch_image" { print $2 }')" = grove-light-hard.png ]
  [ "$(gt_values light-medium "$PALETTES" | awk -F"\t" '$1 == "fetch_image" { print $2 }')" = grove-light-medium.png ]
}

@test "values with & / and backslash render literally" {
  printf '{{amp}}\n' > "$BATS_TEST_TMPDIR/t.tmpl"
  gt_render_file dark-medium "$PALETTES" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = '#A&B/C\2' ]
}

@test "an unknown name fails and writes nothing" {
  printf 'x={{nope}}\n' > "$BATS_TEST_TMPDIR/t.tmpl"
  run gt_render_file dark-hard "$PALETTES" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown name: nope in $BATS_TEST_TMPDIR/t.tmpl"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/out" ]
  [ ! -e "$BATS_TEST_TMPDIR/out.tmp" ]
}

@test "text without names passes through byte for byte" {
  printf '# c / path & amp \\ back {single} $x `y`\n\tindent\nno newline' > "$BATS_TEST_TMPDIR/t.tmpl"
  gt_render_file dark-hard "$PALETTES" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  cmp "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
}

@test "gt_valid rejects other names" {
  gt_valid dark-hard
  gt_valid light-soft
  run gt_valid dark;        [ "$status" -eq 1 ]
  run gt_valid Dark-Medium; [ "$status" -eq 1 ]
  run gt_valid "";          [ "$status" -eq 1 ]
}

@test "gt_schemes lists the six in order" {
  [ "$(gt_schemes | tr '\n' ' ')" = "dark-hard dark-medium dark-soft light-hard light-medium light-soft " ]
}

@test "gt_values lists palette entries then computed names" {
  run gt_values dark-hard "$PALETTES"
  [ "${lines[0]}" = "$(printf 'fg\t#D3C6A1')" ]
  [ "${#lines[@]}" -eq 15 ]
  [ "${lines[3]}" = "$(printf 'fg_rgb\t211, 198, 161')" ]
  [ "${lines[4]}" = "$(printf 'fg_argb\t0xffD3C6A1')" ]
  [ "${lines[8]}" = "$(printf 'fetch_image\tgrove.png')" ]
  [ "${lines[9]}" = "$(printf 'chrome_version\t1.0.1')" ]
  [ "${lines[10]}" = "$(printf 'fetch_logo\tgrove')" ]
  [ "${lines[14]}" = "$(printf 'fetch_min_cols\t140')" ]
}

@test "gt_templates lists *.tmpl relative and sorted" {
  mkdir -p "$BATS_TEST_TMPDIR/cfg/b" "$BATS_TEST_TMPDIR/cfg/a"
  touch "$BATS_TEST_TMPDIR/cfg/b/z.tmpl" "$BATS_TEST_TMPDIR/cfg/a/y.tmpl" "$BATS_TEST_TMPDIR/cfg/a/n.txt"
  run gt_templates "$BATS_TEST_TMPDIR/cfg"
  [ "$output" = "$(printf 'a/y.tmpl\nb/z.tmpl')" ]
}

@test "render works under set -euo pipefail" {
  printf 'fg={{fg}}\n' > "$BATS_TEST_TMPDIR/t.tmpl"
  run /bin/bash -c 'set -euo pipefail; source "$1/lib/render.sh"; gt_render_file dark-hard "$2" "$3" "$4"; echo done' _ "$GT_ROOT" "$PALETTES" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 0 ]
  [ "$output" = done ]
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = "fg=#D3C6A1" ]
  [ ! -e "$BATS_TEST_TMPDIR/out.tmp" ]
  printf 'x={{nope}}\n' > "$BATS_TEST_TMPDIR/u.tmpl"
  run /bin/bash -c 'set -euo pipefail; source "$1/lib/render.sh"; gt_render_file dark-hard "$2" "$3" "$4" || echo "rc=$?"' _ "$GT_ROOT" "$PALETTES" "$BATS_TEST_TMPDIR/u.tmpl" "$BATS_TEST_TMPDIR/out2"
  [[ "$output" == *"unknown name: nope"*"rc=1"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/out2" ]
}

@test "every #RRGGBB value also gets a name_rgb in decimal" {
  mkdir -p "$BATS_TEST_TMPDIR/p"
  printf 'bg0 = #2D353B\nwhite = #FFFFFF\nzero = #000000\nnote = notahex\n' > "$BATS_TEST_TMPDIR/p/everforest-dark-medium"
  printf '{{bg0_rgb}}|{{white_rgb}}|{{zero_rgb}}\n' > "$BATS_TEST_TMPDIR/t.tmpl"
  gt_render_file dark-medium "$BATS_TEST_TMPDIR/p" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = "45, 53, 59|255, 255, 255|0, 0, 0" ]
  [ -z "$(gt_values dark-medium "$BATS_TEST_TMPDIR/p" | awk -F"\t" '$1 == "note_rgb"')" ]
}

@test "every #RRGGBB value also gets a name_argb, 0xff and upper-case hex" {
  mkdir -p "$BATS_TEST_TMPDIR/p"
  printf 'white = #ffeedd\ngreen = #A7C080\nnote = notahex\n' > "$BATS_TEST_TMPDIR/p/everforest-dark-medium"
  printf '{{white_argb}}|{{green_argb}}\n' > "$BATS_TEST_TMPDIR/t.tmpl"
  gt_render_file dark-medium "$BATS_TEST_TMPDIR/p" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = "0xffFFEEDD|0xffA7C080" ]
  [ -z "$(gt_values dark-medium "$BATS_TEST_TMPDIR/p" | awk -F"\t" '$1 == "note_argb"')" ]
}

@test "chrome_version is 1.0.N, N the scheme's position" {
  local s n=0
  for s in $(gt_schemes); do
    n=$((n + 1))
    [ "$(gt_values "$s" "$PALETTES" | awk -F"\t" '$1 == "chrome_version" { print $2 }')" = "1.0.$n" ] || { echo "$s"; false; }
  done
}

# fv SCHEME NAME: one computed value.
fv() { gt_values "$1" "$PALETTES" | awk -F"\t" -v n="$2" '$1 == n { print $2 }'; }

@test "logo: grove when there is no state file" {
  [ "$(gt_logo)" = grove ]
  [ "$(fv dark-medium fetch_logo)" = grove ]
}

@test "logo: avatar is read through surrounding whitespace" {
  mkdir -p "$GROVE_STATE"; printf '  avatar \n\n' > "$GROVE_STATE/fetch-logo"
  [ "$(gt_logo)" = avatar ]
}

@test "logo: anything else is grove" {
  mkdir -p "$GROVE_STATE"; printf 'banana\n' > "$GROVE_STATE/fetch-logo"
  [ "$(gt_logo)" = grove ]
}

@test "logo: gt_logos lists grove then avatar" {
  [ "$(gt_logos)" = "grove avatar" ]
}

@test "logo: grove values are today's" {
  [ "$(fv dark-medium fetch_image)" = grove.png ]
  [ "$(fv dark-medium fetch_width)" = 76 ]
  [ "$(fv dark-medium fetch_height)" = 15 ]
  [ "$(fv dark-medium fetch_pad_top)" = 3 ]
  [ "$(fv dark-medium fetch_min_cols)" = 140 ]
  [ "$(fv light-soft fetch_image)" = grove-light-soft.png ]
}

@test "logo: avatar values on dark and light schemes" {
  mkdir -p "$GROVE_STATE"; echo avatar > "$GROVE_STATE/fetch-logo"
  [ "$(fv dark-hard fetch_logo)" = avatar ]
  [ "$(fv dark-hard fetch_image)" = avatar.png ]
  [ "$(fv dark-hard fetch_width)" = 46 ]
  [ "$(fv dark-hard fetch_height)" = 17 ]
  [ "$(fv dark-hard fetch_pad_top)" = 2 ]
  [ "$(fv dark-hard fetch_min_cols)" = 108 ]
  [ "$(fv light-hard fetch_image)" = avatar-light-hard.png ]
}

@test "logo: a scheme change keeps the avatar" {
  mkdir -p "$GROVE_STATE"; echo avatar > "$GROVE_STATE/fetch-logo"
  [ "$(fv light-soft fetch_image)" = avatar-light-soft.png ]
  [ "$(fv light-medium fetch_image)" = avatar-light-medium.png ]
}

@test "wallpaper: grove by default, avatar through whitespace, unknown is grove" {
  [ "$(gt_wallpaper)" = grove ]
  mkdir -p "$GROVE_STATE"; printf ' avatar\n' > "$GROVE_STATE/wallpaper"
  [ "$(gt_wallpaper)" = avatar ]
  echo banana > "$GROVE_STATE/wallpaper"
  [ "$(gt_wallpaper)" = grove ]
  [ "$(gt_wallpapers)" = "grove avatar" ]
}
