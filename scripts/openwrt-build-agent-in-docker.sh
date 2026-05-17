#!/usr/bin/env sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
base_image="${OPENWRT_BUILDER_BASE_IMAGE:-debian:12}"
image="${OPENWRT_BUILDER_IMAGE:-easytier-openwrt-builder:debian12}"
platform="${OPENWRT_BUILDER_PLATFORM:-linux/amd64}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for build-nanopi-r3s-docker." >&2
  exit 2
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not running or not reachable." >&2
  echo "Start Docker Desktop or another Docker daemon, then rerun make build-nanopi-r3s-docker." >&2
  exit 2
fi

if ! docker image inspect "$image" >/dev/null 2>&1; then
  docker build \
    --platform "$platform" \
    --build-arg BASE_IMAGE="$base_image" \
    --build-arg APT_MIRROR="${APT_MIRROR:-}" \
    --build-arg RUSTUP_DIST_SERVER="${RUSTUP_DIST_SERVER:-}" \
    --build-arg RUSTUP_UPDATE_ROOT="${RUSTUP_UPDATE_ROOT:-}" \
    -t "$image" \
    -f - "$root" <<'EOF'
ARG BASE_IMAGE=debian:12
FROM ${BASE_IMAGE}
ARG APT_MIRROR=
ARG RUSTUP_DIST_SERVER=
ARG RUSTUP_UPDATE_ROOT=
ENV DEBIAN_FRONTEND=noninteractive
RUN if [ -n "$APT_MIRROR" ]; then \
      sed -i "s|http://deb.debian.org/debian|$APT_MIRROR|g" /etc/apt/sources.list.d/debian.sources; \
    fi \
 && apt-get -o Acquire::Retries=5 update \
 && apt-get -o Acquire::Retries=5 install -y --fix-missing --no-install-recommends \
      bash build-essential ca-certificates curl file gawk gettext git libncurses-dev \
      python3 python3-distutils rsync tar unzip wget xz-utils zstd \
 && rm -rf /var/lib/apt/lists/*
ENV RUSTUP_DIST_SERVER=${RUSTUP_DIST_SERVER}
ENV RUSTUP_UPDATE_ROOT=${RUSTUP_UPDATE_ROOT}
RUN curl --retry 5 --retry-delay 2 --retry-all-errors --proto "=https" --tlsv1.2 -fsSL \
      https://sh.rustup.rs -o /tmp/rustup-init.sh \
 && sh /tmp/rustup-init.sh -y --profile minimal --default-toolchain stable \
 && rm -f /tmp/rustup-init.sh
ENV PATH=/root/.cargo/bin:${PATH}
RUN rustup target add aarch64-unknown-linux-musl
EOF
fi

docker run --rm \
  --platform "$platform" \
  -v "$root:/work" \
  -w /work \
  "$image" \
  /bin/sh -eu -c '
    SDK_PARENT_DIR=/tmp/openwrt-sdk make fetch-nanopi-r3s-sdk
    . dist/nanopi-r3s/sdk-env.sh
    EASYTIER_DIR=/work/.worktrees/gateway-full-tunnel/vendor/EasyTier \
      make build TARGET=nanopi-r3s
  '
