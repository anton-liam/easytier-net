#!/bin/bash
# Test: pair apply updates EasyTier native proxy_cidrs and exit_nodes on Source.

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
echo "--- Test 1: Pair network config uses C relay peer ---"
if assert_pair_network_config_uses_controller_peer; then
  pass "A/B network configs use C relay peer"
else
  fail "A/B network configs do not use C relay peer"
fi

echo ""
echo "--- Test 2: Source native config has proxy_cidrs and exit_nodes ---"
if assert_source_native_config; then
  pass "A config contains managed CIDR and B exit node"
else
  fail "A config misses managed CIDR or B exit node"
fi

echo ""
echo "--- Test 3: B route to D subnet uses C relay ---"
if wait_b_route_uses_controller_relay; then
  pass "B reaches A managed CIDR through C relay"
else
  fail "B route to A managed CIDR does not use C relay"
fi

echo ""
echo "--- Test 4: B has a return-route hint for D subnet ---"
if wait_b_has_return_route_hint; then
  pass "B can discover route information for managed CIDR"
else
  fail "B cannot discover route information for managed CIDR"
fi

echo ""
echo "=== Removing pair policy ==="
remove_pair_policy >/dev/null

echo ""
echo "--- Test 5: Source native config is cleaned after pair remove ---"
if assert_source_native_config_removed; then
  pass "A native config cleanup removed proxy CIDR and exit node"
else
  fail "A native config still contains proxy CIDR or exit node"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
