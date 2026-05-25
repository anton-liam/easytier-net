# Pre-built builder image with all dependencies for EasyTier compilation
# Build once, reuse for fast incremental builds

FROM rust:latest

# Optional proxy support: pass --build-arg HTTP_PROXY=... at build time
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG ALL_PROXY
ENV http_proxy=${HTTP_PROXY} https_proxy=${HTTPS_PROXY} all_proxy=${ALL_PROXY}

# Use China mirror for apt when no proxy is available
RUN if [ -z "$HTTP_PROXY" ]; then \
      sed -i 's|http://deb.debian.org|http://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
      sed -i 's|http://deb.debian.org|http://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list 2>/dev/null || true; \
    fi

RUN apt-get update && \
    apt-get install -y --fix-missing \
      musl-tools \
      musl-dev \
      pkg-config \
      protobuf-compiler \
      libclang-dev \
      clang \
      gcc \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js via binary (for frontend builds)
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then NODE_ARCH=x64; else NODE_ARCH=$ARCH; fi && \
    curl -fsSL "https://nodejs.org/dist/v20.18.0/node-v20.18.0-linux-${NODE_ARCH}.tar.xz" \
      | tar -xJ --strip-components=1 -C /usr/local/ && \
    npm install -g pnpm

# Create musl-ar symlink (needed by cc crate for musl targets)
RUN ln -sf /usr/bin/ar /usr/local/bin/musl-ar

# Add musl target
RUN rustup target add aarch64-unknown-linux-musl x86_64-unknown-linux-musl

# Set clang env for bindgen
ENV LIBCLANG_PATH=/usr/lib/llvm-19/lib
# Use musl headers for bindgen when cross-compiling to musl targets
ENV BINDGEN_EXTRA_CLANG_ARGS_aarch64_unknown_linux_musl="-isystem /usr/include/aarch64-linux-musl"
ENV BINDGEN_EXTRA_CLANG_ARGS_x86_64_unknown_linux_musl="-isystem /usr/include/x86_64-linux-musl"

# Clear proxy env for runtime (only needed during build)
ENV http_proxy= https_proxy= all_proxy=

WORKDIR /src
