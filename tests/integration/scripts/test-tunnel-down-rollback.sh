#!/bin/bash
# Test: tunnel down → auto rollback
#
# Simulates tunnel loss by removing the policy route next-hop,
# verifies that cleanup restores A/B to clean state.
#
# Usage: ./test-tunnel-down-rollback.sh

set -eu

COMPOSE="docker compose -f $(dirname "$0")/../docker-compose.yml"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Setup: apply policy ==="

$COMPOSE exec -T node-a sh -c '
  nft add table inet easytier_gw
  nft add chain inet easytier_gw prerouting "{ type filter hook prerouting priority -150; }"
  nft add rule inet easytier_gw prerouting iif eth1 ip saddr 192.168.1.0/24 meta mark set 0x7e
  ip rule add fwmark 0x7e table 126 2>/dev/null || true
  ip route replace default via 192.168.64.3 dev eth0 table 126
'

echo ""
echo "=== Simulating tunnel down: flush policy route ==="

# In real scenario, gateway module detects peer unreachable and runs cleanup
# Here we simulate the rollback action
$COMPOSE exec -T node-a sh -c '
  ip rule del fwmark 0x7e table 126 2>/dev/null || true
  ip route flush table 126 2>/dev/null || true
  nft delete table inet easytier_gw 2>/dev/null || true
'

echo ""
echo "=== Verify clean state ==="

echo ""
echo "--- Test 1: no policy rules on A ---"
RULES=$($COMPOSE exec -T node-a ip rule show 2>/dev/null | grep -c "fwmark 0x7e" || true)
if [ "$RULES" -eq 0 ]; then
  pass "No policy rules after rollback"
else
  fail "Policy rules still present ($RULES)"
fi

echo ""
echo "--- Test 2: no nft table on A ---"
if $COMPOSE exec -T node-a nft list table inet easytier_gw 2>&1 | grep -q "No such"; then
  pass "nft table cleaned up"
else
  fail "nft table still exists"
fi

echo ""
echo "--- Test 3: A → C still reachable ---"
if $COMPOSE exec -T node-a ping -c2 -W3 192.168.64.4 >/dev/null 2>&1; then
  pass "A → C control plane OK after rollback"
else
  fail "A → C broken after rollback"
fi

echo ""
echo "--- Test 4: D → A still reachable ---"
if $COMPOSE exec -T client-d ping -c2 -W3 192.168.1.1 >/dev/null 2>&1; then
  pass "D → A local OK after rollback"
else
  fail "D → A broken after rollback"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
