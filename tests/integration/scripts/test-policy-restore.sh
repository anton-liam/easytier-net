#!/bin/bash
# Test: pair/remove restores A/B to a clean gateway state.

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

echo "=== Removing pair policy through easytier-web ==="
remove_pair_policy >/dev/null

echo ""
echo "--- Test 1: A has no gateway policy rules ---"
if assert_no_gateway_rules node-a; then
  pass "A is clean"
else
  fail "A still has gateway policy artifacts"
fi

echo ""
echo "--- Test 2: B has no gateway policy rules ---"
if assert_no_gateway_rules node-b; then
  pass "B is clean"
else
  fail "B still has gateway policy artifacts"
fi

echo ""
echo "--- Test 3: D -> A local still works after restore ---"
if assert_d_can_reach_a_local; then
  pass "D can reach A after restore"
else
  fail "D cannot reach A after restore"
fi

echo ""
echo "--- Test 4: A -> C control plane still works after restore ---"
if assert_a_can_reach_c; then
  pass "A can reach C after restore"
else
  fail "A cannot reach C after restore"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
