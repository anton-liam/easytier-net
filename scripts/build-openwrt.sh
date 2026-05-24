#!/bin/bash
# Build easytier-core for aarch64 linux (OpenWrt device deployment)
# Runs cross-compilation inside Docker from Mac host
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJECT_DIR/vendor/EasyTier"
DIST_DIR="$PROJECT_DIR/dist/aarch64"

mkdir -p "$DIST_DIR"

echo "=== Building EasyTier for aarch64-unknown-linux-musl ==="

docker run --rm \
  -v "$VENDOR_DIR":/src \
  -v "${DIST_DIR}":/dist \
  -w /src \
  --platform linux/arm64 \
  rust:latest \
  bash -c '
    set -eu

    # Install musl toolchain
    apt-get update -qq && apt-get install -y -qq musl-tools pkg-config protobuf-compiler >/dev/null 2>&1
    rustup target add aarch64-unknown-linux-musl

    # Build easytier-core only (no web needed on device)
    echo "--- Building easytier-core ---"
    cargo build --release --target aarch64-unknown-linux-musl -p easytier

    # Copy output
    cp target/aarch64-unknown-linux-musl/release/easytier-core /dist/ 2>/dev/null || \
    cp target/aarch64-unknown-linux-musl/release/easytier /dist/easytier-core

    echo "--- Done ---"
    ls -lh /dist/
  '

echo "=== Device binary ready in $DIST_DIR ==="
ls -lh "$DIST_DIR"
