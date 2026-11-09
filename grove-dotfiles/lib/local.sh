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

# _grove_local_value VAR PROMPT: ask for VAR when it's missing. Nothing is
# proposed. An empty answer is asked again, up to three times; then VAR stays
# empty. With GROVE_YES=1 nothing is asked and VAR stays empty.
_grove_local_value() {
  local tries=0 ans=""
  [ -n "${!1+x}" ] && return 0
  if [ "${GROVE_YES:-0}" != "1" ]; then
    while [ -z "$ans" ] && [ "$tries" -lt 3 ]; do
      ans="$(grove_ask "$2" "")"
      tries=$((tries + 1))
    done
  fi
  printf -v "$1" '%s' "$ans"
}

# grove_local_ensure: load, ask for missing values, export them. The file is
# written only when it gained values and all three are non-empty, so an empty
# value is asked again next time. A complete file is never rewritten.
grove_local_ensure() {
  local filled=0
  grove_local_load || true
  if [ -z "${GROVE_NAME+x}" ]; then _grove_local_value GROVE_NAME "Your name"; filled=1; fi
  if [ -z "${GROVE_EMAIL+x}" ]; then _grove_local_value GROVE_EMAIL "Your email"; filled=1; fi
  if [ -z "${GROVE_GITHUB_USER+x}" ]; then _grove_local_value GROVE_GITHUB_USER "Your GitHub username"; filled=1; fi
  if [ "$filled" -eq 1 ] && [ -n "$GROVE_NAME" ] && [ -n "$GROVE_EMAIL" ] && [ -n "$GROVE_GITHUB_USER" ]; then
    grove_local_write || return 1
  fi
  export GROVE_NAME GROVE_EMAIL GROVE_GITHUB_USER
}
