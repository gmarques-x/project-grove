# shellcheck disable=SC2016,SC1090,SC1091,SC2154
# 95-vscode: the settings file, Grove Icons, and the module against a fake `code`.
load helpers

VSC_MODULE=95-vscode

load_module() {
  local f
  for f in "$GROVE_ROOT"/lib/*.sh; do . "$f"; done
  MODULE_DIR="$GROVE_ROOT/modules/$VSC_MODULE"
  . "$MODULE_DIR/module.sh"
}

# The fake code: logs its arguments, lists $BATS_TEST_TMPDIR/extensions, and
# "installs" by adding lines there. FAKE_CODE_FAIL=1 acts like an offline Mac.
setup() {
  grove_test_setup
  : > "$BATS_TEST_TMPDIR/extensions"
  stub code '
echo "$*" >> "$BATS_TEST_TMPDIR/code-args"
ex="$BATS_TEST_TMPDIR/extensions"
case "$1" in
  --list-extensions) cat "$ex" ;;
  --install-extension)
    if [ -n "$FAKE_CODE_FAIL" ]; then echo "Failed Installing Extensions: $2" >&2; exit 1; fi
    case "$2" in
      *.vsix)
        cp "$2" "$BATS_TEST_TMPDIR/last.vsix"
        v=$(unzip -p "$2" extension/package.json | sed -n "s/.*\"version\": *\"\([^\"]*\)\".*/\1/p")
        grep -v "^grove.grove-icons@" "$ex" > "$ex.new"; mv "$ex.new" "$ex"
        echo "grove.grove-icons@$v" >> "$ex" ;;
      *) echo "$2@0.3.0" >> "$ex" ;;
    esac ;;
esac'
  export GROVE_CODE="$BATS_TEST_TMPDIR/stubs/code"
  export GROVE_VSCODE_USER="$BATS_TEST_TMPDIR/Application Support/Code/User"
  SETTINGS="$GROVE_VSCODE_USER/settings.json"
  ICONS_VERSION="$(jq -r .version "$GROVE_CONFIG/vscode/grove-icons/package.json")"
}

# vsc_ready: the settings linked and both extensions installed at today's versions.
vsc_ready() {
  mkdir -p "$GROVE_VSCODE_USER"
  ln -s "$GROVE_CONFIG/vscode/settings.json" "$SETTINGS"
  printf 'sainnhe.everforest@0.3.0\ngrove.grove-icons@%s\n' "$ICONS_VERSION" > "$BATS_TEST_TMPDIR/extensions"
}

# vsc_json FILE: FILE without its // comment lines, so jq can read it.
vsc_json() { sed '/^[[:space:]]*\/\//d' "$1"; }

@test "vscode: settings are valid JSON" {
  vsc_json "$GROVE_CONFIG/vscode/settings.json" | jq -e . >/dev/null
}

@test "vscode: settings choose Everforest, Grove Icons and JetBrains Mono 12" {
  vsc_json "$GROVE_CONFIG/vscode/settings.json" | jq -e '
    .["workbench.colorTheme"] == "Everforest Dark" and
    .["workbench.iconTheme"] == "grove-icons" and
    .["everforest.darkContrast"] == "medium" and
    .["editor.fontFamily"] == "JetBrains Mono" and
    .["editor.fontSize"] == 12 and
    .["editor.fontLigatures"] == true and
    .["terminal.integrated.fontFamily"] == "JetBrains Mono" and
    .["terminal.integrated.fontSize"] == 12' >/dev/null
}

@test "vscode: terminal colors are Ghostty's" {
  local g="$GROVE_CONFIG/ghostty/config" want got
  want="$(sed -n 's/^foreground = //p' "$g"; sed -n 's/^palette = [0-9]*=//p' "$g")"
  got="$(vsc_json "$GROVE_CONFIG/vscode/settings.json" | jq -r '
    .["workbench.colorCustomizations"]["[Everforest Dark]"] as $c
    | ["foreground", (["Black","Red","Green","Yellow","Blue","Magenta","Cyan","White"]
        | (map("ansi" + .) + map("ansiBright" + .)))[]]
    | .[] | $c["terminal." + .]')"
  [ "$(printf '%s\n' "$want" | wc -l)" -eq 17 ]
  [ "$got" = "$want" ] || { diff <(echo "$want") <(echo "$got"); false; }
}

VSC_ICONS_DIR=config/vscode/grove-icons
SETI_JSON="/Applications/Visual Studio Code.app/Contents/Resources/app/extensions/theme-seti/icons/vs-seti-icon-theme.json"

