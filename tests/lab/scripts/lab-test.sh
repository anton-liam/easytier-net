#!/usr/bin/env sh
set -eu

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required for lab-test." >&2
  exit 1
fi

for node in clab-easytier-net-web clab-easytier-net-node-a clab-easytier-net-node-b; do
  docker inspect "$node" >/dev/null
  docker exec "$node" ip link show >/dev/null
done

docker exec clab-easytier-net-node-a ping -c 1 172.30.40.10 >/dev/null
docker exec clab-easytier-net-node-b ping -c 1 172.30.40.10 >/dev/null

echo "Lab smoke test passed."

