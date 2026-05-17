#!/usr/bin/env sh
set -eu

WEB_HOST="${UTM_WEB_HOST:-192.168.64.4}"
WEB_URL="${UTM_WEB_URL:-http://$WEB_HOST:11211}"
USER_ID="${UTM_AGENT_USER_ID:-2}"
TOKEN="${UTM_INTERNAL_AUTH_TOKEN:-easytier-lab-internal-token}"
INTERVAL_SECONDS="${UTM_AGENT_INTERVAL_SECONDS:-10}"
EXECUTE="${UTM_AGENT_EXECUTE:-1}"
A_HOST="${UTM_A_HOST:-192.168.64.2}"
B_HOST="${UTM_B_HOST:-192.168.64.3}"
A_USER="${UTM_A_USER:-root}"
B_USER="${UTM_B_USER:-root}"
A_MACHINE_ID="${UTM_A_MACHINE_ID:-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa}"
B_MACHINE_ID="${UTM_B_MACHINE_ID:-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb}"
A_EASYTIER_IPV4="${UTM_A_EASYTIER_IPV4:-10.77.77.2}"
B_EASYTIER_IPV4="${UTM_B_EASYTIER_IPV4:-10.77.77.3}"
EASYTIER_IFACE="${UTM_EASYTIER_IFACE:-easytierw0}"
SSH_BIN="${SSH:-ssh}"

ssh_node() {
  user="$1"
  host="$2"
  shift 2
  "$SSH_BIN" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$user@$host" "$@"
}

configure_node() {
  label="$1"
  user="$2"
  host="$3"
  machine_id="$4"
  easytier_ipv4="$5"

  echo "Configuring $label easytier-agent service on $host"
  ssh_node "$user" "$host" "set -eu
    [ -x /usr/bin/easytier-agent ] || { echo '/usr/bin/easytier-agent missing' >&2; exit 2; }
    [ -x /etc/init.d/easytier-agent ] || { echo '/etc/init.d/easytier-agent missing' >&2; exit 2; }

    uci -q batch <<'UCI'
set easytier_agent.main.enabled='1'
set easytier_agent.main.web_base_url='$WEB_URL'
set easytier_agent.main.user_id='$USER_ID'
set easytier_agent.main.machine_id='$machine_id'
set easytier_agent.main.internal_auth_token='$TOKEN'
set easytier_agent.main.easytier_ipv4='$easytier_ipv4'
set easytier_agent.main.easytier_iface='$EASYTIER_IFACE'
set easytier_agent.main.interval_seconds='$INTERVAL_SECONDS'
set easytier_agent.main.execute='$EXECUTE'
commit easytier_agent
UCI

    if ! grep -q -- '--interval-seconds' /etc/init.d/easytier-agent; then
      cp /etc/init.d/easytier-agent /etc/init.d/easytier-agent.bak.\$(date +%Y%m%d%H%M%S)
      sed -i \"/easytier_iface=/a\\  interval_seconds=\\\"\\\$(uci -q get easytier_agent.main.interval_seconds || echo 10)\\\"\" /etc/init.d/easytier-agent
      sed -i \"/--internal-auth-token \\\"\\\$internal_auth_token\\\"/s/\$/ \\\\\\\\/\" /etc/init.d/easytier-agent
      sed -i \"/--internal-auth-token \\\"\\\$internal_auth_token\\\"/a\\    --interval-seconds \\\"\\\$interval_seconds\\\"\" /etc/init.d/easytier-agent
    fi

    old_pids=\$(pgrep -f '^/usr/bin/easytier-agent run ' || true)
    if [ -n \"\$old_pids\" ]; then kill \$old_pids 2>/dev/null || true; fi
    /etc/init.d/easytier-agent enable
    /etc/init.d/easytier-agent restart
    sleep 2
    /etc/init.d/easytier-agent status || true
    pgrep -af '^/usr/bin/easytier-agent run '"
}

configure_node "A" "$A_USER" "$A_HOST" "$A_MACHINE_ID" "$A_EASYTIER_IPV4"
configure_node "B" "$B_USER" "$B_HOST" "$B_MACHINE_ID" "$B_EASYTIER_IPV4"

echo "UTM easytier-agent services configured."
