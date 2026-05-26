#!/bin/bash
# Test: Web REST -> RPC -> gateway_policy enables D -> A -> B -> Internet flow.

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

echo ""
echo "--- Test 1: D reaches internet endpoint through A -> B ---"
if assert_d_can_reach_internet_endpoint; then
  pass "D can reach B-side internet endpoint"
else
  fail "D cannot reach B-side internet endpoint"
fi

echo ""
echo "--- Test 2: D -> A local is not captured ---"
if assert_d_can_reach_a_local; then
  pass "D can reach A local address"
else
  fail "D cannot reach A local address"
fi

echo ""
echo "--- Test 3: A -> C control plane is not captured ---"
if assert_a_can_reach_c; then
  pass "A can reach C control plane"
else
  fail "A cannot reach C control plane"
fi

echo ""
echo "--- Test 4: B forward counter increased ---"
FWD_COUNT="$(count_b_forward_packets)"
FWD_COUNT="${FWD_COUNT:-0}"
if [ "$FWD_COUNT" -gt 0 ]; then
  pass "B forwarded packets through gateway policy (packets=$FWD_COUNT)"
else
  fail "B forward counter did not increase"
fi

echo ""
echo "--- Test 5: Source native EasyTier config was patched ---"
if assert_source_native_config; then
  pass "A has proxy_cidrs and exit_nodes"
else
  fail "A native config is missing proxy_cidrs or exit_nodes"
fi

echo ""
echo "=== Restoring policy ==="
remove_pair_policy >/dev/null

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
