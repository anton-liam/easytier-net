#!/bin/bash
# Shared build helpers for local and Docker based EasyTier builds.

# Detect whether the host has the aarch64 musl toolchain needed for native cross builds.
can_build_aarch64_musl_native() {
  command -v cargo >/dev/null 2>&1 &&
    command -v rustup >/dev/null 2>&1 &&
    command -v aarch64-linux-musl-gcc >/dev/null 2>&1 &&
    command -v aarch64-linux-musl-ar >/dev/null 2>&1
}

# Export the compiler, linker, and bindgen include paths for aarch64 musl.
setup_aarch64_musl_native_env() {
  local cc
  local ar
  local sysroot
  local gcc_include

  cc="$(command -v aarch64-linux-musl-gcc)"
  ar="$(command -v aarch64-linux-musl-ar)"
  sysroot="$("$cc" -print-sysroot)"
  gcc_include="$("$cc" -print-file-name=include)"

  export CC_aarch64_unknown_linux_musl="$cc"
  export AR_aarch64_unknown_linux_musl="$ar"
  export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER="$cc"
  export BINDGEN_EXTRA_CLANG_ARGS_aarch64_unknown_linux_musl="--sysroot=$sysroot -I$sysroot/include -I$gcc_include"
}

# Return the Cargo target directory that will contain compiled artifacts.
cargo_target_dir() {
  if [ -n "${CARGO_TARGET_DIR:-}" ]; then
    printf '%s\n' "$CARGO_TARGET_DIR"
  else
    printf '%s\n' "$1/target"
  fi
}

# Copy the easytier-core artifact for the requested Rust target into the dist directory.
copy_easytier_core_artifact() {
  local vendor_dir="$1"
  local rust_target="$2"
  local dist_dir="$3"
  local target_dir

  target_dir="$(cargo_target_dir "$vendor_dir")"

  cp "$target_dir/$rust_target/release/easytier-core" "$dist_dir/" 2>/dev/null ||
    cp "$target_dir/$rust_target/release/easytier" "$dist_dir/easytier-core"
}

# Copy the easytier-web artifact for the requested Rust target into the dist directory.
copy_easytier_web_artifact() {
  local vendor_dir="$1"
  local rust_target="$2"
  local dist_dir="$3"
  local target_dir

  target_dir="$(cargo_target_dir "$vendor_dir")"

  cp "$target_dir/$rust_target/release/easytier-web" "$dist_dir/"
}
