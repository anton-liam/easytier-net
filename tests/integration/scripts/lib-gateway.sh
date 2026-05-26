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
MANAGED_CIDR="10.99.2.0/24"
INGRESS_IFACE="eth0"
EASYTIER_IFACE="tun0"
EXIT_PEER_IP="10.126.126.3"
EXIT_WAN_IFACE="eth0"
EXIT_WAN_IP="10.99.3.3"
INTERNET_URL="http://10.99.3.200:8080"
INTERNET_HOST="10.99.3.200"
INTERNET_TCP_PORT="8080"
INTERNET_UDP_PORT="18080"
A_UNDERLAY_IP="10.99.1.10"
B_UNDERLAY_IP="10.99.1.3"
C_UNDERLAY_IP="10.99.1.4"
A_LAN_IP="10.99.2.254"
CLIENT_D_IP="10.99.2.100"

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
    nft delete table inet easytier_gw_guard 2>/dev/null || true
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
  local rules routes nft_table nft_guard_table fw4_rules

  rules="$(compose exec -T "$node" sh -c 'ip rule show 2>/dev/null | grep -c "fwmark 0x7e" || true')"
  routes="$(compose exec -T "$node" sh -c 'ip route show table 126 2>/dev/null | grep -c . || true')"
  nft_table="$(compose exec -T "$node" sh -c 'nft list table inet easytier_gw >/dev/null 2>&1; echo $?')"
  nft_guard_table="$(compose exec -T "$node" sh -c 'nft list table inet easytier_gw_guard >/dev/null 2>&1; echo $?')"
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
  [ "$nft_guard_table" != "0" ] || {
    echo "$node still has inet easytier_gw_guard table" >&2
    return 1
  }
  [ "$fw4_rules" = "0" ] || {
    echo "$node still has fw4 easytier_gw rules: $fw4_rules" >&2
    return 1
  }
}

assert_source_guard_active() {
  local count
  count="$(compose exec -T node-a sh -c 'nft list table inet easytier_gw_guard 2>/dev/null | grep -c " drop" || true')"
  [ "$count" -gt 0 ] || {
    echo "node-a does not have fail-closed guard drop rule" >&2
    return 1
  }
}

wait_source_guard_active() {
  for _ in $(seq 1 20); do
    if assert_no_source_policy_route >/dev/null 2>&1 && assert_source_guard_active >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  assert_no_source_policy_route
  assert_source_guard_active
}

assert_no_source_policy_route() {
  local rules routes
  rules="$(compose exec -T node-a sh -c 'ip rule show 2>/dev/null | grep -c "fwmark 0x7e" || true')"
  routes="$(compose exec -T node-a sh -c 'ip route show table 126 2>/dev/null | grep -c . || true')"
  [ "$rules" = "0" ] && [ "$routes" = "0" ] || {
    echo "node-a still has source policy route artifacts: rules=$rules routes=$routes" >&2
    return 1
  }
}

assert_d_can_reach_internet_endpoint() {
  compose exec -T client-d curl --noproxy '*' -fsS --max-time 5 "$INTERNET_URL" >/dev/null
}

assert_d_cannot_reach_internet_endpoint() {
  ! compose exec -T client-d curl --noproxy '*' -fsS --max-time 5 "$INTERNET_URL" >/dev/null 2>&1
}

assert_d_can_reach_a_local() {
  compose exec -T client-d ping -c2 -W3 "$A_LAN_IP" >/dev/null
}

assert_a_can_reach_c() {
  compose exec -T node-a ping -c2 -W3 "$C_UNDERLAY_IP" >/dev/null
}

count_b_forward_packets() {
  compose exec -T node-b sh -c 'nft list chain inet easytier_gw forward 2>/dev/null | awk "/ip saddr/ {for (i=1; i<=NF; i++) if (\$i == \"packets\") {sum += \$(i+1)}} END {print sum + 0}"'
}

count_b_postrouting_packets() {
  compose exec -T node-b sh -c 'nft list chain inet easytier_gw postrouting 2>/dev/null | awk "/masquerade/ {for (i=1; i<=NF; i++) if (\$i == \"packets\") {sum += \$(i+1)}} END {print sum + 0}"'
}