@test "vscode: every icon has a palette color" {
  local t="$GROVE_ROOT/$VSC_ICONS_DIR/grove-icon-theme.json" pal bad
  pal="$(sed -n 's/^[a-z_0-9]* *= *\(#[0-9A-Fa-f]\{6\}\).*/\1/p' "$GROVE_ROOT/theme/everforest-dark-medium" | tr a-f A-F)"
  [ "$(jq '[.iconDefinitions[] | select(.fontColor == null)] | length' "$t")" -eq 0 ]
  bad="$(jq -r '.iconDefinitions[].fontColor' "$t" | tr a-f A-F | sort -u | grep -vxF "$pal" || true)"
  [ -z "$bad" ] || { echo "not in the palette: $bad"; false; }
}

@test "vscode: Grove Icons keeps every Seti icon" {
  [ -f "$SETI_JSON" ] || skip "VS Code not installed"
  local t="$GROVE_ROOT/$VSC_ICONS_DIR/grove-icon-theme.json"
  [ "$(jq '.iconDefinitions | length' "$t")" -eq "$(jq '.iconDefinitions | length' "$SETI_JSON")" ]
  [ "$(jq 'has("light")' "$t")" = false ]
}

@test "vscode: the icon theme points at its files" {
  local d="$GROVE_ROOT/$VSC_ICONS_DIR" p f
  p="$(jq -r '.contributes.iconThemes[0].path' "$d/package.json")"
  [ -f "$d/$p" ]
  f="$(jq -r '.fonts[0].src[0].path' "$d/$p")"
  [ "$(cd "$(dirname "$d/$p")" && cd "$(dirname "$f")" && pwd -P)/$(basename "$f")" = "$(cd "$d" && pwd -P)/seti.woff" ]
  [ -f "$d/seti.woff" ]
}

@test "vscode: NOTICE credits Seti UI and Microsoft" {
  local n="$GROVE_ROOT/$VSC_ICONS_DIR/NOTICE"
  grep -q "Seti UI" "$n"
  grep -q "Microsoft Corporation" "$n"
  grep -q "MIT" "$n"
}

@test "vscode: about names it" {
  load_module
  run about
  [ "$output" = "VS Code: Everforest, Grove Icons, JetBrains Mono" ]
}

@test "vscode: failed without the code command" {
  unset GROVE_CODE
  rm "$BATS_TEST_TMPDIR/stubs/code"
  export PATH="$BATS_TEST_TMPDIR/stubs:/usr/bin:/bin" GROVE_BREW="$BATS_TEST_TMPDIR/nobrew/brew"
  load_module
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"grove install homebrew"* ]]
}

@test "vscode: finds code next to brew" {
  unset GROVE_CODE
  mkdir -p "$BATS_TEST_TMPDIR/brew/bin"
  mv "$BATS_TEST_TMPDIR/stubs/code" "$BATS_TEST_TMPDIR/brew/bin/code"
  export PATH="$BATS_TEST_TMPDIR/stubs:/usr/bin:/bin" GROVE_BREW="$BATS_TEST_TMPDIR/brew/bin/brew"
  vsc_ready
  load_module
  run check
  [ "$status" -eq 0 ]
}

@test "vscode: needs work when settings aren't linked" {
  vsc_ready
  rm "$SETTINGS"
  load_module
  run check
  [ "$status" -eq 3 ]
}

@test "vscode: needs work without Everforest" {
  vsc_ready
  printf 'grove.grove-icons@%s\n' "$ICONS_VERSION" > "$BATS_TEST_TMPDIR/extensions"
  load_module
  run check
  [ "$status" -eq 3 ]
}

@test "vscode: needs work when Grove Icons is another version" {
  vsc_ready
  load_module
  printf 'sainnhe.everforest@0.3.0\ngrove.grove-icons@0.9.0\n' > "$BATS_TEST_TMPDIR/extensions"
  run check
  [ "$status" -eq 3 ]
  printf 'sainnhe.everforest@0.3.0\ngrove.grove-icons@9.9.9\n' > "$BATS_TEST_TMPDIR/extensions"
  run check
  [ "$status" -eq 3 ]
}

@test "vscode: ok when everything is in place" {
  vsc_ready
  load_module
  run check
  [ "$status" -eq 0 ]
  ! grep -q -- --install-extension "$BATS_TEST_TMPDIR/code-args"
}

@test "vscode: the README lists the module" {
  grep -q '^| `95-vscode` |' "$GROVE_ROOT/README.md"
}
