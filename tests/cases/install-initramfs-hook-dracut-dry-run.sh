#!/bin/sh
# Case: --install-initramfs-hook --dry-run on a dracut-simulated host
# prints the dracut target paths and the recommended regen command, and
# does NOT write any file.
#
# Uses MODULEJAIL_INITRAMFS_BUILDER=dracut to force detection without
# requiring dracut to be installed on the dev host.
set -eu

CASE_NAME=install-initramfs-hook-dracut-dry-run
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

set +e
MODULEJAIL_INITRAMFS_BUILDER=dracut \
    "$MODULEJAIL_BIN" --install-initramfs-hook --dry-run \
    > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr"
rc=$?
set -e

assert_eq 0 "$rc" "dracut-dry-run-exit-code"

assert_grep '^modulejail: dry-run: would write /usr/lib/dracut/modules.d/99modulejail-strip/module-setup.sh \(0755\)$' \
    "$CASE_TMP/stdout" dracut-dry-run-target-path
assert_grep 'dracut --force --regenerate-all' \
    "$CASE_TMP/stdout" dracut-dry-run-regen-command

# Sentinel: no real write happened.
if [ -e /usr/lib/dracut/modules.d/99modulejail-strip/module-setup.sh ]; then
    case_fail "--dry-run wrote the dracut module file (should be no-op)"
fi

case_pass
