# shellcheck shell=bash
# 60-github: GitHub login with the signing-key scope, and the SSH key uploaded
# as a signing key.

about() { echo "GitHub login and SSH signing key"; }

_gh_pub() { echo "$HOME/.ssh/id_ed25519.pub"; }

# _gh: GROVE_GH, else gh from PATH, else the Homebrew location.
_gh() {
  if [ -n "${GROVE_GH-}" ]; then echo "$GROVE_GH"; return; fi
  command -v gh 2>/dev/null || echo /opt/homebrew/bin/gh
}

# _gh_status: print `gh auth status` output (stdout and stderr); returns its exit code.
_gh_status() { "$(_gh)" auth status 2>&1; }

# _gh_has_scope OUTPUT: 0 when the "Token scopes:" line lists admin:ssh_signing_key.
_gh_has_scope() {
  printf '%s\n' "$1" | grep -i 'token scopes' | tr -d "'\"," | tr ' ' '\n' \
    | grep -qx 'admin:ssh_signing_key'
}

# _gh_key_text: "<type> <base64>" of the public key.
_gh_key_text() {
  local type key
  read -r type key _ < "$(_gh_pub)" || return 1
  printf '%s %s' "$type" "$key"
}

# _gh_uploaded: 0 when the key is among the signing rows of `gh ssh-key list`.
# Rows are TITLE<TAB>KEY<TAB>CREATED<TAB>ID<TAB>TYPE; stderr warnings are dropped.
_gh_uploaded() {
  local want list
  want="$(_gh_key_text)" || return 1
  list="$("$(_gh)" ssh-key list 2>/dev/null)" || return 1
  printf '%s\n' "$list" | awk -F '\t' -v want="$want" '
    $5 == "signing" {
      split($2, a, " ")
      if (a[1] " " a[2] == want) found = 1
    }
    END { exit found ? 0 : 1 }'
}

_gh_title() {
  local name
  name="$(scutil --get ComputerName 2>/dev/null)" || name=""
  [ -n "$name" ] || name="$(hostname -s)"
  printf '%s · Project Grove' "$name"
}

check() {
  local out
  [ -f "$(_gh_pub)" ] || return 4
  out="$(_gh_status)" || return 4
  _gh_has_scope "$out" || return 4
  _gh_uploaded || return 3
  return 0
}

apply() {
  local out gh
  gh="$(_gh)"
  if [ ! -f "$(_gh_pub)" ]; then
    grove_fail "no public key at $(_gh_pub)"
    return 1
  fi
  if ! out="$(_gh_status)"; then
    "$gh" auth login --hostname github.com --git-protocol https --web \
      --scopes admin:ssh_signing_key,workflow \
      || { grove_fail "gh auth login failed"; return 1; }
  elif ! _gh_has_scope "$out"; then
    "$gh" auth refresh -h github.com -s admin:ssh_signing_key \
      || { grove_fail "gh auth refresh failed"; return 1; }
  fi
  if ! _gh_uploaded; then
    "$gh" ssh-key add "$(_gh_pub)" --type signing --title "$(_gh_title)" \
      || { grove_fail "gh ssh-key add failed"; return 1; }
  fi
}
