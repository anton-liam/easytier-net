#!/bin/sh
set -eu

ROLE=$(hostname)
echo "[$ROLE] starting..."

# Enable forwarding
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true

# TODO: start easytier-core here once binaries are available
# easytier-core -w udp://192.168.64.4:22020/admin &

echo "[$ROLE] ready"
sleep infinity
