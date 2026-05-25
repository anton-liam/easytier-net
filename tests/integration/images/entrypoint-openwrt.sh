#!/bin/sh
set -eu

ROLE=${ROLE:-unknown}
DEVICE_TEMPLATE=${DEVICE_TEMPLATE:-dualport}
WAN_IFACE=${WAN_IFACE:-eth0}
LAN_IFACE=${LAN_IFACE:-eth1}
CONFIG_SERVER=${CONFIG_SERVER:-}
MACHINE_ID=${MACHINE_ID:-}
NODE_HOSTNAME=${NODE_HOSTNAME:-$(cat /proc/sys/kernel/hostname 2>/dev/null || echo openwrt-node)}

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

if [ -n "$CONFIG_SERVER" ] && [ -x /usr/bin/easytier-core ]; then
  echo "[$(hostname)] starting easytier-core webclient -> $CONFIG_SERVER"
  /usr/bin/easytier-core \
    -w "$CONFIG_SERVER" \
    --machine-id "$MACHINE_ID" \
    --hostname "$NODE_HOSTNAME" &
  echo "$!" >/tmp/easytier-core.pid
else
  echo "[$(hostname)] easytier-core not started (CONFIG_SERVER or binary missing)"
fi

echo "[$(hostname)] ready"
sleep infinity
