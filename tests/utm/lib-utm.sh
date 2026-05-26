#!/bin/bash
# Shared helpers for UTM four-node gateway_policy acceptance checks.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_FILE="${UTM_INVENTORY_FILE:-$SCRIPT_DIR/inventory.env}"

if [ -f "$INVENTORY_FILE" ]; then
  # shellcheck disable=SC1090
  . "$INVENTORY_FILE"
else
  echo "missing inventory: $INVENTORY_FILE" >&2
  exit 1
fi

UTM_WEB_LOGIN_USER="${UTM_WEB_LOGIN_USER:-admin}"
UTM_WEB_LOGIN_PASSWORD="${UTM_WEB_LOGIN_PASSWORD:-admin}"
UTM_WEB_COOKIE_FILE="${UTM_WEB_COOKIE_FILE:-$SCRIPT_DIR/.utm-easytier-web.cookie}"
UTM_POLICY_ID="${UTM_POLICY_ID:-utm-gw-001}"
UTM_A_INGRESS_IFACE="${UTM_A_INGRESS_IFACE:-br-lan}"
UTM_B_WAN_IFACE="${UTM_B_WAN_IFACE:-eth0}"
UTM_EASYTIER_IFACE="${UTM_EASYTIER_IFACE:-tun0}"
UTM_TEST_TCP_URL="${UTM_TEST_TCP_URL:-http://ifconfig.me/ip}"
UTM_TEST_MTU_HOST="${UTM_TEST_MTU_HOST:-1.1.1.1}"
UTM_SSH_COMMON_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=6"

run_ssh() {
  local host="$1"
  local user="$2"
  local password="$3"
  local cmd
  shift 3
  cmd="$*"

  if [ -n "$password" ]; then
    sshpass -p "$password" ssh $UTM_SSH_COMMON_OPTS "$user@$host" "$cmd"
  else
    ssh $UTM_SSH_COMMON_OPTS "$user@$host" "$cmd"
  fi
}

ssh_a() { run_ssh "$UTM_A_HOST" "$UTM_A_USER" "${UTM_A_PASSWORD:-}" "$@"; }
ssh_b() { run_ssh "$UTM_B_HOST" "$UTM_B_USER" "${UTM_B_PASSWORD:-}" "$@"; }
ssh_c() { run_ssh "$UTM_C_HOST" "$UTM_C_USER" "${UTM_C_PASSWORD:-}" "$@"; }
ssh_d() { run_ssh "$UTM_D_HOST" "$UTM_D_USER" "${UTM_D_PASSWORD:-}" "$@"; }

login_web() {
  local password

  rm -f "$UTM_WEB_COOKIE_FILE"
  password="$UTM_WEB_LOGIN_PASSWORD"
  if [ "$password" = "admin" ]; then
    password="21232f297a57a5a743894a0e4a801fc3"
  fi

  curl -fsS \
    -c "$UTM_WEB_COOKIE_FILE" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"$UTM_WEB_LOGIN_USER\",\"password\":\"$password\"}" \
    "$UTM_WEB_URL/api/v1/auth/login" >/dev/null
}

policy_payload() {
  cat <<JSON
{
  "policy_id": "$UTM_POLICY_ID",
  "source_machine_id": "$UTM_A_MACHINE_ID",
  "exit_machine_id": "$UTM_B_MACHINE_ID",
  "managed_cidrs": ["$UTM_A_MANAGED_CIDRS"],
  "ingress_iface": "$UTM_A_INGRESS_IFACE",
  "easytier_iface": "$UTM_EASYTIER_IFACE",
  "exit_peer_tun_ip": "$UTM_B_EASYTIER_IPV4",
  "exit_wan_iface": "$UTM_B_WAN_IFACE"
}
JSON
}

apply_pair_policy() {
  curl -fsS \
    -b "$UTM_WEB_COOKIE_FILE" \
    -c "$UTM_WEB_COOKIE_FILE" \
    -H 'Content-Type: application/json' \
    -d "$(policy_payload)" \
    "$UTM_WEB_URL/api/v1/gateway-policy/pair"
}

remove_pair_policy() {
  curl -fsS \
    -b "$UTM_WEB_COOKIE_FILE" \
    -c "$UTM_WEB_COOKIE_FILE" \
    -H 'Content-Type: application/json' \
    -d "$(policy_payload)" \
    "$UTM_WEB_URL/api/v1/gateway-policy/pair/remove"
}

proxy_rpc() {
  local machine_id="$1"
  local service_name="$2"
  local method_name="$3"
  local payload="$4"

  curl -fsS \
    -b "$UTM_WEB_COOKIE_FILE" \
    -c "$UTM_WEB_COOKIE_FILE" \
    -H 'Content-Type: application/json' \
    -d "{\"service_name\":\"$service_name\",\"method_name\":\"$method_name\",\"payload\":$payload}" \
    "$UTM_WEB_URL/api/v1/machines/$machine_id/proxy-rpc"
}

get_source_config() {
  proxy_rpc "$UTM_A_MACHINE_ID" "api.config.ConfigRpcService" "GetConfig" "{}"
}

get_source_status() {
  curl -fsS \
    -b "$UTM_WEB_COOKIE_FILE" \
    -c "$UTM_WEB_COOKIE_FILE" \
    "$UTM_WEB_URL/api/v1/gateway-policy/$UTM_A_MACHINE_ID"
}

assert_json_contains_native_source_config() {
  get_source_config | jq -e --arg cidr "$UTM_A_MANAGED_CIDRS" --arg exit "$UTM_B_EASYTIER_IPV4" '
    (((.config.proxy_cidrs // []) | index($cidr)) != null)
    and
    (((.config.exit_nodes // []) | index($exit)) != null)
  ' >/dev/null
}

assert_source_guard_active() {
  ssh_a "nft list table inet easytier_gw_guard 2>/dev/null | grep -q ' drop'"
}

assert_source_policy_route_absent() {
  ssh_a "! ip rule show | grep -q 'fwmark 0x7e' && ! ip route show table 126 | grep -q ."
}

print_section() {
  printf '\n=== %s ===\n' "$1"
}
