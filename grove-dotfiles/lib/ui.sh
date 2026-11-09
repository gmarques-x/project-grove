# shellcheck shell=bash
# grove output and prompt helpers. Meant to be sourced; sets no shell options.

# _grove_c <r;g;b> [fd]: print a 24-bit color escape, or nothing when color is off.
_grove_c() {
  if [ -z "${NO_COLOR:-}" ] && [ -t "${2:-1}" ]; then
    printf '\033[38;2;%sm' "$1"
  fi
}

# _grove_reset [fd]
_grove_reset() {
  if [ -z "${NO_COLOR:-}" ] && [ -t "${1:-1}" ]; then
    printf '\033[0m'
  fi
}

# _grove_status <rgb> <label> <msg> [fd]
_grove_status() {
  printf '%s%-10s%s %s\n' "$(_grove_c "$1" "${4:-1}")" "$2" "$(_grove_reset "${4:-1}")" "$3"
}

grove_ok()   { _grove_status '167;192;128' 'ok'         "$1"; }
grove_work() { _grove_status '219;188;127' 'needs work' "$1"; }
grove_you()  { _grove_status '131;192;146' 'needs you'  "$1"; }
grove_fail() { _grove_status '230;126;128' 'failed'     "$1" 2 >&2; }

grove_step() {
  printf '\n%s==> %s%s\n' "$(_grove_c '167;192;128')" "$1" "$(_grove_reset)"
}

grove_info() {
  [ "${GROVE_QUIET:-0}" = "1" ] && return 0
  printf '%s%s%s\n' "$(_grove_c '133;146;137')" "$1" "$(_grove_reset)"
}

# grove_ask PROMPT DEFAULT: prompt on stderr, read from the terminal (never
# stdin, which is the script itself under `curl | bash`), answer on stdout.
grove_ask() {
  local ans=""
  printf '%s [%s]: ' "$1" "$2" >&2
  read -r ans < "${GROVE_TTY:-/dev/tty}" || true
  printf '%s\n' "${ans:-$2}"
}
