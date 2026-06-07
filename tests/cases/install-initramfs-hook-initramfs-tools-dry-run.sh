#!/bin/sh
# Case: --install-initramfs-hook --dry-run on an initramfs-tools-simulated
# host prints the initramfs-tools target path and the recommended regen
# command, and does NOT write any file.
set -eu

CASE_NAME=install-initramfs-hook-initramfs-tools-dry-run
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

set +e
MODULEJAIL_INITRAMFS_BUILDER=initramfs-tools \
    "$MODULEJAIL_BIN" --install-initramfs-hook --dry-run \
    > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr"
rc=$?
set -e

assert_eq 0 "$rc" "initramfs-tools-dry-run-exit-code"

assert_grep '^modulejail: dry-run: would write /etc/initramfs-tools/hooks/zz-modulejail-strip \(0755\)$' \
    "$CASE_TMP/stdout" initramfs-tools-dry-run-target-path
assert_grep 'update-initramfs -u -k all' \
    "$CASE_TMP/stdout" initramfs-tools-dry-run-regen-command

if [ -e /etc/initramfs-tools/hooks/zz-modulejail-strip ]; then
    case_fail "--dry-run wrote the initramfs-tools hook file (should be no-op)"
fi

case_pass
