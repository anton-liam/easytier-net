#!/bin/bash
# Test: exit peer loss makes Source gateway auto-clean its policy rules.

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
sleep 12

echo ""
echo "--- Test 1: A auto-rolled back gateway rules ---"
if assert_no_gateway_rules node-a; then
  pass "A cleaned policy after peer loss"
else
  fail "A still has policy artifacts after peer loss"
fi

echo ""
echo "--- Test 2: D -> A local still works after rollback ---"
if assert_d_can_reach_a_local; then
  pass "D can still reach A"
else
  fail "D cannot reach A after rollback"
fi

echo ""
echo "--- Test 3: A -> C control plane still works after rollback ---"
if assert_a_can_reach_c; then
  pass "A can still reach C"
else
  fail "A cannot reach C after rollback"
fi

echo "=== Restoring B for subsequent tests ==="
compose up -d node-b >/dev/null
sleep 3
cleanup_node_rules node-b || true

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
