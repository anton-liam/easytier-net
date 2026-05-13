#!/usr/bin/env sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"

if command -v containerlab >/dev/null 2>&1; then
  containerlab destroy -t "$root/tests/lab/clab.yml" --cleanup || true
else
  echo "containerlab not found; nothing to destroy."
fi

