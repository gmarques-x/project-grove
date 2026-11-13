# shellcheck shell=bash
# 40-ssh: where ~/.ssh lives (on this Mac or in a OneDrive folder as dot-ssh),
# the tracked ssh config, an ed25519 key, and the key's passphrase in the
# Keychain. The agent loads the key on first use (UseKeychain, AddKeysToAgent in
# the config), so after a restart it isn't in the agent yet and that is fine.

about() { echo "ssh config, ed25519 key and agent"; }

_ssh_key() { echo "$HOME/.ssh/id_ed25519"; }

# _ssh_loaded: 0 when the key's fingerprint is listed by ssh-add -l.
_ssh_loaded() {
  local fp
  fp="$(ssh-keygen -lf "$(_ssh_key).pub" 2>/dev/null | awk '{print $2}')"
  [ -n "$fp" ] || return 1
  ssh-add -l 2>/dev/null | grep -qF "$fp"
}

# _ssh_stored: 0 when apply has put this key's passphrase in the Keychain (a
# marker with the key's fingerprint; a new key needs a new ssh-add).
_ssh_marker() { echo "$GROVE_STATE/ssh-keychain"; }
_ssh_stored() {
  local fp
  fp="$(ssh-keygen -lf "$(_ssh_key).pub" 2>/dev/null | awk '{print $2}')"
  [ -n "$fp" ] && [ "$(cat "$(_ssh_marker)" 2>/dev/null)" = "$fp" ]
}

# ---- where ~/.ssh lives
# ~/.ssh can live in a OneDrive folder as "dot-ssh", with ~/.ssh a symlink to it.
# The OneDrive folder's name differs per Mac (OneDrive-Personal at home,
# "OneDrive-<Company>" at work), so install asks which one, once. The answer is
# the link itself; choosing to keep ~/.ssh on this Mac is remembered in
# $GROVE_STATE/ssh-place ("local").

_ssh_clouds() { echo "${GROVE_CLOUD_STORAGE:-$HOME/Library/CloudStorage}"; }
_ssh_place_file() { echo "$GROVE_STATE/ssh-place"; }

# _ssh_onedrives: the OneDrive folders on this Mac, one per line, sorted.
_ssh_onedrives() {
  local d
  for d in "$(_ssh_clouds)"/OneDrive*; do
    [ -d "$d" ] && printf '%s\n' "$d"
  done
}

# _ssh_placed: 0 when where ~/.ssh lives is settled: ~/.ssh is a symlink to an
# existing dot-ssh folder, "local" was chosen, or there is no OneDrive to ask
# about. 4 when install has to ask.
_ssh_placed() {
  if [ -L "$HOME/.ssh" ]; then
    [ -d "$HOME/.ssh" ] && [ "$(basename "$(readlink "$HOME/.ssh")")" = "dot-ssh" ] && return 0
    return 4
  fi
  [ "$(cat "$(_ssh_place_file)" 2>/dev/null)" = "local" ] && return 0
  [ -z "$(_ssh_onedrives)" ] && return 0
  return 4
}

# _ssh_choose: print the OneDrive folders and ask for one, "local", or a path.
# Prints the chosen folder, or "local". Under --yes it chooses nothing (1).
_ssh_choose() {
  local i=0 d ans list
  [ "${GROVE_YES:-0}" = "1" ] && return 1
  list="$(_ssh_onedrives)"
  printf 'Where should ~/.ssh live? It becomes a link to <folder>/dot-ssh.\n' >&2
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    i=$((i + 1)); printf '  %d  %s\n' "$i" "$d" >&2
  done <<<"$list"
  printf '  0  keep ~/.ssh on this Mac\n' >&2
  ans="$(grove_ask "Number, or another folder's path" "1")"
  case "$ans" in
    0) echo local ;;
    /*) [ -d "$ans" ] || { grove_fail "no folder $ans"; return 1; }; echo "${ans%/}" ;;
    *[!0-9]*|'') grove_fail "not a choice: $ans"; return 1 ;;
    *) d="$(sed -n "${ans}p" <<<"$list")"
       [ -n "$d" ] || { grove_fail "not a choice: $ans"; return 1; }
       echo "$d" ;;
  esac
}

# _ssh_move_to FOLDER: make ~/.ssh a link to FOLDER/dot-ssh. Files in an
# existing ~/.ssh that dot-ssh lacks are copied in (nothing in dot-ssh is
# overwritten; agent sockets are left out), then ~/.ssh is moved to the backup.
_ssh_move_to() {
  local dot="$1/dot-ssh" moved
  if [ ! -d "$dot" ]; then
    mkdir -m 700 "$dot" || { grove_fail "could not create $dot"; return 1; }
  fi
  chmod 700 "$dot" 2>/dev/null || true
  if [ -d "$HOME/.ssh" ] && [ ! -L "$HOME/.ssh" ]; then
    rsync -a --ignore-existing --exclude 'agent/' "$HOME/.ssh/" "$dot/" \
      || { grove_fail "could not copy ~/.ssh into $dot"; return 1; }
    moved="$(grove_backup "$HOME/.ssh")" || return 1
    grove_note "backed up ~/.ssh to $moved"
  fi
  ln -s "$dot" "$HOME/.ssh" || { grove_fail "could not link ~/.ssh to $dot"; return 1; }
  grove_note "$HOME/.ssh is now a link to $dot"
}

_ssh_place() {
  local where
  _ssh_placed && return 0
  where="$(_ssh_choose)" || return 1
  if [ "$where" = "local" ]; then
    mkdir -p "$GROVE_STATE" && echo local > "$(_ssh_place_file)"
    return 0
  fi
  _ssh_move_to "$where"
}

check() {
  _ssh_placed || return 4
  [ -f "$(_ssh_key)" ] || return 4
  grove_link_check "$GROVE_CONFIG/ssh/config" "$HOME/.ssh/config" || return 3
  _ssh_loaded || _ssh_stored || return 3
  return 0
}

apply() {
  local key
  key="$(_ssh_key)"
  _ssh_place || return 1
  if [ ! -d "$HOME/.ssh" ]; then
    mkdir -m 700 "$HOME/.ssh" || { grove_fail "could not create $HOME/.ssh"; return 1; }
  fi
  grove_link "$GROVE_CONFIG/ssh/config" "$HOME/.ssh/config" || return 1
  if [ ! -f "$key" ]; then
    ssh-keygen -t ed25519 -C "${GROVE_EMAIL-}" -f "$key" \
      || { grove_fail "ssh-keygen failed"; return 1; }
  fi
  if ! _ssh_stored; then
    if ! _ssh_loaded; then
      ssh-add --apple-use-keychain "$key" || { grove_fail "ssh-add failed"; return 1; }
    fi
    mkdir -p "$GROVE_STATE"
    ssh-keygen -lf "$key.pub" 2>/dev/null | awk '{print $2}' > "$(_ssh_marker)"
  fi
}
