#!/bin/bash
# Build easytier-core for aarch64 linux (OpenWrt device deployment)
# Prefers local aarch64 musl cross compile; falls back to Docker when needed.
#
# EASYTIER_BUILD_BACKEND=auto   local first, Docker fallback (default)
# EASYTIER_BUILD_BACKEND=native require local aarch64 musl toolchain
# EASYTIER_BUILD_BACKEND=docker require Docker builder
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
BUILD_BACKEND="${EASYTIER_BUILD_BACKEND:-auto}"

# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib-build.sh"

mkdir -p "$DIST_DIR"

build_native() {
  echo "=== Building EasyTier aarch64 core with local musl toolchain ==="
  setup_aarch64_musl_native_env

  (
    cd "$VENDOR_DIR"
    rustup target add aarch64-unknown-linux-musl
    cargo build --release --target aarch64-unknown-linux-musl -p easytier --features gateway-policy
  )

  copy_easytier_core_artifact "$VENDOR_DIR" "aarch64-unknown-linux-musl" "$DIST_DIR"
  echo "=== Native device binary ready in $DIST_DIR ==="
}

build_docker() {
  if ! docker image inspect "$BUILDER_IMAGE" >/dev/null 2>&1; then
    echo "=== Building builder image (one-time) ==="
    docker build -t "$BUILDER_IMAGE" \
      --platform linux/arm64 \
      -f "$SCRIPT_DIR/Dockerfile.builder" \
      "$SCRIPT_DIR"
  fi

  echo "=== Building EasyTier aarch64 core with Docker builder ==="

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

    # The repo pins channel "1.95"; rustup may try to sync that channel online.
    # Use the already-cached full toolchain in the builder image for repeatable builds.
    export RUSTUP_TOOLCHAIN=1.95.0

    # Ensure musl target is installed for the active toolchain
    # (rust-toolchain.toml may specify a different version than the image default)
    rustup target add aarch64-unknown-linux-musl

    echo "--- Building easytier-core ---"
    cargo build --release --target aarch64-unknown-linux-musl -p easytier --features gateway-policy

    # Copy output
    cp target/aarch64-unknown-linux-musl/release/easytier-core /dist/ 2>/dev/null || \
    cp target/aarch64-unknown-linux-musl/release/easytier /dist/easytier-core

    echo "--- Done ---"
    ls -lh /dist/
  '
}

case "$BUILD_BACKEND" in
  auto)
    if can_build_aarch64_musl_native; then
      build_native || {
        echo "WARNING: native build failed; falling back to Docker builder" >&2
        build_docker
      }
    else
      echo "=== Local aarch64 musl toolchain not found; using Docker builder ==="
      build_docker
    fi
    ;;
  native)
    if ! can_build_aarch64_musl_native; then
      echo "ERROR: native aarch64 musl toolchain not found. Install musl-cross or use EASYTIER_BUILD_BACKEND=docker." >&2
      exit 1
    fi
    build_native
    ;;
  docker)
    build_docker
    ;;
  *)
    echo "ERROR: unknown EASYTIER_BUILD_BACKEND='$BUILD_BACKEND'. Use: auto | native | docker" >&2
    exit 1
    ;;
esac

echo "=== Device binary ready in $DIST_DIR ==="
ls -lh "$DIST_DIR"
