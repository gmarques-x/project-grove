# shellcheck shell=bash
about() { echo "Always fine"; }
check() { return 0; }
apply() { echo "10-ok" >> "$HOME/apply.log"; return 0; }
