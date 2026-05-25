#!/bin/bash
# Build easytier-core + easytier-web for x86_64 linux (C server deployment)
# Uses a pre-built builder image with all dependencies cached
#
# First run: ~10 min (build builder image + compile, Rosetta emulation)
# Subsequent: ~3-5 min (incremental cargo build)
set -eu

# Ensure Docker credential helpers are in PATH (macOS Docker Desktop)
if [ -d "/Applications/Docker.app/Contents/Resources/bin" ]; then
  export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJECT_DIR/vendor/EasyTier"
DIST_DIR="$PROJECT_DIR/dist/x86_64"
BUILDER_IMAGE="easytier-builder:x86_64"

mkdir -p "$DIST_DIR"

# Build builder image if not exists
if ! docker image inspect "$BUILDER_IMAGE" >/dev/null 2>&1; then
  echo "=== Building builder image (one-time) ==="
  docker build -t "$BUILDER_IMAGE" \
    --platform linux/amd64 \
    -f "$SCRIPT_DIR/Dockerfile.builder" \
    "$SCRIPT_DIR"
fi

echo "=== Building EasyTier for x86_64-unknown-linux-musl ==="

docker run --rm \
  -v "$VENDOR_DIR":/src \
  -v "${DIST_DIR}":/dist \
  -v easytier-cargo-registry-x86:/usr/local/cargo/registry \
  -v easytier-cargo-git-x86:/usr/local/cargo/git \
  -v easytier-target-x86:/src/target \
  -v easytier-pnpm-store:/root/.local/share/pnpm/store \
  -w /src \
  --platform linux/amd64 \
  "$BUILDER_IMAGE" \
  bash -c '
    set -eu

    rustup target add x86_64-unknown-linux-musl 2>/dev/null || true

    # Build frontend first
    export CI=true
    if [ -d easytier-web/frontend ]; then
      echo "--- Building frontend ---"
      cd easytier-web/frontend
      pnpm install --frozen-lockfile 2>/dev/null || pnpm install
      pnpm build
      cd /src
    fi

    # Build easytier-core
    echo "--- Building easytier-core ---"
    cargo build --release --target x86_64-unknown-linux-musl -p easytier --features gateway-policy

    # Build easytier-web
    echo "--- Building easytier-web ---"
    cargo build --release --target x86_64-unknown-linux-musl -p easytier-web

    # Copy outputs
    cp target/x86_64-unknown-linux-musl/release/easytier-core /dist/ 2>/dev/null || \
    cp target/x86_64-unknown-linux-musl/release/easytier /dist/easytier-core
    cp target/x86_64-unknown-linux-musl/release/easytier-web /dist/

    echo "--- Done ---"
    ls -lh /dist/
  '

echo "=== Server binaries ready in $DIST_DIR ==="
ls -lh "$DIST_DIR"
