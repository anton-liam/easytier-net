#!/bin/bash
# Test: policy restore — disable policy → verify clean state on A and B
#
# Verifies that after removing gateway policy:
# 1. All nft rules are cleaned on both A and B
# 2. All ip rule/route entries for table 126 are removed on A
# 3. D→A local and A→C control plane still work
#
# Usage: ./test-policy-restore.sh

set -eu

COMPOSE="docker compose -f $(dirname "$0")/../docker-compose.yml"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Setup: apply policy on A (source) and B (exit) ==="

$COMPOSE exec -T node-a sh -c '
  nft add table inet easytier_gw
  nft add chain inet easytier_gw prerouting "{ type filter hook prerouting priority -150; }"
  nft add rule inet easytier_gw prerouting ip saddr 10.99.1.100 ip daddr != 10.99.1.0/24 meta mark set 0x7e
  nft add chain inet easytier_gw forward "{ type filter hook forward priority 0; }"
  nft add rule inet easytier_gw forward meta mark 0x7e counter

  ip rule add fwmark 0x7e table 126 2>/dev/null || true
  ip route replace default via 10.99.1.3 dev eth0 table 126
'

$COMPOSE exec -T node-b sh -c '
  nft add table inet easytier_gw
  nft add chain inet easytier_gw postrouting "{ type nat hook postrouting priority 100; }"
  nft add rule inet easytier_gw postrouting ip saddr 10.99.1.0/24 masquerade
'

echo ""
echo "--- Pre-check: D can reach Internet via A→B ---"
if $COMPOSE exec -T client-d ping -c2 -W3 8.8.8.8 >/dev/null 2>&1; then
  echo "  OK: forwarding works before restore"
else
  echo "  WARN: forwarding not working (may be expected in isolated lab)"
fi

echo ""
echo "=== Restoring: remove policy on A and B ==="

$COMPOSE exec -T node-a sh -c '
  ip rule del fwmark 0x7e table 126 2>/dev/null || true
  ip route flush table 126 2>/dev/null || true
  nft delete table inet easytier_gw 2>/dev/null || true
'

$COMPOSE exec -T node-b sh -c '
  nft delete table inet easytier_gw 2>/dev/null || true
'

echo ""
echo "=== Verify clean state ==="

echo ""
echo "--- Test 1: no fwmark ip rules on A ---"
RULES=$($COMPOSE exec -T node-a ip rule show 2>/dev/null | grep -c "fwmark 0x7e" || true)
if [ "$RULES" -eq 0 ]; then
  pass "No fwmark 0x7e ip rules on A"
else
  fail "fwmark ip rules still present on A ($RULES)"
fi

echo ""
echo "--- Test 2: table 126 empty on A ---"
ROUTES=$($COMPOSE exec -T node-a ip route show table 126 2>/dev/null | grep -c . || true)
if [ "$ROUTES" -eq 0 ]; then
  pass "Table 126 is empty on A"
else
  fail "Table 126 still has routes on A ($ROUTES)"
fi

echo ""
echo "--- Test 3: no easytier_gw nft table on A ---"
if $COMPOSE exec -T node-a nft list table inet easytier_gw 2>&1 | grep -q "No such\|does not exist\|Error"; then
  pass "No easytier_gw nft table on A"
else
  fail "easytier_gw nft table still exists on A"
fi

echo ""
echo "--- Test 4: no easytier_gw nft table on B ---"
if $COMPOSE exec -T node-b nft list table inet easytier_gw 2>&1 | grep -q "No such\|does not exist\|Error"; then
  pass "No easytier_gw nft table on B"
else
  fail "easytier_gw nft table still exists on B"
fi

echo ""
echo "--- Test 5: D → A local still works ---"
if $COMPOSE exec -T client-d ping -c2 -W3 10.99.1.10 >/dev/null 2>&1; then
  pass "D → A local OK after restore"
else
  fail "D → A broken after restore"
fi

echo ""
echo "--- Test 6: A → C control plane still works ---"
if $COMPOSE exec -T node-a ping -c2 -W3 10.99.1.4 >/dev/null 2>&1; then
  pass "A → C control plane OK after restore"
else
  fail "A → C broken after restore"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
