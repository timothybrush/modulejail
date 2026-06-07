#!/bin/sh
# Case: --help lists the v1.4 --self-update flag.
# Catches regressions where the flag is added to the parser but not
# documented to operators.
set -eu

CASE_NAME=self-update-help-listed
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

"$MODULEJAIL_BIN" --help > "$CASE_TMP/help" 2>&1 || \
    case_fail "modulejail --help exited non-zero"

assert_grep '^  --self-update' "$CASE_TMP/help" self-update-flag-listed
assert_grep 'SYSADMIN WHITELIST' "$CASE_TMP/help" self-update-region-mentioned
assert_grep 'apt/dnf/pacman' "$CASE_TMP/help" self-update-routes-to-package-manager

case_pass
