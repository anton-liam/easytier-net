#!/bin/bash
# Test: easytier-core process exit cleans gateway policy artifacts.

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

echo "=== Simulating A easytier-core process exit ==="
compose exec -T node-a sh -c 'kill -TERM "$(cat /tmp/easytier-core.pid)"'
sleep 5

echo ""
echo "--- Test 1: A cleaned gateway rules on process exit ---"
if assert_no_gateway_rules node-a; then
  pass "A is clean after easytier-core exit"
else
  fail "A still has gateway policy artifacts after process exit"
fi

echo ""
echo "--- Test 2: D -> A local still works after process exit ---"
if assert_d_can_reach_a_local; then
  pass "D can still reach A"
else
  fail "D cannot reach A after process exit"
fi

echo "=== Restarting A for subsequent manual inspection ==="
compose restart node-a >/dev/null
sleep 5
cleanup_node_rules node-b || true

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
