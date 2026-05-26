#!/bin/bash
# Test: Source tunnel loss keeps desired policy guarded and blocks D leakage.

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
compose up -d node-b >/dev/null

echo "=== Applying pair policy through easytier-web ==="
wait_apply_pair_policy >/dev/null

echo "=== Simulating exit peer/tunnel loss by stopping B ==="
compose stop node-b >/dev/null

echo ""
echo "--- Test 1: A removed policy-route artifacts and installed fail-closed guard ---"
if wait_source_guard_active; then
  pass "A is guarded instead of leaking D traffic through local WAN"
else
  fail "A did not enter guarded fail-closed state"
fi

echo ""
echo "--- Test 2: D cannot reach external endpoint while policy is desired but tunnel is down ---"
if assert_d_cannot_reach_internet_endpoint; then
  pass "D external traffic is blocked"
else
  fail "D external traffic still leaks"
fi

echo ""
echo "--- Test 3: D -> A local and A -> C control traffic still work ---"
if assert_d_can_reach_a_local && assert_a_can_reach_c; then
  pass "local/control traffic is not captured by guard"
else
  fail "guard broke local/control traffic"
fi

echo ""
echo "--- Test 4: Source status reports degraded guarded ---"
if assert_source_status_degraded_guarded; then
  pass "A reports DEGRADED_GUARDED"
else
  fail "A does not report DEGRADED_GUARDED"
fi

echo "=== Restoring B for subsequent tests ==="
compose up -d node-b >/dev/null
sleep 8
remove_pair_policy >/dev/null 2>&1 || true
cleanup_all_rules

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
