# shellcheck shell=bash
about() { echo "Always fails"; }
check() { return 3; }
apply() { echo "40-broken" >> "$HOME/apply.log"; return 1; }
