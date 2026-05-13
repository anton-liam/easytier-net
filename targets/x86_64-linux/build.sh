#!/usr/bin/env sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
easytier="$root/vendor/EasyTier"

if [ ! -d "$easytier/.git" ]; then
  echo "vendor/EasyTier is missing. Run: make vendor" >&2
  exit 1
fi

mkdir -p "$root/dist/x86_64-linux"

echo "Building EasyTier Linux artifacts..."
(
  cd "$easytier"
  cargo build --release
)

find "$easytier/target/release" -maxdepth 1 -type f \
  \( -name 'easytier-core' -o -name 'easytier-cli' -o -name 'easytier-web*' \) \
  -exec cp {} "$root/dist/x86_64-linux/" \;

echo "Artifacts copied to dist/x86_64-linux"

