#!/usr/bin/env bash
# Shared helpers for the exercise checkers. Source this file. Do not run it.
#
# Every AWS call uses `--profile floci`. Without the lab environment, that
# profile does not exist, so a checker cannot reach a real AWS account.

set -uo pipefail

PASSED=0
FAILED=0

require_lab_env() {
  if [ "${AWS_PROFILE:-}" != "floci" ]; then
    echo "ERROR: The lab environment is not loaded." >&2
    echo "Run the checker from a folder inside the lab, in a shell where mise is active." >&2
    exit 2
  fi
  if ! curl -fsS -m 3 http://localhost:4566/_floci/health >/dev/null 2>&1; then
    echo "ERROR: The emulator does not answer on localhost:4566. Run: mise run up" >&2
    exit 2
  fi
}

# The AWS CLI, locked to the lab profile.
awsl() { aws --profile floci "$@"; }

# check "<description>" <command> [args...]
# The command passes when it exits with 0. Its output is hidden.
check() {
  local description=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf '  PASS  %s\n' "$description"
    PASSED=$((PASSED + 1))
  else
    printf '  FAIL  %s\n' "$description"
    FAILED=$((FAILED + 1))
  fi
}

section() { printf '\n%s\n' "$1"; }

summary() {
  echo
  if [ "$FAILED" -eq 0 ]; then
    echo "All $PASSED checks passed."
    exit 0
  fi
  echo "$FAILED of $((PASSED + FAILED)) checks failed. Read the Hints section of the README."
  exit 1
}
