#!/bin/bash
# Verify D -> A -> B -> Internet and return path evidence in UTM.

set -eu

source "$(dirname "$0")/lib-utm.sh"

TMP_DIR="${TMP_DIR:-/tmp/easytier-utm-return-path}"
mkdir -p "$TMP_DIR"

print_section "Web 登录与 pair apply"
login_web
remove_pair_policy >/dev/null 2>&1 || true
apply_pair_policy >/dev/null
sleep 2

print_section "D 基础连通与出口 IP"
ssh_d "ping -c 3 -W 2 '$UTM_A_LAN_IP'"
ssh_a "ping -c 3 -W 2 '$UTM_C_HOST'"
ssh_b "ping -c 3 -W 2 '$UTM_C_HOST'"
D_EXIT_IP="$(ssh_d "curl -4 --max-time 10 -fsS '$UTM_TEST_TCP_URL'")"
echo "D observed exit IP: $D_EXIT_IP"

print_section "A/B 规则与计数器"
ssh_a "ip rule show | grep '0x7e' && ip route show table 126 && nft list table inet easytier_gw"
ssh_b "nft list table inet easytier_gw"

print_section "回程证据"
ssh_b "conntrack -L 2>/dev/null | grep -E '$UTM_A_MANAGED_CIDRS|${UTM_D_HOST}' || true"
ssh_a "ip route get '$UTM_D_HOST' || true"
ssh_b "ip route show | grep '$UTM_A_MANAGED_CIDRS' || true"

print_section "TCP/UDP/WebSocket/MTU 检查"
ssh_d "curl -4 --max-time 10 -fsS '$UTM_TEST_TCP_URL' >/dev/null"
ssh_d "command -v tracepath >/dev/null 2>&1 && tracepath '$UTM_TEST_MTU_HOST' || true"
ssh_d "ping -M do -s 1200 -c 3 '$UTM_TEST_MTU_HOST' || true"
ssh_d "ping -M do -s 1360 -c 3 '$UTM_TEST_MTU_HOST' || true"
ssh_d "command -v websocat >/dev/null 2>&1 && printf 'easytier-websocket-check\n' | timeout 8 websocat -t 'wss://echo.websocket.events' || true"
ssh_d "command -v iperf3 >/dev/null 2>&1 && iperf3 -c iperf3.iperf.fr -u -b 1M -t 5 || true"

print_section "D -> A 本机不被捕获"
BEFORE="$(ssh_b "nft list chain inet easytier_gw postrouting 2>/dev/null | awk '/masquerade/ {for (i=1; i<=NF; i++) if (\\\$i == \"packets\") print \\\$(i+1)}' | awk '{s+=\\\$1} END {print s+0}'")"
ssh_d "ping -c 3 -W 2 '$UTM_A_LAN_IP'"
AFTER="$(ssh_b "nft list chain inet easytier_gw postrouting 2>/dev/null | awk '/masquerade/ {for (i=1; i<=NF; i++) if (\\\$i == \"packets\") print \\\$(i+1)}' | awk '{s+=\\\$1} END {print s+0}'")"
echo "B NAT counter around D->A local: $BEFORE -> $AFTER"
test "$BEFORE" = "$AFTER"

echo "UTM return-path check passed"
