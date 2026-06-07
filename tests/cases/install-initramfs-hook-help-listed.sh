#!/bin/sh
# Case: --help lists the v1.4 initramfs hook flags
# (--install-initramfs-hook, --uninstall-initramfs-hook, --yes).
# Catches regressions where a new flag is added to the parser but not
# documented to operators.
set -eu

CASE_NAME=install-initramfs-hook-help-listed
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

"$MODULEJAIL_BIN" --help > "$CASE_TMP/help" 2>&1 || \
    case_fail "modulejail --help exited non-zero"

assert_grep '^  --install-initramfs-hook' "$CASE_TMP/help" install-flag-listed
assert_grep '^  --uninstall-initramfs-hook' "$CASE_TMP/help" uninstall-flag-listed
assert_grep '^  -y, --yes' "$CASE_TMP/help" yes-flag-listed

case_pass
