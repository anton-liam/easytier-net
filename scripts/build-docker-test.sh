#!/bin/bash
# Build arm64 binaries used by Docker integration tests.
# Prefers local aarch64 musl cross compile; falls back to Docker when needed.
set -eu

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

can_build_native_docker_test() {
  can_build_aarch64_musl_native && command -v pnpm >/dev/null 2>&1
}

build_native() {
  echo "=== Building Docker integration binaries with local musl toolchain ==="
  setup_aarch64_musl_native_env

  (
    cd "$VENDOR_DIR/easytier-web/frontend"
    export CI=true
    pnpm install --frozen-lockfile 2>/dev/null || pnpm install
    pnpm build
  )

  (
    cd "$VENDOR_DIR"
    rustup target add aarch64-unknown-linux-musl
    cargo build --release --target aarch64-unknown-linux-musl -p easytier --features gateway-policy
    cargo build --release --target aarch64-unknown-linux-musl -p easytier-web --features embed
  )

  copy_easytier_core_artifact "$VENDOR_DIR" "aarch64-unknown-linux-musl" "$DIST_DIR"
  copy_easytier_web_artifact "$VENDOR_DIR" "aarch64-unknown-linux-musl" "$DIST_DIR"
  echo "=== Native Docker test binaries ready in $DIST_DIR ==="
}

build_docker() {
  if ! docker image inspect "$BUILDER_IMAGE" >/dev/null 2>&1; then
    echo "=== Building builder image (one-time) ==="
    docker build -t "$BUILDER_IMAGE" \
      --platform linux/arm64 \
      -f "$SCRIPT_DIR/Dockerfile.builder" \
      "$SCRIPT_DIR"
  fi

  echo "=== Building Docker integration binaries with Docker builder ==="

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
    cargo build --release --target aarch64-unknown-linux-musl -p easytier-web --features embed

    cp target/aarch64-unknown-linux-musl/release/easytier-core /dist/ 2>/dev/null || \
    cp target/aarch64-unknown-linux-musl/release/easytier /dist/easytier-core
    cp target/aarch64-unknown-linux-musl/release/easytier-web /dist/

    echo "--- Done ---"
    ls -lh /dist/
  '
}

case "$BUILD_BACKEND" in
  auto)
    if can_build_native_docker_test; then
      build_native || {
        echo "WARNING: native build failed; falling back to Docker builder" >&2
        build_docker
      }
    else
      echo "=== Local aarch64 musl toolchain or pnpm not found; using Docker builder ==="
      build_docker
    fi
    ;;
  native)
    if ! can_build_native_docker_test; then
      echo "ERROR: native build requires aarch64 musl toolchain and pnpm. Use EASYTIER_BUILD_BACKEND=docker to force Docker." >&2
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

echo "=== Docker test binaries ready in $DIST_DIR ==="
ls -lh "$DIST_DIR"
