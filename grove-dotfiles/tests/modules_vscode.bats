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
