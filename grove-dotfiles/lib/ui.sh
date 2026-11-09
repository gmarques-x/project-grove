# shellcheck shell=bash
# grove output and prompt helpers. Meant to be sourced; sets no shell options.

# _grove_color_on [fd]: true when color is wanted on that fd. Call it directly,
# never inside $(...), where fd 1 is the capture pipe and never a terminal.
_grove_color_on() {
  [ -z "${NO_COLOR:-}" ] || return 1
  # bin/grove sets GROVE_FORCE_COLOR to a comma list of fds ("1", "1,2") whose
  # real target is a terminal while output goes through a log pipe.
  case ",${GROVE_FORCE_COLOR:-}," in *",${1:-1},"*) return 0 ;; esac
  [ -t "${1:-1}" ]
}

# _grove_line <rgb> <text> <fd>: print text, colored when fd is a terminal.
_grove_line() {
  if _grove_color_on "$3"; then
    printf '\033[38;2;%sm%s\033[0m\n' "$1" "$2"
  else
    printf '%s\n' "$2"
  fi
}

grove_ok()   { _grove_line '167;192;128' "$(printf '%-10s %s' 'ok' "$1")" 1; }
grove_work() { _grove_line '219;188;127' "$(printf '%-10s %s' 'needs work' "$1")" 1; }
grove_you()  { _grove_line '131;192;146' "$(printf '%-10s %s' 'needs you' "$1")" 1; }
grove_fail() { _grove_line '230;126;128' "$(printf '%-10s %s' 'failed' "$1")" 2 >&2; }

grove_step() {
  printf '\n'
  _grove_line '167;192;128' "==> $1" 1
}

grove_info() {
  [ "${GROVE_QUIET:-0}" = "1" ] && return 0
  _grove_line '133;146;137' "$1" 1
}

# grove_note MSG: like grove_info but never hidden by --quiet (changes the user
# must be able to find, such as backups).
grove_note() { _grove_line '133;146;137' "$1" 1; }

# grove_ask PROMPT DEFAULT: prompt on stderr, read from the terminal (never
# stdin, which is the script itself under `curl | bash`), answer on stdout.
grove_ask() {
  local ans=""
  printf '%s [%s]: ' "$1" "$2" >&2
  read -r ans < "${GROVE_TTY:-/dev/tty}" || true
  printf '%s\n' "${ans:-$2}"
}
