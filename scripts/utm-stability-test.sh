#!/usr/bin/env sh
set -eu

WEB_HOST="${UTM_WEB_HOST:-192.168.64.4}"
WEB_URL="${UTM_WEB_URL:-http://$WEB_HOST:11211}"
WEB_USER="${UTM_WEB_USER:-anton}"
WEB_PASSWORD="${UTM_WEB_PASSWORD:-anton}"
A_HOST="${UTM_A_HOST:-192.168.64.2}"
B_HOST="${UTM_B_HOST:-192.168.64.3}"
A_USER="${UTM_A_USER:-root}"
B_USER="${UTM_B_USER:-root}"
WEB_LOGIN_USER="${UTM_WEB_LOGIN_USER:-admin}"
WEB_LOGIN_PASSWORD="${UTM_WEB_LOGIN_PASSWORD:-admin}"

SSH_BIN="${SSH:-ssh}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

ssh_node() {
  user="$1"
  host="$2"
  shift 2
  "$SSH_BIN" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$user@$host" "$@"
}

node_web_probe_cmd() {
  cat <<EOF
set -eu
if command -v curl >/dev/null 2>&1; then
  curl --noproxy '*' -fsS -m 5 '$WEB_URL/' >/dev/null
elif command -v wget >/dev/null 2>&1; then
  wget -q -T 5 -O /dev/null '$WEB_URL/'
else
  echo 'missing curl/wget' >&2
  exit 127
fi
EOF
}

assert_node_can_reach_web() {
  name="$1"
  user="$2"
  host="$3"
  info "$name checks Web reachability"
  ssh_node "$user" "$host" "$(node_web_probe_cmd)" \
    || fail "$name cannot reach $WEB_URL. Try: ssh $user@$host 'ip route get $WEB_HOST; logread | tail'"
}

assert_node_processes() {
  name="$1"
  user="$2"
  host="$3"
  info "$name checks EasyTier processes"
  ssh_node "$user" "$host" "pgrep -af 'easytier-core' >/dev/null" \
    || fail "$name has no easytier-core process"
  ssh_node "$user" "$host" "pgrep -af 'easytier-agent' >/dev/null" \
    || fail "$name has no easytier-agent process"
}

assert_node_underlay_route() {
  name="$1"
  user="$2"
  host="$3"
  info "$name checks route to Web stays on underlay"
  route="$(ssh_node "$user" "$host" "ip route get '$WEB_HOST' | head -n1")" \
    || fail "$name cannot resolve route to $WEB_HOST"
  echo "$name route: $route"
  if echo "$route" | grep -E 'easytier|tap|tun' >/dev/null; then
    fail "$name route to $WEB_HOST appears to use tunnel: $route"
  fi
}

login_web() {
  cookie="$1"
  if command -v md5 >/dev/null 2>&1; then
    pass="$(printf '%s' "$WEB_LOGIN_PASSWORD" | md5)"
  else
    pass="$(printf '%s' "$WEB_LOGIN_PASSWORD" | md5sum | awk '{print $1}')"
  fi
  curl --noproxy '*' -fsS -c "$cookie" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"$WEB_LOGIN_USER\",\"password\":\"$pass\"}" \
    "$WEB_URL/api/v1/auth/login" >/dev/null
}

assert_gateway_policies_aligned() {
  check_gateway_policies_aligned || fail "no enabled gateway policy has aligned source/exit observed state"
}

check_gateway_policies_aligned() {
  cookie="$(mktemp)"
  info "C checks gateway policy observed state"
  login_web "$cookie" || {
    rm -f "$cookie"
    return 1
  }
  body="$(curl --noproxy '*' -fsS -b "$cookie" "$WEB_URL/api/v1/gateway-policies")" \
    || {
      rm -f "$cookie"
      return 1
    }
  rm -f "$cookie"
  printf '%s\n' "$body" | jq -e '
    [
      .[]
      | select(.desired.enabled == true)
      | select(.observed.source != null and .observed.exit != null)
      | select(.observed.source.policy_id == .desired.policy_id)
      | select(.observed.exit.policy_id == .desired.policy_id)
      | select(.observed.source.version == .desired.desired_version)
      | select(.observed.exit.version == .desired.desired_version)
    ] | length >= 1
  ' >/dev/null || {
    printf '%s\n' "$body" | jq '[.[] | {policy_id:.desired.policy_id, desired_version:.desired.desired_version, enabled:.desired.enabled, source:.observed.source, exit:.observed.exit}]' >&2
    return 1
  }
}

