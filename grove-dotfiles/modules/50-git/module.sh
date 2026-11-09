# shellcheck shell=bash
# 50-git: generated identity (config/git/local) and allowed_signers, and the
# old ~/.gitconfig retired.

about() { echo "git identity and commit signing"; }

_git_pub() { echo "$HOME/.ssh/id_ed25519.pub"; }

# _git_escape VALUE: make VALUE safe inside a double-quoted git config value.
_git_escape() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\"/\\\"}"
  printf '%s' "$v"
}

_git_local_content() {
  printf '[user]\n'
  printf '    name = "%s"\n' "$(_git_escape "${GROVE_NAME-}")"
  printf '    email = "%s"\n' "$(_git_escape "${GROVE_EMAIL-}")"
  printf '    signingkey = %s\n' "$(_git_pub)"
}

_git_signers_content() {
  local type key
  read -r type key _ < "$(_git_pub)" || return 1
  printf '%s %s %s\n' "${GROVE_EMAIL-}" "$type" "$key"
}

# _git_same FILE GENERATOR: 0 when FILE already has exactly the generated text.
_git_same() {
  [ -f "$1" ] || return 1
  [ "$(cat "$1"; echo x)" = "$("$2"; echo x)" ]
}

# _git_write FILE GENERATOR: write atomically (temp + mv), only when different.
_git_write() {
  local file="$1" gen="$2" tmp
  _git_same "$file" "$gen" && return 0
  mkdir -p "$(dirname "$file")" || return 1
  tmp="$(mktemp "$(dirname "$file")/.grove.XXXXXX")" || return 1
  if ! "$gen" > "$tmp"; then rm -f "$tmp"; return 1; fi
  chmod 644 "$tmp"
  mv -f "$tmp" "$file"
}

check() {
  [ -n "${GROVE_NAME-}" ] && [ -n "${GROVE_EMAIL-}" ] || return 4
  [ -f "$(_git_pub)" ] || return 4
  if [ -f "$HOME/.gitconfig" ] && [ ! -L "$HOME/.gitconfig" ]; then return 3; fi
  _git_same "$GROVE_CONFIG/git/local" _git_local_content || return 3
  _git_same "$GROVE_CONFIG/git/allowed_signers" _git_signers_content || return 3
  return 0
}

apply() {
  local moved
  if [ -z "${GROVE_NAME-}" ] || [ -z "${GROVE_EMAIL-}" ]; then
    grove_fail "set your name and email: edit ~/.config/grove/local.env or run grove install without --yes"
    return 1
  fi
  if [ ! -f "$(_git_pub)" ]; then
    grove_fail "no public key at $(_git_pub)"
    return 1
  fi
  _git_write "$GROVE_CONFIG/git/local" _git_local_content \
    || { grove_fail "could not write config/git/local"; return 1; }
  _git_write "$GROVE_CONFIG/git/allowed_signers" _git_signers_content \
    || { grove_fail "could not write config/git/allowed_signers"; return 1; }
  if [ -f "$HOME/.gitconfig" ] && [ ! -L "$HOME/.gitconfig" ]; then
    moved="$(grove_backup "$HOME/.gitconfig")" || return 1
    grove_note "backed up $HOME/.gitconfig to $moved"
  fi
}
