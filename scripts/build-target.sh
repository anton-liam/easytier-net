#!/usr/bin/env sh
set -eu

target="${1:-x86_64-linux}"
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

case "$target" in
  x86_64-linux)
    "$root/targets/x86_64-linux/build.sh"
    ;;
  nanopi-r3s)
    "$root/targets/nanopi-r3s/build.sh"
    ;;
  *)
    echo "Unknown target: $target" >&2
    echo "Known targets: x86_64-linux, nanopi-r3s" >&2
    exit 2
    ;;
esac

