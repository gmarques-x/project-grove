# shellcheck shell=bash
# 10-xcode-tools: Command Line Tools for Xcode.

about() { echo "Xcode command line tools"; }

check() {
  xcode-select -p >/dev/null 2>&1 && return 0
  return 4
}

apply() {
  grove_info "a dialog asks to install the command line tools; click Install"
  # Fails when a request is already pending; waiting below covers both cases.
  xcode-select --install >/dev/null 2>&1 || true
  until xcode-select -p >/dev/null 2>&1; do
    sleep "${GROVE_POLL_SECONDS:-5}"
  done
}
