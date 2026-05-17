#!/usr/bin/env sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
easytier="${EASYTIER_DIR:-$root/vendor/EasyTier}"

if [ ! -d "$easytier/.git" ]; then
  echo "EasyTier workspace is missing: $easytier" >&2
  echo "Run make vendor or set EASYTIER_DIR=/path/to/EasyTier." >&2
  exit 1
fi

mkdir -p "$root/dist/x86_64-linux"

host_os="$(uname -s)"
if [ "$host_os" != "Linux" ] && [ -z "${CARGO_BUILD_TARGET:-}" ]; then
  echo "x86_64-linux builds must run on Linux or set CARGO_BUILD_TARGET." >&2
  echo "Current host is $host_os; refusing to copy non-Linux artifacts into dist/x86_64-linux." >&2
  exit 2
fi

echo "Building EasyTier Linux artifacts..."
(
  cd "$easytier"
  if [ -n "${BUILD_PACKAGES:-}" ]; then
    for package in $BUILD_PACKAGES; do
      if [ -n "${CARGO_BUILD_TARGET:-}" ]; then
        cargo build --release --target "$CARGO_BUILD_TARGET" -p "$package"
      else
        cargo build --release -p "$package"
      fi
    done
  else
    if [ -n "${CARGO_BUILD_TARGET:-}" ]; then
      cargo build --release --target "$CARGO_BUILD_TARGET"
    else
      cargo build --release
    fi
  fi
)

target_dir="$(
  cd "$easytier"
  cargo metadata --format-version=1 --no-deps \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["target_directory"])'
)"

release_dir="$target_dir/release"
if [ -n "${CARGO_BUILD_TARGET:-}" ]; then
  release_dir="$target_dir/$CARGO_BUILD_TARGET/release"
fi

find "$release_dir" -maxdepth 1 -type f \
  \( -name 'easytier-core' -o -name 'easytier-cli' -o -name 'easytier-web*' -o -name 'easytier-agent' \) \
  -exec cp {} "$root/dist/x86_64-linux/" \;

echo "Artifacts copied to dist/x86_64-linux"
