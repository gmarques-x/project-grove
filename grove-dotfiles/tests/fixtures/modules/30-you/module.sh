# shellcheck shell=bash
about() { echo "Needs a human"; }
check() { return 4; }
apply() { echo "30-you" >> "$HOME/apply.log"; return 0; }
