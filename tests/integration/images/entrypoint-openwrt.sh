#!/bin/sh
set -eu

ROLE=${ROLE:-unknown}
DEVICE_TEMPLATE=${DEVICE_TEMPLATE:-dualport}
WAN_IFACE=${WAN_IFACE:-eth0}
LAN_IFACE=${LAN_IFACE:-eth1}

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

# TODO: start easytier-core here once binaries are available
# On real device, this is managed by procd init script:
#   easytier-core -w udp://192.168.64.4:22020/admin

echo "[$(hostname)] ready"
sleep infinity