assert_web_process() {
  info "C checks Web process"
  ssh_node "$WEB_USER" "$WEB_HOST" "pgrep -af '^/usr/local/bin/easytier-web-embed( |$)' >/dev/null" \
    || fail "C has no easytier-web-embed process"
  curl --noproxy '*' -fsS -m 5 "$WEB_URL/" >/dev/null \
    || fail "Mac host cannot reach $WEB_URL"
}

run_chaos_notice() {
  if [ "${UTM_STABILITY_CHAOS:-0}" = "1" ]; then
    run_agent_respawn_check "A" "$A_USER" "$A_HOST"
    run_agent_respawn_check "B" "$B_USER" "$B_HOST"
    run_web_restart_check
    assert_node_can_reach_web "A" "$A_USER" "$A_HOST"
    assert_node_can_reach_web "B" "$B_USER" "$B_HOST"
    assert_node_underlay_route "A" "$A_USER" "$A_HOST"
    assert_node_underlay_route "B" "$B_USER" "$B_HOST"
    wait_gateway_policies_aligned
  fi
}

run_web_restart_check() {
  info "C chaos: restart easytier-web and wait for A/B control-plane reachability"
  ssh_node "$WEB_USER" "$WEB_HOST" "set -eu
    sudo_with_password() { printf '%s\n' '$WEB_PASSWORD' | sudo -S \"\$@\"; }
    pids=\$(pgrep -f '^/usr/local/bin/easytier-web-embed( |$)' || true)
    [ -n \"\$pids\" ] || { echo 'easytier-web-embed is not running' >&2; exit 2; }
    sudo_with_password kill \$pids
    for _ in 1 2 3 4 5; do
      remaining=\$(pgrep -f '^/usr/local/bin/easytier-web-embed( |$)' || true)
      [ -z \"\$remaining\" ] && break
      sleep 1
    done
    remaining=\$(pgrep -f '^/usr/local/bin/easytier-web-embed( |$)' || true)
    [ -z \"\$remaining\" ] || sudo_with_password kill -9 \$remaining
    nohup /usr/local/bin/easytier-web-embed \
      -d /var/lib/easytier/easytier-web.db \
      -p udp \
      -c 22020 \
      -a 11211 \
      --api-host '$WEB_URL' \
      --internal-auth-token easytier-lab-internal-token \
      --console-log-level info \
      > /tmp/easytier-web-embed.log 2>&1 &
  "
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if curl --noproxy '*' -fsS -m 5 "$WEB_URL/" >/dev/null; then
      return 0
    fi
    sleep 2
  done
  fail "C Web did not come back after restart. Try: ssh $WEB_USER@$WEB_HOST 'tail -80 /tmp/easytier-web-embed.log'"
}

run_agent_respawn_check() {
  name="$1"
  user="$2"
  host="$3"
  info "$name chaos: kill easytier-agent and wait for procd respawn"
  ssh_node "$user" "$host" "/etc/init.d/easytier-agent enabled >/dev/null" \
    || fail "$name easytier-agent service is not enabled"
  ssh_node "$user" "$host" "/etc/init.d/easytier-agent status | grep -q running" \
    || fail "$name easytier-agent service is not running"
  ssh_node "$user" "$host" "pids=\$(pgrep -f '^/usr/bin/easytier-agent run ' || true); [ -n \"\$pids\" ]; kill \$pids"

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ssh_node "$user" "$host" "pgrep -af '^/usr/bin/easytier-agent run ' >/dev/null"; then
      return 0
    fi
    sleep 2
  done
  fail "$name easytier-agent did not respawn. Try: ssh $user@$host '/etc/init.d/easytier-agent status; logread | tail -80'"
}

wait_gateway_policies_aligned() {
  info "C waits for gateway observed state after chaos"
  for _ in 1 2 3 4 5 6; do
    if check_gateway_policies_aligned; then
      return 0
    fi
    sleep 10
  done
  fail "gateway observed state did not recover after chaos"
}

assert_web_process
assert_node_can_reach_web "A" "$A_USER" "$A_HOST"
assert_node_can_reach_web "B" "$B_USER" "$B_HOST"
assert_node_processes "A" "$A_USER" "$A_HOST"
assert_node_processes "B" "$B_USER" "$B_HOST"
assert_node_underlay_route "A" "$A_USER" "$A_HOST"
assert_node_underlay_route "B" "$B_USER" "$B_HOST"
assert_gateway_policies_aligned
run_chaos_notice

echo "UTM control-plane stability smoke test passed."
