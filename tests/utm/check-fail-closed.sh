#!/bin/bash
# Verify Source fail-closed behavior when the tunnel/exit peer is unhealthy.

set -eu

source "$(dirname "$0")/lib-utm.sh"

print_section "Web 登录与 pair apply"
login_web
remove_pair_policy >/dev/null 2>&1 || true
apply_pair_policy >/dev/null
sleep 2

print_section "模拟 Source 隧道异常"
ssh_a "ip link set '$UTM_EASYTIER_IFACE' down"
sleep 8

print_section "验证 fail-closed guard"
assert_source_policy_route_absent
assert_source_guard_active
get_source_status | jq '.'
ssh_d "! curl -4 --max-time 6 -fsS '$UTM_TEST_TCP_URL' >/dev/null"

print_section "验证本地和控制面不被 guard 破坏"
ssh_d "ping -c 3 -W 2 '$UTM_A_LAN_IP'"
ssh_a "ping -c 3 -W 2 '$UTM_C_HOST'"

print_section "恢复隧道并清理"
ssh_a "ip link set '$UTM_EASYTIER_IFACE' up"
sleep 8
remove_pair_policy >/dev/null 2>&1 || true

echo "UTM fail-closed check passed"
