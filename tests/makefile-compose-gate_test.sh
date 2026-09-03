#!/usr/bin/env bash
# Regression gate: `make compose-config` must validate every Compose stack and
# stop at the first invalid one.
#
# The failure this locks out: the recipe used to run
#
#     for file in docker-compose*.yml; do docker compose -f "$file" config --quiet; done
#
# A shell `for` loop exits with the status of its *last* iteration, so an
# invalid docker-compose*.yml anywhere but the alphabetically last file left the
# recipe — and `make test` — green. The gate is only useful if it is also
# reachable, so `test` must depend on the target.
#
# Hermetic: the recipe is taken from the Makefile itself via `make -n` (which
# expands and prints, but never executes) and evaluated with `docker` stubbed by
# a shell function. No container is pulled, started or validated for real.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# --- The gate is wired into `make test` -------------------------------------
grep -Eq '^test:[^#]*[[:space:]]compose-config([[:space:]]|$|#)' Makefile \
  || fail "Makefile: 'test' must depend on 'compose-config', otherwise no Compose stack is ever validated"

# --- The recipe make would actually run -------------------------------------
# MAKEFLAGS/MAKELEVEL are unset so this works when it runs from inside `make`.
RECIPE="$(env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL make -n compose-config)"
[ -n "$RECIPE" ] \
  || fail "make -n compose-config produced no recipe; is compose-config declared .PHONY?"

case "$RECIPE" in
  *"|| exit 1"*) ;;
  *) fail "compose-config must run 'docker compose ... config || exit 1'; a bare loop reports only the last file's status" ;;
esac

# --- Run the real recipe against a stubbed docker ---------------------------
# `eval` runs in the current (sub)shell, so the function below shadows the
# docker binary. Callers wrap this in a command substitution, which keeps the
# recipe's `exit 1` from ending this script.
run_recipe() {
  local fail_file="${1:-}"

  # shellcheck disable=SC2329,SC2317  # invoked indirectly: `eval "$RECIPE"` below
  # runs `docker compose ...`, which resolves to this function, not the binary.
  docker() {
    local arg prev="" file=""
    for arg in "$@"; do
      [ "$prev" = "-f" ] && file="$arg"
      prev="$arg"
    done
    echo "VALIDATED $file"
    [ "$file" != "$fail_file" ]
  }

  eval "$RECIPE"
}

validated_files() {
  sed -n 's/^VALIDATED //p' <<<"$1"
}

# --- 1. Positive control: every stack is validated when all of them parse ----
status=0
output="$(run_recipe)" || status=$?
[ "$status" -eq 0 ] \
  || fail "compose-config failed even though every stack validated (exit $status)"

ORDER=()
while IFS= read -r f; do
  [ -n "$f" ] && ORDER+=("$f")
done < <(validated_files "$output")

expected_count="$(find . -maxdepth 1 -name 'docker-compose*.yml' | wc -l | tr -d ' ')"
[ "${#ORDER[@]}" -eq "$expected_count" ] \
  || fail "compose-config validated ${#ORDER[@]} stacks but the repository ships $expected_count"

[ "${#ORDER[@]}" -ge 2 ] \
  || fail "expected at least two docker-compose*.yml files; with one file the loop cannot regress"

first="${ORDER[0]}"
second="${ORDER[1]}"
last="${ORDER[$(( ${#ORDER[@]} - 1 ))]}"

# --- 2. A failure on the first stack must stop the loop immediately ----------
status=0
output="$(run_recipe "$first")" || status=$?

[ "$status" -ne 0 ] \
  || fail "compose-config exited 0 while $first was invalid; a non-last failure is being masked"

grep -Fq "VALIDATED $first" <<<"$output" \
  || fail "compose-config never validated $first"

if grep -Fq "VALIDATED $second" <<<"$output"; then
  fail "compose-config kept going after $first failed (it also validated $second); it must fail immediately"
fi

# --- 3. A failure on the last stack still fails -----------------------------
# This is the only case the unguarded loop caught. Keep it, so a "fix" that
# merely reorders the glob cannot pass.
status=0
output="$(run_recipe "$last")" || status=$?
[ "$status" -ne 0 ] \
  || fail "compose-config exited 0 while the last stack ($last) was invalid"

echo "makefile-compose-gate: compose-config validates all ${#ORDER[@]} stacks and fails closed on the first invalid one"
