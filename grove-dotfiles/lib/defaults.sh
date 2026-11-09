# shellcheck shell=bash
# grove macOS settings helpers. Meant to be sourced; sets no shell options.
# File format, one setting per line: `domain key type value [# comment]`
# type: string | bool | int | float. Blank lines and # lines are skipped.

# _grove_defaults_norm_bool VALUE: print 1 or 0 (empty when not a bool).
_grove_defaults_norm_bool() {
  case "$1" in
    true | TRUE | True | yes | YES | 1) printf '1' ;;
    false | FALSE | False | no | NO | 0) printf '0' ;;
  esac
}

_GROVE_RE_INT='^-?[0-9]+$'
_GROVE_RE_FLOAT='^-?([0-9]+[.]?[0-9]*|[.][0-9]+)$'
_GROVE_RE_FLOAT_LIVE='^-?([0-9]+[.]?[0-9]*|[.][0-9]+)([eE][-+]?[0-9]+)?$'

# _grove_defaults_norm_int VALUE: canonical integer (no leading zeros, no -0).
_grove_defaults_norm_int() {
  local s="$1" neg=""
  case "$s" in -*) neg=-; s="${s#-}" ;; esac
  s=$(printf '%s' "$s" | sed 's/^0*//')
  if [ -z "$s" ]; then s=0; neg=""; fi
  printf '%s%s' "$neg" "$s"
}

# _grove_defaults_same TYPE LIVE WANTED: true when the live value matches.
_grove_defaults_same() {
  case "$1" in
    bool) [ "$2" = "$(_grove_defaults_norm_bool "$3")" ] ;;
    int)
      [[ "$2" =~ $_GROVE_RE_INT ]] &&
        [ "$(_grove_defaults_norm_int "$2")" = "$(_grove_defaults_norm_int "$3")" ]
      ;;
    float)
      [[ "$2" =~ $_GROVE_RE_FLOAT_LIVE ]] &&
        awk -v a="$2" -v b="$3" 'BEGIN { exit !(a + 0 == b + 0) }'
      ;;
    *) [ "$2" = "$3" ] ;;
  esac
}

# _grove_defaults_validate FILE: report malformed lines; return 1 if any.
_grove_defaults_validate() {
  local file="$1" n=0 bad=0 line domain key type value extra
  if [ ! -r "$file" ]; then
    grove_fail "settings file not readable: $file"
    return 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    # shellcheck disable=SC2162
    read -r domain key type value extra <<<"$line"
    case "$domain" in '' | '#'*) continue ;; esac
    if [ -z "$value" ] || [[ "$value" == '#'* ]]; then
      grove_fail "$file line $n: expected 'domain key type value'"
      bad=1
      continue
    fi
    if [ -n "$extra" ] && [[ "$extra" != '#'* ]]; then
      grove_fail "$file line $n: unexpected text after value (values cannot contain spaces)"
      bad=1
      continue
    fi
    case "$type" in
      string) ;;
      int)
        if ! [[ "$value" =~ $_GROVE_RE_INT ]]; then
          grove_fail "$file line $n: bad int value '$value'"
          bad=1
        fi
        ;;
      float)
        if ! [[ "$value" =~ $_GROVE_RE_FLOAT ]]; then
          grove_fail "$file line $n: bad float value '$value'"
          bad=1
        fi
        ;;
      bool)
        if [ -z "$(_grove_defaults_norm_bool "$value")" ]; then
          grove_fail "$file line $n: bad bool value '$value'"
          bad=1
        fi
        ;;
      *)
        grove_fail "$file line $n: unknown type '$type'"
        bad=1
        ;;
    esac
  done <"$file"
  [ "$bad" -eq 0 ]
}

# _grove_defaults_each FILE MODE: MODE is check (print mismatches) or apply
# (write them and print the count). Returns 0, 3 (check mismatches) or 1.
_grove_defaults_each() {
  local file="$1" mode="$2" line domain key type value extra live wanted count=0
  _grove_defaults_validate "$file" || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    # shellcheck disable=SC2162
    read -r domain key type value extra <<<"$line"
    case "$domain" in '' | '#'*) continue ;; esac
    live=$(defaults read "$domain" "$key" 2>/dev/null) || live=""
    wanted="$value"
    [ "$type" = bool ] && wanted=$(_grove_defaults_norm_bool "$value")
    _grove_defaults_same "$type" "$live" "$value" && continue
    count=$((count + 1))
    if [ "$mode" = check ]; then
      printf '%s %s: %s → %s\n' "$domain" "$key" "${live:-(unset)}" "$wanted"
    else
      if [ "$type" = bool ]; then
        [ "$wanted" = 1 ] && wanted=true || wanted=false
      fi
      defaults write "$domain" "$key" "-$type" "$wanted" || return 1
    fi
  done <"$file"
  if [ "$mode" = check ]; then
    [ "$count" -eq 0 ] || return 3
  else
    printf '%s\n' "$count"
  fi
}

grove_defaults_check() { _grove_defaults_each "$1" check; }
grove_defaults_apply() { _grove_defaults_each "$1" apply; }
