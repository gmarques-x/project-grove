# shellcheck disable=SC2016,SC2030,SC2031,SC1090,SC1091,SC2154
load helpers

load_module() {
  local f
  for f in "$GROVE_ROOT"/lib/*.sh; do
    # shellcheck source=/dev/null
    . "$f"
  done
  MODULE_DIR="$GROVE_ROOT/modules/$1"
  # shellcheck source=/dev/null
  . "$MODULE_DIR/module.sh"
}

setup() {
  grove_test_setup
  export GROVE_GITHUB_USER=gmx GROVE_EMAIL=gm@example.com
  # Stateful gh stub mimicking gh 2.103; never the real gh.
  #   $T/auth_rc   exit code of `gh auth status` (default 0)
  #   $T/auth_out  its output (default: signed in with the signing scope)
  #   $T/keys      stdout of `gh ssh-key list`
  #   $T/keys_err  stderr of `gh ssh-key list`
  export GROVE_GH="$BATS_TEST_TMPDIR/stubs/gh"
  stub gh 'T="$BATS_TEST_TMPDIR"
echo "$@" >> "$T/gh.log"
case "$1 $2" in
  "auth status")
    if [ -f "$T/auth_out" ]; then cat "$T/auth_out" >&2; else
      printf "github.com\n  ✓ Logged in to github.com account gmarques-x (keyring)\n  - Active account: true\n  - Git operations protocol: https\n  - Token: gho_************************************\n  - Token scopes: %s\n" "'"'"'admin:ssh_signing_key'"'"', '"'"'gist'"'"', '"'"'read:org'"'"', '"'"'repo'"'"', '"'"'workflow'"'"'" >&2
    fi
    exit "$(cat "$T/auth_rc" 2>/dev/null || echo 0)" ;;
  "ssh-key list")
    cat "$T/keys" 2>/dev/null
    cat "$T/keys_err" 2>/dev/null >&2
    exit 0 ;;
  *) exit 0 ;;
esac'
  stub scutil 'echo "MacBook Air"'
}

make_key() {
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  /usr/bin/ssh-keygen -q -t ed25519 -N '' -C "$GROVE_EMAIL" -f "$HOME/.ssh/id_ed25519"
}

# upload_key TYPE: list the key as TYPE (signing|authentication)
upload_key() {
  local k
  k="$(cut -d' ' -f1,2 "$HOME/.ssh/id_ed25519.pub")"
  printf 'MacBook Air · Project Grove\t%s\t2026-11-09T03:17:54Z\t1314060\t%s\n' "$k" "$1" >> "$BATS_TEST_TMPDIR/keys"
}

@test "github needs you without a public key" {
  load_module 60-github
  run check
  [ "$status" -eq 4 ]
}

@test "github needs you when signed out" {
  load_module 60-github
  make_key
  echo 1 > "$BATS_TEST_TMPDIR/auth_rc"
  echo "You are not logged into any GitHub hosts. To log in, run: gh auth login" > "$BATS_TEST_TMPDIR/auth_out"
  run check
  [ "$status" -eq 4 ]
}

@test "github needs you without the signing scope" {
  load_module 60-github
  make_key
  printf "github.com\n  ✓ Logged in to github.com account gmarques-x (keyring)\n  - Token scopes: 'gist', 'read:org', 'repo'\n" > "$BATS_TEST_TMPDIR/auth_out"
  run check
  [ "$status" -eq 4 ]
}

@test "github needs work when the key isn't uploaded" {
  load_module 60-github
  make_key
  run check
  [ "$status" -eq 3 ]
}

@test "github needs work when the key is only an authentication key" {
  load_module 60-github
  make_key; upload_key authentication
  run check
  [ "$status" -eq 3 ]
}

@test "github is ok when uploaded as a signing key" {
  load_module 60-github
  make_key; upload_key signing
  run check
  [ "$status" -eq 0 ]
}

@test "github ignores the stderr warning about authentication keys" {
  load_module 60-github
  make_key; upload_key signing
  echo "warning: your token lacks admin:public_key; authentication keys are not listed" > "$BATS_TEST_TMPDIR/keys_err"
  run check
  [ "$status" -eq 0 ]
}

@test "github apply uploads as a signing key with the computer name" {
  load_module 60-github
  make_key
  run apply
  [ "$status" -eq 0 ]
  grep -qF -- "ssh-key add $HOME/.ssh/id_ed25519.pub --type signing --title MacBook Air · Project Grove" "$BATS_TEST_TMPDIR/gh.log"
  run grep -q 'auth login' "$BATS_TEST_TMPDIR/gh.log"
  [ "$status" -ne 0 ]
  run grep -q 'auth refresh' "$BATS_TEST_TMPDIR/gh.log"
  [ "$status" -ne 0 ]
}

@test "github apply falls back to hostname -s when scutil fails" {
  load_module 60-github
  make_key
  stub scutil 'exit 1'
  stub hostname 'echo mymac'
  run apply
  [ "$status" -eq 0 ]
  grep -qF -- "--title mymac · Project Grove" "$BATS_TEST_TMPDIR/gh.log"
}

@test "github apply logs in when signed out" {
  load_module 60-github
  make_key
  echo 1 > "$BATS_TEST_TMPDIR/auth_rc"
  run apply
  [ "$status" -eq 0 ]
  grep -qF -- "auth login --hostname github.com --git-protocol https --web --scopes admin:ssh_signing_key,workflow" "$BATS_TEST_TMPDIR/gh.log"
  grep -q -- '--type signing' "$BATS_TEST_TMPDIR/gh.log"
}

@test "github apply refreshes when the scope is missing" {
  load_module 60-github
  make_key
  printf "github.com\n  - Token scopes: 'repo'\n" > "$BATS_TEST_TMPDIR/auth_out"
  run apply
  [ "$status" -eq 0 ]
  grep -qF -- "auth refresh -h github.com -s admin:ssh_signing_key" "$BATS_TEST_TMPDIR/gh.log"
  run grep -q 'auth login' "$BATS_TEST_TMPDIR/gh.log"
  [ "$status" -ne 0 ]
}

@test "github apply does not re-upload an uploaded key" {
  load_module 60-github
  make_key; upload_key signing
  run apply
  [ "$status" -eq 0 ]
  run grep -q 'ssh-key add' "$BATS_TEST_TMPDIR/gh.log"
  [ "$status" -ne 0 ]
}
