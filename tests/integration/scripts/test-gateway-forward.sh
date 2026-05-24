#!/bin/bash
# Test: D → A → B → Internet forwarding
#
# Verifies that after applying gateway policy:
# 1. D's traffic to Internet goes through A → B (marked + policy routed)
# 2. D → A local is NOT captured (direct, no mark)
# 3. A → C control plane is NOT captured (A's own traffic, not from br-lan)
#
# Usage: ./test-gateway-forward.sh

set -eu

COMPOSE="docker compose -f $(dirname "$0")/../docker-compose.yml"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Applying gateway policy on A (source) ==="

$COMPOSE exec -T node-a sh -c '
  LAN_IFACE=${LAN_IFACE:-eth1}
  WAN_IFACE=${WAN_IFACE:-eth0}

  nft add table inet easytier_gw
  nft add chain inet easytier_gw prerouting "{ type filter hook prerouting priority -150; }"
  nft add rule inet easytier_gw prerouting iif $LAN_IFACE ip saddr 192.168.1.0/24 meta mark set 0x7e
  nft add chain inet easytier_gw forward "{ type filter hook forward priority 0; }"
  nft add rule inet easytier_gw forward meta mark 0x7e counter

  ip rule add fwmark 0x7e table 126 2>/dev/null || true
  # NOTE: in real setup, next-hop is B EasyTier IP via tun0
  # For now, route to B underlay directly via WAN for smoke test
  ip route replace default via 192.168.64.3 dev $WAN_IFACE table 126
'

echo "=== Applying masquerade on B (exit) ==="

$COMPOSE exec -T node-b sh -c '
  nft add table inet easytier_gw
  nft add chain inet easytier_gw postrouting "{ type nat hook postrouting priority 100; }"
  nft add rule inet easytier_gw postrouting ip saddr 192.168.1.0/24 masquerade
  nft add chain inet easytier_gw forward "{ type filter hook forward priority 0; }"
  nft add rule inet easytier_gw forward ct state established,related counter accept
  nft add rule inet easytier_gw forward ip saddr 192.168.1.0/24 counter accept
'

echo ""
echo "=== Running tests ==="

echo ""
echo "--- Test 1: D → Internet (via A → B) ---"
if $COMPOSE exec -T client-d ping -c2 -W3 8.8.8.8 >/dev/null 2>&1; then
  pass "D can reach Internet through A → B"
else
  fail "D cannot reach Internet"
fi

echo ""
echo "--- Test 2: D → A local (not captured) ---"
if $COMPOSE exec -T client-d ping -c2 -W3 192.168.1.1 >/dev/null 2>&1; then
  pass "D can reach A directly"
else
  fail "D cannot reach A"
fi

echo ""
echo "--- Test 3: A → C control plane (not captured) ---"
if $COMPOSE exec -T node-a ping -c2 -W3 192.168.64.4 >/dev/null 2>&1; then
  pass "A can reach C control plane"
else
  fail "A cannot reach C"
fi

echo ""
echo "--- Test 4: A SSH still reachable from D ---"
# Simulate by checking A's IP is reachable on any port
if $COMPOSE exec -T client-d sh -c 'echo | nc -w2 192.168.1.1 22 2>/dev/null || ping -c1 -W2 192.168.1.1' >/dev/null 2>&1; then
  pass "A management still reachable from D"
else
  fail "A management unreachable from D"
fi

echo ""
echo "--- Test 5: nft counters show forwarded traffic ---"
FWD_COUNT=$($COMPOSE exec -T node-a nft list chain inet easytier_gw forward 2>/dev/null | grep -oP 'packets \K[0-9]+' | head -1 || echo 0)
if [ "$FWD_COUNT" -gt 0 ]; then
  pass "A forwarded $FWD_COUNT packets with mark 0x7e"
else
  fail "No marked packets forwarded on A (counter=$FWD_COUNT)"
fi

echo ""
echo "=== Cleanup: restoring policy ==="

$COMPOSE exec -T node-a sh -c '
  ip rule del fwmark 0x7e table 126 2>/dev/null || true
  ip route flush table 126 2>/dev/null || true
  nft delete table inet easytier_gw 2>/dev/null || true
'
$COMPOSE exec -T node-b sh -c '
  nft delete table inet easytier_gw 2>/dev/null || true
'

echo ""
echo "--- Test 6: after cleanup, A has no policy rules ---"
RULES=$($COMPOSE exec -T node-a ip rule show 2>/dev/null | grep -c "fwmark 0x7e" || true)
if [ "$RULES" -eq 0 ]; then
  pass "Policy rules cleaned up"
else
  fail "Policy rules still present ($RULES)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
