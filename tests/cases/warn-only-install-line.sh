#!/bin/sh
# Case: --warn-only (permissive audit mode, gh #30) emits install lines that
# log a "would-block: <mod>" syslog event and then LOAD the module anyway via
# `<modprobe> --ignore-install <mod>`. Nothing is actually blocked; the file
# is an audit instrument, not an enforcement policy.
#
# Asserts:
#   1. Plain form: /bin/sh -c wrapper, logger "would-block:", then the real
#      load via --ignore-install (the exact shape requested in #30).
#   2. Verbose form composes: --warn-only --verbose-logging keeps the enriched
#      ppid/loginuid context AND the --ignore-install load, with no /bin/sh -c
#      wrapper (so $PPID resolves to modprobe, same reasoning as the enforcing
#      verbose branch).
#   3. The would-block file never carries an enforcing trailer (no `; exit 0`,
#      no `/bin/false`, no `blocked:` verb).
#   4. Mutual-exclusion + requirement rejects: --warn-only with
#      -f/--fail-on-module-load and with --no-syslog-logging are usage errors;
#      an absent modprobe is an input error.
#
# The modprobe path is overridden to a CASE_TMP fake (MODULEJAIL_MODPROBE_PATH)
# so the emitted byte-shape is deterministic across containers whose real
# modprobe lives at different paths. Skips (not fails) when /usr/bin/logger is
# absent, matching fail-on-module-load-logger.sh.
set -eu

CASE_NAME=warn-only-install-line
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/case-tree.sh disable=SC1091
. "$REPO_ROOT/tests/lib/case-tree.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

if [ ! -x /usr/bin/logger ]; then
    printf '[%s] SKIP: /usr/bin/logger not executable on this host\n' "$CASE_NAME"
    exit 77
fi

# A fake, executable modprobe so the emitted path is stable regardless of the
# host's real modprobe location (kmod at /usr/sbin, busybox at /sbin, ...).
FAKE_MODPROBE=$CASE_TMP/modprobe
printf '#!/bin/sh\n:\n' > "$FAKE_MODPROBE"
chmod +x "$FAKE_MODPROBE"
MODULEJAIL_MODPROBE_PATH=$FAKE_MODPROBE
export MODULEJAIL_MODPROBE_PATH

OUT_WARN=$CASE_TMP/out-warn.conf
OUT_WV=$CASE_TMP/out-warn-verbose.conf

# --- Run 1: plain --warn-only -----------------------------------------------
"$MODULEJAIL_BIN" --warn-only -o "$OUT_WARN" \
    > "$CASE_TMP/stdout-warn" 2> "$CASE_TMP/stderr-warn" || \
    case_fail "modulejail --warn-only exited $? (expected 0)"

# Header annotation identifies the permissive audit mode.
assert_grep '^# install-line: /bin/sh \+ logger "would-block:" \+ modprobe --ignore-install \(WARN-ONLY: module still loads, syslog tag: modulejail, --warn-only\)$' \
    "$OUT_WARN" header-warn-only-annotation

# Body: the #30 line shape. Path-agnostic (.* covers the modprobe path).
assert_grep "^install [a-zA-Z0-9_-]+ /bin/sh -c '/usr/bin/logger -t modulejail \"would-block: [a-zA-Z0-9_-]+\" 2>/dev/null; .*--ignore-install [a-zA-Z0-9_-]+'\$" \
    "$OUT_WARN" body-warn-only-form

# The fake modprobe path is actually stamped in (absolute-path contract).
if ! grep -qF "$FAKE_MODPROBE --ignore-install" "$OUT_WARN"; then
    case_fail "warn-only body does not stamp the absolute modprobe path"
fi

# A would-block file must never carry an enforcing trailer or verb.
for forbidden in '; exit 0' '/bin/false' '/bin/true' 'blocked:'; do
    if grep -qF "$forbidden" "$OUT_WARN"; then
        case_fail "warn-only body unexpectedly contains '$forbidden'"
    fi
done

# --- Run 2: --warn-only --verbose-logging (compose) -------------------------
if [ -x /usr/bin/tr ]; then
    "$MODULEJAIL_BIN" --warn-only --verbose-logging -o "$OUT_WV" \
        > "$CASE_TMP/stdout-wv" 2> "$CASE_TMP/stderr-wv" || \
        case_fail "modulejail --warn-only --verbose-logging exited $? (expected 0)"

    assert_grep '^# install-line: logger "would-block:" \+ ppid/loginuid/pcomm/pexe context \+ modprobe --ignore-install \(WARN-ONLY: module still loads, syslog tag: modulejail, --warn-only --verbose-logging\)$' \
        "$OUT_WV" header-warn-verbose-annotation

    # Enriched body: no /bin/sh -c wrapper, keeps ppid context, still loads.
    assert_grep '^install [a-zA-Z0-9_-]+ /usr/bin/logger -t modulejail "would-block: [a-zA-Z0-9_-]+ ppid=' \
        "$OUT_WV" body-warn-verbose-context
    if ! grep -qF "$FAKE_MODPROBE --ignore-install" "$OUT_WV"; then
        case_fail "warn-only --verbose-logging body does not stamp the absolute modprobe path"
    fi
    if grep -qF "/bin/sh -c" "$OUT_WV"; then
        case_fail "warn-only --verbose-logging body must not use a /bin/sh -c wrapper (breaks \$PPID)"
    fi
else
    printf '[%s] note: /usr/bin/tr absent, skipping the --verbose-logging compose sub-check\n' "$CASE_NAME"
fi

# --- Rejection: --warn-only + --fail-on-module-load (usage error) -----------
set +e
"$MODULEJAIL_BIN" --warn-only --fail-on-module-load -o "$CASE_TMP/x.conf" \
    > /dev/null 2> "$CASE_TMP/stderr-rej-f"
rc=$?
set -e
assert_eq 64 "$rc" reject-warn-plus-fail-exit
assert_grep 'warn-only and -f/--fail-on-module-load are mutually exclusive' \
    "$CASE_TMP/stderr-rej-f" reject-warn-plus-fail-msg

# --- Rejection: --warn-only + --no-syslog-logging (usage error) -------------
set +e
"$MODULEJAIL_BIN" --warn-only --no-syslog-logging -o "$CASE_TMP/x.conf" \
    > /dev/null 2> "$CASE_TMP/stderr-rej-ns"
rc=$?
set -e
assert_eq 64 "$rc" reject-warn-plus-nosyslog-exit
assert_grep 'warn-only and --no-syslog-logging are mutually exclusive' \
    "$CASE_TMP/stderr-rej-ns" reject-warn-plus-nosyslog-msg

# --- Rejection: --warn-only with no modprobe present (input error) ----------
set +e
MODULEJAIL_MODPROBE_PATH=$CASE_TMP/nonexistent-modprobe \
    "$MODULEJAIL_BIN" --warn-only -o "$CASE_TMP/x.conf" \
    > /dev/null 2> "$CASE_TMP/stderr-rej-mp"
rc=$?
set -e
assert_eq 66 "$rc" reject-warn-no-modprobe-exit
assert_grep 'warn-only requires an executable modprobe' \
    "$CASE_TMP/stderr-rej-mp" reject-warn-no-modprobe-msg

case_pass