assert_internet_sees_b_wan_source_tcp() {
  local capture_file="$LAB_DIR/.tcpdump-snat.out"
  rm -f "$capture_file"

  compose exec -T internet sh -c "timeout 8 tcpdump -ni eth0 -tt -c 1 'src host $EXIT_WAN_IP and dst host $INTERNET_HOST and tcp port $INTERNET_TCP_PORT'" >"$capture_file" 2>&1 &
  local capture_pid=$!

  sleep 1
  assert_d_can_reach_internet_endpoint >/dev/null 2>&1 || true
  wait "$capture_pid" >/dev/null 2>&1 || true

  grep -q "IP $EXIT_WAN_IP\\." "$capture_file"
}

count_a_source_mark_rules() {
  compose exec -T node-a sh -c 'nft list table inet easytier_gw 2>/dev/null | grep -c "meta mark set 0x0000007e\\|meta mark set 0x7e" || true'
}

proxy_rpc() {
  local machine_id="$1"
  local service_name="$2"
  local method_name="$3"
  local payload="$4"

  curl -fsS \
    -b "$COOKIE_FILE" \
    -c "$COOKIE_FILE" \
    -H 'Content-Type: application/json' \
    -d "{\"service_name\":\"$service_name\",\"method_name\":\"$method_name\",\"payload\":$payload}" \
    "$WEB_URL/api/v1/machines/$machine_id/proxy-rpc"
}

get_source_config() {
  proxy_rpc "$A_MACHINE_ID" "api.config.ConfigRpcService" "GetConfig" "{}"
}

get_gateway_status() {
  local machine_id="$1"
  curl -fsS \
    -b "$COOKIE_FILE" \
    -c "$COOKIE_FILE" \
    "$WEB_URL/api/v1/gateway-policy/$machine_id"
}

assert_source_native_config() {
  local config
  config="$(get_source_config)"
  echo "$config" | jq -e --arg cidr "$MANAGED_CIDR" --arg exit "$EXIT_PEER_IP" '
    (((.config.proxy_cidrs // []) | index($cidr)) != null)
    and
    (((.config.exit_nodes // []) | index($exit)) != null)
  ' >/dev/null
}

assert_source_native_config_removed() {
  local config
  config="$(get_source_config)"
  echo "$config" | jq -e --arg cidr "$MANAGED_CIDR" --arg exit "$EXIT_PEER_IP" '
    (((.config.proxy_cidrs // []) | index($cidr)) == null)
    and
    (((.config.exit_nodes // []) | index($exit)) == null)
  ' >/dev/null
}

assert_source_status_degraded_guarded() {
  local status
  status="$(get_gateway_status "$A_MACHINE_ID")"
  echo "$status" | jq -e '
    (.state == 3 or .state == "DEGRADED_GUARDED" or .state == "DegradedGuarded")
  ' >/dev/null
}

assert_b_has_return_route_hint() {
  local routes peer_json
  routes="$(compose exec -T node-b sh -c "ip route show | grep -c '$MANAGED_CIDR' || true")"
  if [ "$routes" -gt 0 ]; then
    return 0
  fi

  peer_json="$(proxy_rpc "$B_MACHINE_ID" "api.instance.PeerManageRpcService" "ListRoute" "{}" 2>/dev/null || true)"
  echo "$peer_json" | jq -e --arg cidr "$MANAGED_CIDR" '
    tostring | contains($cidr)
  ' >/dev/null
}

ensure_udp_echo_server() {
  compose exec -T internet sh -c "
    if [ -f /tmp/udp_echo_$INTERNET_UDP_PORT.pid ]; then
      kill \$(cat /tmp/udp_echo_$INTERNET_UDP_PORT.pid) 2>/dev/null || true
      rm -f /tmp/udp_echo_$INTERNET_UDP_PORT.pid
    fi
    cat >/tmp/udp_echo_$INTERNET_UDP_PORT.py <<'PY'
import socket

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(('0.0.0.0', $INTERNET_UDP_PORT))
while True:
    data, addr = sock.recvfrom(65535)
    sock.sendto(data, addr)
PY
    python3 /tmp/udp_echo_$INTERNET_UDP_PORT.py >/tmp/udp-echo.log 2>&1 &
    echo \$! >/tmp/udp_echo_$INTERNET_UDP_PORT.pid
  "
}

assert_udp_echo() {
  ensure_udp_echo_server
  compose exec -T client-d sh -c "printf 'gw-udp-ok' | nc -u -w 3 $INTERNET_HOST $INTERNET_UDP_PORT | grep -q 'gw-udp-ok'"
}
