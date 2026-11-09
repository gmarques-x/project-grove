# shellcheck shell=bash
# Personal values (name, email, GitHub user), stored outside git in $GROVE_LOCAL.
# Meant to be sourced; sets no shell options. Needs lib/ui.sh for grove_ask.

# grove_local_load: source $GROVE_LOCAL if present. 0 when all three values are
# set (empty counts as set), 3 otherwise.
grove_local_load() {
  # shellcheck disable=SC1090
  [ -f "$GROVE_LOCAL" ] && . "$GROVE_LOCAL"
  if [ -n "${GROVE_NAME+x}" ] && [ -n "${GROVE_EMAIL+x}" ] && [ -n "${GROVE_GITHUB_USER+x}" ]; then
    return 0
  fi
  return 3
}

# grove_local_write: write the three variables to $GROVE_LOCAL, mode 600, via a
# temp file in the same folder so a crash never leaves a half-written file.
grove_local_write() {
  local dir tmp
  dir="$(dirname "$GROVE_LOCAL")"
  mkdir -p "$dir" || return 1
  chmod 700 "$dir" 2>/dev/null || true
  tmp="$(mktemp "$dir/.local.env.XXXXXX")" || return 1
  chmod 600 "$tmp"
  {
    printf '%s=%q\n' GROVE_NAME "${GROVE_NAME-}"
    printf '%s=%q\n' GROVE_EMAIL "${GROVE_EMAIL-}"
    printf '%s=%q\n' GROVE_GITHUB_USER "${GROVE_GITHUB_USER-}"
  } > "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$GROVE_LOCAL"
}

# _grove_local_value VAR PROMPT DEFAULT: set VAR if missing, from the default
# when GROVE_YES=1, otherwise by asking.
_grove_local_value() {
  [ -n "${!1+x}" ] && return 0
  if [ "${GROVE_YES:-0}" = "1" ]; then
    printf -v "$1" '%s' "$3"
  else
    printf -v "$1" '%s' "$(grove_ask "$2" "$3")"
  fi
}

# grove_local_ensure: load, fill missing values (defaults from git config; the
# GitHub default is the name), write the file, export the variables.
grove_local_ensure() {
  local def_name def_email
  grove_local_load || true
  if [ -z "${GROVE_NAME+x}" ]; then
    def_name="$(git config --global user.name 2>/dev/null || true)"
    _grove_local_value GROVE_NAME "Your name" "$def_name"
  fi
  if [ -z "${GROVE_EMAIL+x}" ]; then
    def_email="$(git config --global user.email 2>/dev/null || true)"
    _grove_local_value GROVE_EMAIL "Your email" "$def_email"
  fi
  _grove_local_value GROVE_GITHUB_USER "Your GitHub username" "$GROVE_NAME"
  grove_local_write || return 1
  export GROVE_NAME GROVE_EMAIL GROVE_GITHUB_USER
}
