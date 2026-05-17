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
  cookie="$(mktemp)"
  trap 'rm -f "$cookie"' EXIT
  info "C checks gateway policy observed state"
  login_web "$cookie" || fail "cannot login Web API at $WEB_URL"
  body="$(curl --noproxy '*' -fsS -b "$cookie" "$WEB_URL/api/v1/gateway-policies")" \
    || fail "cannot fetch gateway policies"
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
    fail "no enabled gateway policy has aligned source/exit observed state"
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
    cat >&2 <<'EOF'
FAIL: UTM_STABILITY_CHAOS=1 requires procd/supervisor-managed easytier-agent on A/B.
Current script intentionally refuses destructive fault injection until agent restart commands are productized.
EOF
    exit 2
  fi
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
