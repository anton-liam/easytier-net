#!/bin/bash
# Verify D -> A -> B -> Internet and return path evidence in UTM.

set -eu

source "$(dirname "$0")/lib-utm.sh"

TMP_DIR="${TMP_DIR:-/tmp/easytier-utm-return-path}"
mkdir -p "$TMP_DIR"

count_b_gateway_forward_packets() {
  ssh_b "nft list chain inet easytier_gw forward 2>/dev/null | awk '/ip saddr/ {for (i=1; i<=NF; i++) if (\$i == \"packets\") sum += \$(i+1)} END {print sum + 0}'"
}

run_d_acceptance_check() {
  local label="$1"
  local required="$2"
  local cmd="$3"

  printf '\n[%s] %s\n' "$([ "$required" = "1" ] && echo REQUIRED || echo WEAK)" "$label"
  if ssh_d "$cmd"; then
    echo "PASS: $label"
    return 0
  fi

  if [ "$required" = "1" ]; then
    echo "FAIL: $label" >&2
    return 1
  fi

  echo "WEAK-FAIL/SKIP: $label"
  return 0
}

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
run_d_acceptance_check "TCP 出口请求" 1 \
  "curl -4 --max-time 10 -fsS '$UTM_TEST_TCP_URL' >/dev/null"
run_d_acceptance_check "tracepath 诊断到 $UTM_TEST_MTU_HOST" "$UTM_REQUIRE_TRACEPATH" \
  "command -v tracepath >/dev/null 2>&1 && tracepath '$UTM_TEST_MTU_HOST'"
run_d_acceptance_check "MTU 强制探测 size=$UTM_REQUIRED_MTU_PROBE_SIZE" 1 \
  "ping -M do -s '$UTM_REQUIRED_MTU_PROBE_SIZE' -c 3 '$UTM_TEST_MTU_HOST'"
run_d_acceptance_check "MTU 大包探测 size=$UTM_LARGE_MTU_PROBE_SIZE" "$UTM_REQUIRE_LARGE_MTU" \
  "ping -M do -s '$UTM_LARGE_MTU_PROBE_SIZE' -c 3 '$UTM_TEST_MTU_HOST'"
run_d_acceptance_check "WebSocket 出口请求" "$UTM_REQUIRE_WEBSOCKET" \
  "command -v websocat >/dev/null 2>&1 && printf 'easytier-websocket-check\n' | timeout 8 websocat -t '$UTM_TEST_WEBSOCKET_URL'"
run_d_acceptance_check "公网 UDP iperf3 出口请求" "$UTM_REQUIRE_PUBLIC_UDP" \
  "command -v iperf3 >/dev/null 2>&1 && iperf3 -c '$UTM_TEST_PUBLIC_UDP_IPERF_HOST' -u -b 1M -t 5"

print_section "D -> A 本机不被捕获"
BEFORE="$(count_b_gateway_forward_packets)"
ssh_d "ping -c 3 -W 2 '$UTM_A_LAN_IP'"
AFTER="$(count_b_gateway_forward_packets)"
echo "B forward counter around D->A local: $BEFORE -> $AFTER"
test "$BEFORE" = "$AFTER"

echo "UTM return-path check passed"
