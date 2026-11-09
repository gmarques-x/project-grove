# A macchina summary once per new terminal window. GROVE_FETCHED is inherited
# by every shell started from this one (nested shells, exec zsh, tools), so
# they stay quiet. Turn it off with GROVE_NO_FETCH=1.
if [[ -o interactive && -t 1 && -z "$GROVE_FETCHED" && -z "$GROVE_NO_FETCH" ]] \
  && [[ "$TERM_PROGRAM" == ghostty || "$TERM_PROGRAM" == Apple_Terminal ]] \
  && (( $+commands[macchina] )); then
  macchina || true
  export GROVE_FETCHED=1
fi
