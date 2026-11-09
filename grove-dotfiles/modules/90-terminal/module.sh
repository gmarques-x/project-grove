# shellcheck shell=bash
# 90-terminal: Ghostty and macchina are installed (Homebrew does that), the
# Ghostty config is valid and not overridden, and Ghostty has Terminal's slot
# in the Dock. Tests redirect GROVE_DOCK_DOMAIN, GROVE_GHOSTTY, GROVE_GHOSTTY_APP.

about() { echo "Ghostty, the prompt and macchina"; }

_TERM_PB=/usr/libexec/PlistBuddy
_TERM_GHOSTTY_URL=file:///Applications/Ghostty.app/
_TERM_GHOSTTY_ID=com.mitchellh.ghostty

_term_dock_domain() { printf '%s' "${GROVE_DOCK_DOMAIN:-com.apple.dock}"; }
_term_app() { printf '%s' "${GROVE_GHOSTTY_APP:-/Applications/Ghostty.app}"; }
_term_cli() { printf '%s' "${GROVE_GHOSTTY:-/Applications/Ghostty.app/Contents/MacOS/ghostty}"; }

# Homebrew may not be on PATH yet in a fresh install run, so also look next to brew.
_term_installed() {
  [ -d "$(_term_app)" ] || return 1
  command -v macchina >/dev/null 2>&1 || [ -x "$(dirname "${GROVE_BREW:-/opt/homebrew/bin/brew}")/macchina" ]
}

# _term_extra_config: Ghostty configs in Application Support (`config` or
# `config.ghostty`) that set anything, one per line. Ghostty reads them as well
# as ~/.config/ghostty/config, so they could override Grove. Its generated
# template holds only comments and doesn't count.
_term_extra_config() {
  local d="$HOME/Library/Application Support/com.mitchellh.ghostty" f
  for f in "$d/config" "$d/config.ghostty"; do
    [ -f "$f" ] && grep -qv '^[[:space:]]*\(#.*\)\{0,1\}$' "$f" && printf '%s\n' "$f"
  done
  return 0
}

# _term_kind PLIST I: "terminal", "ghostty" or "other" for persistent-apps:I;
# fails past the last tile. Terminal is found by its path, not its label.
_term_kind() {
  local url id
  url="$("$_TERM_PB" -c "Print :persistent-apps:$2:tile-data:file-data:_CFURLString" "$1" 2>/dev/null)" || {
    "$_TERM_PB" -c "Print :persistent-apps:$2" "$1" >/dev/null 2>&1 || return 1
    url=""
  }
  id="$("$_TERM_PB" -c "Print :persistent-apps:$2:tile-data:bundle-identifier" "$1" 2>/dev/null || true)"
  case "$url" in
    */Terminal.app/) echo terminal ;;
    */Ghostty.app/) echo ghostty ;;
    *) if [ "$id" = "$_TERM_GHOSTTY_ID" ]; then echo ghostty; else echo other; fi ;;
  esac
}

# _term_dock_state PLIST: ghostty, terminal, both or neither.
_term_dock_state() {
  local i=0 k g=0 t=0
  while k="$(_term_kind "$1" "$i")"; do
    case "$k" in terminal) t=1 ;; ghostty) g=1 ;; esac
    i=$((i + 1))
  done
  case "$g$t" in 10) echo ghostty ;; 01) echo terminal ;; 11) echo both ;; *) echo neither ;; esac
}

# _term_set_ghostty PLIST I: turn tile I into Ghostty, dropping the old bookmark.
_term_set_ghostty() {
  local p=":persistent-apps:$2:tile-data"
  "$_TERM_PB" -c "Delete $p:book" "$1" >/dev/null 2>&1 || true
  "$_TERM_PB" -c "Delete $p:bundle-identifier" "$1" >/dev/null 2>&1 || true
  "$_TERM_PB" -c "Delete $p:file-type" "$1" >/dev/null 2>&1 || true
  "$_TERM_PB" -c "Delete $p:file-data" "$1" >/dev/null 2>&1 || true
  "$_TERM_PB" -c "Delete $p:file-label" "$1" >/dev/null 2>&1 || true
  "$_TERM_PB" -c "Add $p:bundle-identifier string $_TERM_GHOSTTY_ID" \
    -c "Add $p:file-type integer 41" \
    -c "Add $p:file-data dict" \
    -c "Add $p:file-data:_CFURLString string $_TERM_GHOSTTY_URL" \
    -c "Add $p:file-data:_CFURLStringType integer 15" \
    -c "Add $p:file-label string Ghostty" "$1" >/dev/null
}

