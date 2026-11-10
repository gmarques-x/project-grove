# shellcheck disable=SC2016,SC1090,SC1091,SC2154
# 95-vscode: the settings file, Grove Icons, and the module against a fake `code`.
load helpers

setup() { grove_test_setup; }

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
