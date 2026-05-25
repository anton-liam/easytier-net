#!/bin/bash
# Shared helpers for gateway_policy product-path integration tests.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE=(docker compose -f "$LAB_DIR/docker-compose.yml")

WEB_URL="${WEB_URL:-http://127.0.0.1:11211}"
COOKIE_FILE="${COOKIE_FILE:-$LAB_DIR/.easytier-web.cookie}"
WEB_USERNAME="${WEB_USERNAME:-admin}"
WEB_PASSWORD="${WEB_PASSWORD:-21232f297a57a5a743894a0e4a801fc3}"

A_MACHINE_ID="00000000-0000-0000-0000-00000000000a"
B_MACHINE_ID="00000000-0000-0000-0000-00000000000b"
POLICY_ID="docker-gw-001"
MANAGED_CIDR="10.99.1.0/25"
INGRESS_IFACE="eth0"
EASYTIER_IFACE="eth0"
EXIT_PEER_IP="10.99.1.3"
EXIT_WAN_IFACE="eth0"
INTERNET_URL="http://10.99.1.200:8080"

compose() {
  "${COMPOSE[@]}" "$@"
}

policy_payload() {
  cat <<JSON
{
  "policy_id": "$POLICY_ID",
  "source_machine_id": "$A_MACHINE_ID",
  "exit_machine_id": "$B_MACHINE_ID",
  "managed_cidrs": ["$MANAGED_CIDR"],
  "ingress_iface": "$INGRESS_IFACE",
  "easytier_iface": "$EASYTIER_IFACE",
  "exit_peer_tun_ip": "$EXIT_PEER_IP",
  "exit_wan_iface": "$EXIT_WAN_IFACE"
}
JSON
}

login_web() {
  rm -f "$COOKIE_FILE"
  for _ in $(seq 1 60); do
    if curl -fsS \
      -c "$COOKIE_FILE" \
      -H 'Content-Type: application/json' \
      -d "{\"username\":\"$WEB_USERNAME\",\"password\":\"$WEB_PASSWORD\"}" \
      "$WEB_URL/api/v1/auth/login" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "web login timeout: $WEB_URL" >&2
  return 1
}

apply_pair_policy() {
  curl -fsS \
    -b "$COOKIE_FILE" \
    -c "$COOKIE_FILE" \
    -H 'Content-Type: application/json' \
    -d "$(policy_payload)" \
    "$WEB_URL/api/v1/gateway-policy/pair"
}

wait_apply_pair_policy() {
  local last_error
  for _ in $(seq 1 60); do
    if last_error="$(apply_pair_policy 2>&1)"; then
      echo "$last_error"
      return 0
    fi
    sleep 1
  done

  echo "apply pair policy timeout. last error: $last_error" >&2
  return 1
}

remove_pair_policy() {
  curl -fsS \
    -b "$COOKIE_FILE" \
    -c "$COOKIE_FILE" \
    -H 'Content-Type: application/json' \
    -d "$(policy_payload)" \
    "$WEB_URL/api/v1/gateway-policy/pair/remove"
}

cleanup_node_rules() {
  local node="$1"
  compose exec -T "$node" sh -c '
    while ip rule show 2>/dev/null | grep -q "fwmark 0x7e.*lookup 126\|fwmark 0x7e.*table 126"; do
      ip rule del fwmark 0x7e table 126 2>/dev/null || break
    done
    ip route flush table 126 2>/dev/null || true
    nft delete table inet easytier_gw 2>/dev/null || true
    for chain in input forward srcnat; do
      nft -a list chain inet fw4 "$chain" 2>/dev/null | awk "/easytier_gw/ {print \$NF}" | while read handle; do
        nft delete rule inet fw4 "$chain" handle "$handle" 2>/dev/null || true
      done
    done
  '
}

cleanup_all_rules() {
  cleanup_node_rules node-a || true
  cleanup_node_rules node-b || true
}

assert_no_gateway_rules() {
  local node="$1"
  local rules routes nft_table fw4_rules

  rules="$(compose exec -T "$node" sh -c 'ip rule show 2>/dev/null | grep -c "fwmark 0x7e" || true')"
  routes="$(compose exec -T "$node" sh -c 'ip route show table 126 2>/dev/null | grep -c . || true')"
  nft_table="$(compose exec -T "$node" sh -c 'nft list table inet easytier_gw >/dev/null 2>&1; echo $?')"
  fw4_rules="$(compose exec -T "$node" sh -c 'for chain in input forward srcnat; do nft -a list chain inet fw4 "$chain" 2>/dev/null; done | grep -c "easytier_gw" || true')"

  [ "$rules" = "0" ] || {
    echo "$node still has fwmark rules: $rules" >&2
    return 1
  }
  [ "$routes" = "0" ] || {
    echo "$node still has table 126 routes: $routes" >&2
    return 1
  }
  [ "$nft_table" != "0" ] || {
    echo "$node still has inet easytier_gw table" >&2
    return 1
  }
  [ "$fw4_rules" = "0" ] || {
    echo "$node still has fw4 easytier_gw rules: $fw4_rules" >&2
    return 1
  }
}

assert_d_can_reach_internet_endpoint() {
  compose exec -T client-d curl --noproxy '*' -fsS --max-time 5 "$INTERNET_URL" >/dev/null
}

assert_d_can_reach_a_local() {
  compose exec -T client-d ping -c2 -W3 10.99.1.10 >/dev/null
}

assert_a_can_reach_c() {
  compose exec -T node-a ping -c2 -W3 10.99.1.4 >/dev/null
}
