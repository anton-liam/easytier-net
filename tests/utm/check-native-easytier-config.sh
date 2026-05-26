#!/bin/bash
# Verify EasyTier native proxy_cidrs/exit_nodes integration on UTM A/B/C.

set -eu

source "$(dirname "$0")/lib-utm.sh"

print_section "Web 登录与 pair apply"
login_web
remove_pair_policy >/dev/null 2>&1 || true
apply_pair_policy >/dev/null

print_section "基础隧道状态"
ssh_a "ip addr show '$UTM_EASYTIER_IFACE'"
ssh_b "ip addr show '$UTM_EASYTIER_IFACE'"
ssh_a "ping -c 3 -W 2 '$UTM_B_EASYTIER_IPV4'"
ssh_b "ping -c 3 -W 2 '$UTM_A_EASYTIER_IPV4'"

print_section "A 原生 EasyTier 配置"
assert_json_contains_native_source_config
get_source_config | jq '{proxy_cidrs: .config.proxy_cidrs, exit_nodes: .config.exit_nodes, proxy_forward_by_system: .config.proxy_forward_by_system}'

print_section "B 回程路由视图"
ssh_b "ip route show | grep '$UTM_A_MANAGED_CIDRS' || true"
proxy_rpc "$UTM_B_MACHINE_ID" "api.instance.PeerManageRpcService" "ListRoute" "{}" | jq '.'

print_section "清理策略"
remove_pair_policy >/dev/null

echo "UTM native EasyTier config check passed"
