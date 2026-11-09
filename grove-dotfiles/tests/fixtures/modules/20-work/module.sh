# shellcheck shell=bash
about() { echo "Needs applying once"; }
check() { [ -e "$HOME/applied-20" ] && return 0; return 3; }
apply() { echo "20-work" >> "$HOME/apply.log"; touch "$HOME/applied-20"; }
