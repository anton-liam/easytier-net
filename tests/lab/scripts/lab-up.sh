#!/usr/bin/env sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required for lab-up." >&2
  exit 1
fi

if ! command -v containerlab >/dev/null 2>&1; then
  echo "containerlab is required for lab-up. Run this inside the Linux lab VM." >&2
  exit 1
fi

docker build -t easytier-net/node-lab:dev -f "$root/tests/lab/images/Dockerfile.node" "$root/tests/lab/images"
docker build -t easytier-net/web-lab:dev -f "$root/tests/lab/images/Dockerfile.web" "$root/tests/lab/images"

containerlab deploy -t "$root/tests/lab/clab.yml"

