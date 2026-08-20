#!/usr/bin/env bash
# .zshrc behaviour that is easy to get wrong and impossible to notice.
#
# The completion-cache branch was unreachable for months: `(#q...)` glob
# qualifiers need EXTENDED_GLOB, and without it zsh never expands the pattern,
# the -n test sees a non-empty literal string, and every shell paid for a full
# compinit. The only symptom was "shells feel a bit slow".

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ZSHRC="$REPO_ROOT/zsh/.zshrc"

command -v zsh >/dev/null 2>&1 || skip_suite "zsh is not installed"

echo "== the file is valid zsh =="
assert ".zshrc parses" zsh -n "$ZSHRC"

echo
echo "== the compinit cache branch is reachable =="
# Extracted rather than sourced: sourcing the real .zshrc would pull in nvm,
# brew shellenv, plugins and completion dumps, and would write to the caller's
# $HOME. What matters is which branch the guard takes, so run just that.
probe() { # $1 = probe file to test against
  PROBE="$1" zsh -f -c '
    compinit() { print -r -- "compinit $*"; }
    () {
      setopt localoptions extendedglob
      if [[ -n ${PROBE}(#qN.mh-24) ]]; then compinit -C; else compinit; fi
    }
    [[ -o extendedglob ]] && print -r -- "LEAKED" || print -r -- "scoped"
  '
}

DUMP="$TEST_TMP/zcompdump"

touch "$DUMP"
out="$(probe "$DUMP")"
assert "a fresh dump takes the CACHED path (this is what was unreachable)" \
  contains "$out" "compinit -C"

touch -t "$(date -v-48H +%Y%m%d%H%M 2>/dev/null || date -d '48 hours ago' +%Y%m%d%H%M)" "$DUMP"
out="$(probe "$DUMP")"
assert "a day-old dump is rebuilt" contains "$out" "compinit"
refute "...and specifically NOT from cache" contains "$out" "compinit -C"

rm -f "$DUMP"
out="$(probe "$DUMP")"
assert "a MISSING dump is built properly rather than trusted" contains "$out" "compinit"
refute "...and specifically NOT from cache" contains "$out" "compinit -C"

assert "extendedglob does not leak out of the anonymous function" \
  contains "$out" "scoped"

# Why extendedglob is load-bearing, demonstrated rather than asserted. Note that
# a FRESH dump gives the right answer either way by coincidence — both branches
# say "use the cache" — so testing only that case would prove nothing. The
# missing-dump case is the one that separates them.
broken="$(PROBE="$TEST_TMP/definitely-absent" zsh -f -c '
  compinit() { print -r -- "compinit $*"; }
  () {
    setopt localoptions          # extendedglob deliberately NOT set
    if [[ -n ${PROBE}(#qN.mh-24) ]]; then compinit -C; else compinit; fi
  }
')"
assert "without extendedglob a MISSING dump wrongly takes the cached path" \
  contains "$broken" "compinit -C"

echo
echo "== the real .zshrc still contains that shape =="
# Anchored to the setopt line, not to any mention of extendedglob: the comment
# above it explains why it is needed, and matching that proves nothing. This is
# the same bug check.sh had.
assert "it enables extendedglob where it uses (#q...)" \
  grep -qE '^[[:space:]]*setopt[^#]*extendedglob' "$ZSHRC"
assert "it uses the mh-24 form, so a missing dump falls through to a full build" \
  grep -qE 'mh-24' "$ZSHRC"

echo
echo "== PATH cannot accumulate duplicates =="
# Every PATH entry in .zshrc prepends unconditionally, so without typeset -U a
# nested shell or a re-source stacks another copy of each.
assert "path and PATH are declared -U" \
  grep -qE '^[[:space:]]*typeset -U path PATH' "$ZSHRC"
dupes="$(zsh -f -c 'typeset -U path PATH; path=(/a /b /a /b /c); print -r -- $#path')"
assert "which really does collapse duplicates" [ "${dupes:-0}" -eq 3 ]

echo
echo "== a missing ~/.zshrc.local must not poison \$? =="
# It is the last statement in the file, so with `[[ -f x ]] && source x` and no
# override present the exit status is 1 and starship draws its error character
# before you have run a single command.
# shellcheck disable=SC2016  # a regex matching literal $HOME in the file text
assert "the override is sourced from an if, not a && chain" \
  grep -qE '^[[:space:]]*if \[\[ -f "\$HOME/\.zshrc\.local" \]\]' "$ZSHRC"
rc="$(zsh -f -c 'if [[ -f /definitely/not/here ]]; then :; fi; print -r -- $?')"
assert "so the shell starts with a clean status" [ "${rc:-1}" -eq 0 ]

finish
