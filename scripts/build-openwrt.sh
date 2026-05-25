#!/bin/bash
# Build easytier-core for aarch64 linux (OpenWrt device deployment)
# Uses a pre-built builder image with all dependencies cached
#
# First run: ~5 min (build builder image + compile)
# Subsequent: ~1-3 min (incremental cargo build)
set -eu

# Ensure Docker credential helpers are in PATH (macOS Docker Desktop)
if [ -d "/Applications/Docker.app/Contents/Resources/bin" ]; then
  export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJECT_DIR/vendor/EasyTier"
DIST_DIR="$PROJECT_DIR/dist/aarch64"
BUILDER_IMAGE="easytier-builder:arm64"

mkdir -p "$DIST_DIR"

# Build builder image if not exists
if ! docker image inspect "$BUILDER_IMAGE" >/dev/null 2>&1; then
  echo "=== Building builder image (one-time) ==="
  docker build -t "$BUILDER_IMAGE" \
    --platform linux/arm64 \
    -f "$SCRIPT_DIR/Dockerfile.builder" \
    "$SCRIPT_DIR"
fi

echo "=== Building EasyTier for aarch64-unknown-linux-musl ==="

docker run --rm \
  -v "$VENDOR_DIR":/src \
  -v "${DIST_DIR}":/dist \
  -v easytier-cargo-registry:/usr/local/cargo/registry \
  -v easytier-cargo-git:/usr/local/cargo/git \
  -v easytier-target-aarch64:/src/target \
  -w /src \
  --platform linux/arm64 \
  "$BUILDER_IMAGE" \
  bash -c '
    set -eu

    # Ensure musl target is installed for the active toolchain
    # (rust-toolchain.toml may specify a different version than the image default)
    rustup target add aarch64-unknown-linux-musl 2>/dev/null || true

    echo "--- Building easytier-core ---"
    cargo build --release --target aarch64-unknown-linux-musl -p easytier --features gateway-policy

    # Copy output
    cp target/aarch64-unknown-linux-musl/release/easytier-core /dist/ 2>/dev/null || \
    cp target/aarch64-unknown-linux-musl/release/easytier /dist/easytier-core

    echo "--- Done ---"
    ls -lh /dist/
  '

echo "=== Device binary ready in $DIST_DIR ==="
ls -lh "$DIST_DIR"
