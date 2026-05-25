#!/bin/sh
set -eu

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

ROLE=${ROLE:-unknown}
CLIENT_DEFAULT_GW=${CLIENT_DEFAULT_GW:-}
CLIENT_IPV4=${CLIENT_IPV4:-}

echo "[$(hostname)] ubuntu node starting... role=$ROLE"

case "$ROLE" in
  web)
    if [ ! -x /opt/easytier/easytier-web ]; then
      echo "[$(hostname)] missing /opt/easytier/easytier-web" >&2
      exit 1
    fi
    echo "[$(hostname)] starting easytier-web on api=:11211 config-server=:22020/udp"
    exec /opt/easytier/easytier-web \
      --db /tmp/easytier-web.db \
      --api-server-addr 0.0.0.0 \
      --api-server-port 11211 \
      --config-server-protocol udp \
      --config-server-port 22020
    ;;
  client)
    if [ -n "$CLIENT_IPV4" ]; then
      ip addr flush dev eth0
      ip addr add "$CLIENT_IPV4" dev eth0
      ip link set eth0 up
      echo "[$(hostname)] eth0 -> $CLIENT_IPV4"
    fi
    if [ -n "$CLIENT_DEFAULT_GW" ]; then
      ip route replace default via "$CLIENT_DEFAULT_GW"
      echo "[$(hostname)] default gw -> $CLIENT_DEFAULT_GW"
    fi
    ;;
esac

echo "[$(hostname)] ubuntu node ready"
sleep infinity
