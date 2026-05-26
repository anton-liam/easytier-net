#!/bin/sh
set -eu

ROLE=${ROLE:-unknown}
DEVICE_TEMPLATE=${DEVICE_TEMPLATE:-dualport}
WAN_IFACE=${WAN_IFACE:-eth0}
LAN_IFACE=${LAN_IFACE:-eth1}
CONFIG_SERVER=${CONFIG_SERVER:-}
MACHINE_ID=${MACHINE_ID:-}
NODE_HOSTNAME=${NODE_HOSTNAME:-$(cat /proc/sys/kernel/hostname 2>/dev/null || echo openwrt-node)}
NODE_NETWORK_NAME=${NODE_NETWORK_NAME:-gateway-docker}
NODE_NETWORK_SECRET=${NODE_NETWORK_SECRET:-gateway-docker-secret}
NODE_IPV4=${NODE_IPV4:-}
NODE_PEERS=${NODE_PEERS:-}
NODE_LISTENERS=${NODE_LISTENERS:-}
NODE_DEV_NAME=${NODE_DEV_NAME:-tun0}
DEFAULT_GW=${DEFAULT_GW:-}
BOOTSTRAP_NETWORK=${BOOTSTRAP_NETWORK:-0}

echo "[$(hostname)] starting... template=$DEVICE_TEMPLATE role=$ROLE"

# Enable forwarding
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true

# Log interface info
echo "[$(hostname)] interfaces:"
if [ "$DEVICE_TEMPLATE" = "dualport" ]; then
  echo "  WAN: $WAN_IFACE (upstream/underlay)"
  echo "  LAN: $LAN_IFACE (downstream clients)"
elif [ "$DEVICE_TEMPLATE" = "singleport" ]; then
  echo "  WAN: $WAN_IFACE (upstream, single-port exit)"
fi

ip addr show 2>/dev/null || true

if [ -n "$DEFAULT_GW" ]; then
  ip route replace default via "$DEFAULT_GW"
  echo "[$NODE_HOSTNAME] default gw -> $DEFAULT_GW"
fi

if [ -n "$CONFIG_SERVER" ] && [ -x /usr/bin/easytier-core ]; then
  echo "[$(hostname)] starting easytier-core webclient -> $CONFIG_SERVER"
  set -- /usr/bin/easytier-core \
    -w "$CONFIG_SERVER" \
    --proxy-forward-by-system \
    --machine-id "$MACHINE_ID" \
    --hostname "$NODE_HOSTNAME"

  if [ "$BOOTSTRAP_NETWORK" = "1" ]; then
    set -- "$@" \
      --network-name "$NODE_NETWORK_NAME" \
      --network-secret "$NODE_NETWORK_SECRET" \
      --dev-name "$NODE_DEV_NAME"

    if [ -n "$NODE_IPV4" ]; then
      set -- "$@" --ipv4 "$NODE_IPV4"
    fi
    if [ -n "$NODE_PEERS" ]; then
      set -- "$@" --peers "$NODE_PEERS"
    fi
    if [ -n "$NODE_LISTENERS" ]; then
      set -- "$@" --listeners "$NODE_LISTENERS"
    fi
  fi

  "$@" &
  echo "$!" >/tmp/easytier-core.pid
else
  echo "[$(hostname)] easytier-core not started (CONFIG_SERVER or binary missing)"
fi

echo "[$(hostname)] ready"
sleep infinity
