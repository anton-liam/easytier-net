#!/bin/bash
# Test: TCP/UDP return path flows back through B -> A -> D under gateway policy.

set -eu

source "$(dirname "$0")/lib-gateway.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Preparing clean gateway state ==="
login_web
remove_pair_policy >/dev/null 2>&1 || true
cleanup_all_rules

echo "=== Applying pair policy through easytier-web ==="
wait_apply_pair_policy >/dev/null

BEFORE_FWD="$(count_b_forward_packets)"

echo ""
echo "--- Test 1: TCP request from D receives response through gateway path ---"
if assert_d_can_reach_internet_endpoint; then
  pass "D receives TCP response from B-side endpoint"
else
  fail "D cannot receive TCP response from B-side endpoint"
fi

AFTER_FWD="$(count_b_forward_packets)"

echo ""
echo "--- Test 2: B forward counter increases and internet sees B WAN source ---"
if [ "$AFTER_FWD" -gt "$BEFORE_FWD" ] && assert_internet_sees_b_wan_source_tcp; then
  pass "B forwarded TCP and SNAT source is B WAN ($EXIT_WAN_IP)"
else
  fail "B forward/SNAT verification failed: forward $BEFORE_FWD->$AFTER_FWD"
fi

echo ""
echo "--- Test 3: UDP echo can return to D ---"
if assert_udp_echo; then
  pass "D receives UDP echo response"
else
  fail "D cannot receive UDP echo response"
fi

echo ""
echo "--- Test 4: Local/control traffic is still reachable ---"
if assert_d_can_reach_a_local && assert_a_can_reach_c; then
  pass "D -> A local and A -> C control traffic remain reachable"
else
  fail "local/control traffic reachability failed"
fi

echo ""
echo "=== Removing pair policy ==="
remove_pair_policy >/dev/null

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
