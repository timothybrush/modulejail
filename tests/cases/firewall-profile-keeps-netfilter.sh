#!/bin/sh
# Case: the firewall profile keeps the netfilter toolkit (iptables/nftables/
# ipset/IPVS match, target, and helper modules) that conservative blacklists
# (gh #16, reported by teou1: xt_recent got blacklisted because the firewall
# was down when modulejail ran, then a later rule using it failed to load).
#
# Netfilter match/target modules autoload on demand when a rule first
# references them, so a firewall host whose full rule set is not active at
# run time would otherwise lose them. The firewall profile keeps the whole
# subsystem:
#   -p firewall      => xt_recent, xt_hashlimit, nf_conntrack, ip_vs kept
#                       even when unloaded
#   -p conservative  => same modules blacklisted (servers that are not
#                       firewalls do not need the netfilter toolkit)
# The conservative arm is the discriminating control: if it ever stops
# blacklisting these, the firewall keep is no longer proving anything.
set -eu

CASE_NAME=firewall-profile-keeps-netfilter
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/case-tree.sh disable=SC1091
. "$REPO_ROOT/tests/lib/case-tree.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

# Add a representative slice of the netfilter subsystem to the synthetic
# universe as available but UNLOADED (absent from case-tree.sh's fake
# /proc/modules). One from each major family exercised by the profile.
NFDIR="$MODULEJAIL_MODULES_ROOT/$MODULEJAIL_KVER/kernel/net/netfilter"
mkdir -p "$NFDIR"
for m in xt_recent xt_hashlimit nf_conntrack ip_vs; do
    touch "$NFDIR/$m.ko.zst"
done

# --- firewall: the netfilter modules MUST be kept ---
FW=$CASE_TMP/firewall.conf
"$MODULEJAIL_BIN" -p firewall -o "$FW" > "$CASE_TMP/f.out" 2> "$CASE_TMP/f.err" || \
    case_fail "modulejail -p firewall exited $? (expected 0); stderr=$(cat "$CASE_TMP/f.err")"
assert_grep '^# profile: firewall$' "$FW" firewall-header
for m in xt_recent xt_hashlimit nf_conntrack ip_vs; do
    if grep -qE "^install $m " "$FW"; then
        case_fail "$m should be kept under -p firewall (netfilter toolkit)"
    fi
done
# Sanity: the pipeline ran and blacklisted the dummy padding (non-netfilter).
if ! grep -qE '^install dummy_[0-9]+ ' "$FW"; then
    case_fail "no dummy_* module blacklisted under -p firewall; pipeline did not run"
fi

# --- conservative: the same modules MUST be blacklisted (control) ---
CONS=$CASE_TMP/conservative.conf
"$MODULEJAIL_BIN" -p conservative -o "$CONS" > "$CASE_TMP/c.out" 2> "$CASE_TMP/c.err" || \
    case_fail "modulejail -p conservative exited $? (expected 0); stderr=$(cat "$CASE_TMP/c.err")"
for m in xt_recent xt_hashlimit nf_conntrack ip_vs; do
    if ! grep -qE "^install $m " "$CONS"; then
        case_fail "$m should be blacklisted under -p conservative (not a firewall host)"
    fi
done

case_pass
