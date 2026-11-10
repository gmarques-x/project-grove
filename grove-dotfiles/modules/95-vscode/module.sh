# shellcheck shell=bash
# 95-vscode: VS Code's settings are a link to config/vscode/settings.json, and
# sainnhe's Everforest and Grove Icons (config/vscode/grove-icons, at its
# package.json version) are installed. Homebrew installs VS Code itself.
# Tests point GROVE_CODE at a fake code and GROVE_VSCODE_USER at a temp folder.

about() { echo "VS Code: Everforest, Grove Icons, JetBrains Mono"; }

_VSC_EVERFOREST=sainnhe.everforest
_VSC_ICONS_ID=grove.grove-icons

# _vsc_code: the code command. Homebrew may not be on PATH yet in a fresh
# install run, so also look next to brew.
_vsc_code() {
  local c
  if [ -n "${GROVE_CODE:-}" ]; then printf '%s' "$GROVE_CODE"; return 0; fi
  if c="$(command -v code 2>/dev/null)"; then printf '%s' "$c"; return 0; fi
  c="$(dirname "${GROVE_BREW:-/opt/homebrew/bin/brew}")/code"
  [ -x "$c" ] || return 1
  printf '%s' "$c"
}

_vsc_settings() {
  printf '%s/settings.json' "${GROVE_VSCODE_USER:-$HOME/Library/Application Support/Code/User}"
}

_vsc_icons() { printf '%s/vscode/grove-icons' "$GROVE_CONFIG"; }

_vsc_icons_version() { plutil -extract version raw -o - "$(_vsc_icons)/package.json"; }

# _vsc_installed WANT: 0 when the extension list has WANT, ignoring case. WANT
# is id@version, or a bare id for any version.
_vsc_installed() {
  local want line
  want="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
    case "$want" in
      *@*) [ "$line" = "$want" ] && return 0 ;;
      *) [ "${line%%@*}" = "$want" ] && return 0 ;;
    esac
  done <<EOF
$("$(_vsc_code)" --list-extensions --show-versions 2>/dev/null)
EOF
  return 1
}

check() {
  if ! _vsc_code >/dev/null; then
    grove_fail "VS Code's code command is missing; run grove install homebrew"
    return 1
  fi
  grove_link_check "$GROVE_CONFIG/vscode/settings.json" "$(_vsc_settings)" || return 3
  _vsc_installed "$_VSC_EVERFOREST" || return 3
  _vsc_installed "$_VSC_ICONS_ID@$(_vsc_icons_version)" || return 3
  return 0
}

# _vsc_vsix DIR: zip Grove Icons into DIR/grove-icons.vsix (the committed files
# plus the two manifests a vsix needs; build.py stays out) and print its path.
_vsc_vsix() {
  local dir="$1" v f
  v="$(_vsc_icons_version)" || return 1
  mkdir -p "$dir/extension" || return 1
  for f in package.json grove-icon-theme.json seti.woff NOTICE; do
    cp "$(_vsc_icons)/$f" "$dir/extension/$f" || return 1
  done
  cat > "$dir/[Content_Types].xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension=".json" ContentType="application/json"/><Default Extension=".woff" ContentType="font/woff"/><Default Extension=".vsixmanifest" ContentType="text/xml"/><Default Extension="" ContentType="text/plain"/></Types>
XML
  cat > "$dir/extension.vsixmanifest" <<XML
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata><Identity Language="en-US" Id="grove-icons" Version="$v" Publisher="grove"/><DisplayName>Grove Icons</DisplayName><Description xml:space="preserve">VS Code's Seti icons in Everforest colors</Description><Categories>Themes</Categories></Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets>
</PackageManifest>
XML
  (cd "$dir" && /usr/bin/zip -qrX grove-icons.vsix extension.vsixmanifest '[Content_Types].xml' extension) || return 1
  printf '%s/grove-icons.vsix' "$dir"
}

apply() {
  local code tmp vsix rc=0
  if ! code="$(_vsc_code)"; then
    grove_fail "VS Code's code command is missing; run grove install homebrew"
    return 1
  fi
  grove_link "$GROVE_CONFIG/vscode/settings.json" "$(_vsc_settings)" || return 1
  if ! _vsc_installed "$_VSC_EVERFOREST"; then
    "$code" --install-extension "$_VSC_EVERFOREST" >/dev/null || {
      grove_fail "could not install $_VSC_EVERFOREST (is the Mac online?)"
      return 1
    }
  fi
  if ! _vsc_installed "$_VSC_ICONS_ID@$(_vsc_icons_version)"; then
    tmp="$(mktemp -d)" || return 1
    if vsix="$(_vsc_vsix "$tmp")"; then
      "$code" --install-extension "$vsix" --force >/dev/null || rc=1
    else
      rc=1
    fi
    rm -rf "$tmp"
    if [ "$rc" -ne 0 ]; then
      grove_fail "could not install Grove Icons"
      return 1
    fi
  fi
  grove_note "VS Code picks up the theme the next time it opens."
}
