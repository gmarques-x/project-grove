# shellcheck shell=bash
# 40-ssh: tracked ssh config, an ed25519 key, and the key's passphrase in the
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

check() {
  [ -f "$(_ssh_key)" ] || return 4
  grove_link_check "$GROVE_CONFIG/ssh/config" "$HOME/.ssh/config" || return 3
  _ssh_loaded || _ssh_stored || return 3
  return 0
}

apply() {
  local key
  key="$(_ssh_key)"
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
