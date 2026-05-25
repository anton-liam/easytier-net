#!/bin/bash
# Build arm64 binaries used by Docker integration tests.
# Reuses the same cached builder image/volumes as build-openwrt.sh.
set -eu

if [ -d "/Applications/Docker.app/Contents/Resources/bin" ]; then
  export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJECT_DIR/vendor/EasyTier"
DIST_DIR="$PROJECT_DIR/dist/aarch64"
BUILDER_IMAGE="easytier-builder:arm64"

mkdir -p "$DIST_DIR"

if ! docker image inspect "$BUILDER_IMAGE" >/dev/null 2>&1; then
  echo "=== Building builder image (one-time) ==="
  docker build -t "$BUILDER_IMAGE" \
    --platform linux/arm64 \
    -f "$SCRIPT_DIR/Dockerfile.builder" \
    "$SCRIPT_DIR"
fi

echo "=== Building Docker integration binaries for arm64 ==="

docker run --rm \
  -v "$VENDOR_DIR":/src \
  -v "${DIST_DIR}":/dist \
  -v easytier-cargo-registry:/usr/local/cargo/registry \
  -v easytier-cargo-git:/usr/local/cargo/git \
  -v easytier-target-aarch64:/src/target \
  -v easytier-pnpm-store:/root/.local/share/pnpm/store \
  -w /src \
  --platform linux/arm64 \
  "$BUILDER_IMAGE" \
  bash -c '
    set -eu
    export RUSTUP_TOOLCHAIN=1.95.0

    rustup target add aarch64-unknown-linux-musl

    export CI=true
    if [ -d easytier-web/frontend ]; then
      echo "--- Building frontend ---"
      cd easytier-web/frontend
      pnpm install --frozen-lockfile 2>/dev/null || pnpm install
      pnpm build
      cd /src
    fi

    echo "--- Building easytier-core ---"
    cargo build --release --target aarch64-unknown-linux-musl -p easytier --features gateway-policy

    echo "--- Building easytier-web ---"
    cargo build --release --target aarch64-unknown-linux-musl -p easytier-web

    cp target/aarch64-unknown-linux-musl/release/easytier-core /dist/ 2>/dev/null || \
    cp target/aarch64-unknown-linux-musl/release/easytier /dist/easytier-core
    cp target/aarch64-unknown-linux-musl/release/easytier-web /dist/

    echo "--- Done ---"
    ls -lh /dist/
  '

echo "=== Docker test binaries ready in $DIST_DIR ==="
ls -lh "$DIST_DIR"
