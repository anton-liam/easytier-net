#!/bin/bash
# Test: process exit cleanup
#
# Simulates easytier-core process exit by applying rules then running
# the cleanup sequence. Verifies all gateway policy artifacts are removed
# while default routing remains intact.
#
# Usage: ./test-process-exit-cleanup.sh

set -eu

COMPOSE="docker compose -f $(dirname "$0")/../docker-compose.yml"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Setup: apply policy on A ==="

$COMPOSE exec -T node-a sh -c '
  nft add table inet easytier_gw
  nft add chain inet easytier_gw prerouting "{ type filter hook prerouting priority -150; }"
  nft add rule inet easytier_gw prerouting ip saddr 10.99.1.100 ip daddr != 10.99.1.0/24 meta mark set 0x7e
  nft add chain inet easytier_gw forward "{ type filter hook forward priority 0; }"
  nft add rule inet easytier_gw forward meta mark 0x7e counter

  ip rule add fwmark 0x7e table 126 2>/dev/null || true
  ip route replace default via 10.99.1.3 dev eth0 table 126
'

echo ""
echo "--- Pre-check: rules exist on A ---"
PRE_RULES=$($COMPOSE exec -T node-a ip rule show 2>/dev/null | grep -c "fwmark 0x7e" || true)
PRE_NFT=$($COMPOSE exec -T node-a nft list table inet easytier_gw 2>/dev/null | grep -c "easytier_gw" || true)
if [ "$PRE_RULES" -gt 0 ] && [ "$PRE_NFT" -gt 0 ]; then
  echo "  OK: rules applied (ip rules=$PRE_RULES, nft refs=$PRE_NFT)"
else
  echo "  WARN: rules may not be fully applied (ip rules=$PRE_RULES, nft refs=$PRE_NFT)"
fi

echo ""
echo "=== Simulating process exit: running cleanup sequence ==="

# This is the exact cleanup sequence from executor.rs cleanup()
$COMPOSE exec -T node-a sh -c '
  ip rule del fwmark 0x7e table 126 2>/dev/null || true
  ip route flush table 126 2>/dev/null || true
  nft delete table inet easytier_gw 2>/dev/null || true
'

echo ""
echo "=== Verify clean state ==="

echo ""
echo "--- Test 1: no fwmark ip rules ---"
RULES=$($COMPOSE exec -T node-a ip rule show 2>/dev/null | grep -c "fwmark 0x7e" || true)
if [ "$RULES" -eq 0 ]; then
  pass "No fwmark 0x7e ip rules after cleanup"
else
  fail "fwmark ip rules still present ($RULES)"
fi

echo ""
echo "--- Test 2: table 126 empty ---"
ROUTES=$($COMPOSE exec -T node-a ip route show table 126 2>/dev/null | grep -c . || true)
if [ "$ROUTES" -eq 0 ]; then
  pass "Table 126 is empty after cleanup"
else
  fail "Table 126 still has routes ($ROUTES)"
fi

echo ""
echo "--- Test 3: no nft table ---"
if $COMPOSE exec -T node-a nft list table inet easytier_gw 2>&1 | grep -q "No such\|does not exist\|Error"; then
  pass "No easytier_gw nft table after cleanup"
else
  fail "easytier_gw nft table still exists"
fi

echo ""
echo "--- Test 4: default route intact ---"
DEFAULT_RT=$($COMPOSE exec -T node-a ip route show default 2>/dev/null | grep -c "default" || true)
if [ "$DEFAULT_RT" -gt 0 ]; then
  pass "Default route still intact"
else
  fail "Default route missing after cleanup"
fi

echo ""
echo "--- Test 5: D → A local still works ---"
if $COMPOSE exec -T client-d ping -c2 -W3 10.99.1.10 >/dev/null 2>&1; then
  pass "D → A local OK after process exit"
else
  fail "D → A broken after process exit"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