# _term_dock_fix PLIST: edit the exported Dock plist in place. 0 changed,
# 2 nothing to change, 1 error.
_term_dock_fix() {
  local f="$1" state i k first=""
  state="$(_term_dock_state "$f")"
  case "$state" in
    ghostty) return 2 ;;
    neither)
      "$_TERM_PB" -c "Print :persistent-apps" "$f" >/dev/null 2>&1 \
        || "$_TERM_PB" -c "Add :persistent-apps array" "$f" >/dev/null || return 1
      "$_TERM_PB" -c "Add :persistent-apps:0 dict" \
        -c "Add :persistent-apps:0:tile-type string file-tile" \
        -c "Add :persistent-apps:0:tile-data dict" "$f" >/dev/null || return 1
      _term_set_ghostty "$f" 0 || return 1
      return 0 ;;
  esac
  # terminal or both: the first Terminal tile becomes Ghostty (when there's no
  # Ghostty yet); every other Terminal tile goes. Walk backwards so deleting
  # doesn't shift the tiles still to visit.
  i=0
  while k="$(_term_kind "$f" "$i")"; do i=$((i + 1)); done
  while [ "$i" -gt 0 ]; do
    i=$((i - 1))
    [ "$(_term_kind "$f" "$i")" = terminal ] && first="$i"
  done
  i=0
  while k="$(_term_kind "$f" "$i")"; do i=$((i + 1)); done
  while [ "$i" -gt 0 ]; do
    i=$((i - 1))
    [ "$(_term_kind "$f" "$i")" = terminal ] || continue
    if [ "$state" = terminal ] && [ "$i" = "$first" ]; then
      _term_set_ghostty "$f" "$i" || return 1
    else
      "$_TERM_PB" -c "Delete :persistent-apps:$i" "$f" >/dev/null || return 1
    fi
  done
  return 0
}

# _term_dock_export FILE: the current Dock settings. Fails when they can't be
# read; a domain that doesn't exist exports as an empty plist, which is fine.
_term_dock_export() {
  defaults export "$(_term_dock_domain)" "$1" 2>/dev/null && [ -s "$1" ]
}

check() {
  local tmp out rc state
  _term_installed || return 3
  rc=0
  out="$("$(_term_cli)" +validate-config --config-file="$GROVE_CONFIG/ghostty/config" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    grove_fail "the Ghostty config is invalid: $out"
    return 1
  fi
  [ -z "$(_term_extra_config)" ] || return 3
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/grove-dock.XXXXXX")" || return 1
  _term_dock_export "$tmp/dock.plist" || { rm -rf "$tmp"; return 1; }
  state="$(_term_dock_state "$tmp/dock.plist")"
  rm -rf "$tmp"
  [ "$state" = ghostty ] || return 3
  return 0
}

apply() {
  local tmp extra moved rc
  if ! _term_installed; then
    grove_fail "Ghostty or macchina is missing; run grove install homebrew"
    return 1
  fi
  while IFS= read -r extra; do
    [ -n "$extra" ] || continue
    moved="$(grove_backup "$extra")" || return 1
    grove_note "backed up $extra to $moved (it could override ~/.config/ghostty/config)"
  done <<EOF
$(_term_extra_config)
EOF
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/grove-dock.XXXXXX")" || return 1
  if ! _term_dock_export "$tmp/dock.plist"; then
    rm -rf "$tmp"; grove_fail "could not read the Dock settings"; return 1
  fi
  rc=0
  _term_dock_fix "$tmp/dock.plist" || rc=$?
  if [ "$rc" -eq 1 ]; then
    rm -rf "$tmp"; grove_fail "could not edit the Dock settings; the Dock is unchanged"; return 1
  fi
  if [ "$rc" -eq 0 ]; then
    if ! defaults import "$(_term_dock_domain)" "$tmp/dock.plist"; then
      rm -rf "$tmp"; grove_fail "could not save the Dock settings; the Dock is unchanged"; return 1
    fi
    killall Dock 2>/dev/null || true
    grove_info "Ghostty is in the Dock"
  fi
  rm -rf "$tmp"
  grove_note "Manual step: allow Ghostty in System Settings › Privacy & Security › Accessibility, so ⌃\` opens the quick terminal from any app."
  return 0
}
