#!/usr/bin/env sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
profile_file="$root/targets/nanopi-r3s/openwrt-profile.env"

. "$profile_file"

mkdir -p "$root/dist/nanopi-r3s"

if [ -z "${OPENWRT_SDK_DIR:-}" ]; then
  cat > "$root/dist/nanopi-r3s/build-manifest.txt" <<EOF
target=$OPENWRT_TARGET
subtarget=$OPENWRT_SUBTARGET
profile=$OPENWRT_PROFILE
packages=$OPENWRT_PACKAGES
status=missing OPENWRT_SDK_DIR
notes=Set OPENWRT_SDK_DIR to a Linux OpenWrt/iStoreOS SDK work directory for rockchip/armv8 friendlyarm_nanopi-r3s, then rerun make build TARGET=nanopi-r3s.
EOF
  echo "NanoPi R3S build requires OPENWRT_SDK_DIR." >&2
  echo "Manifest written to dist/nanopi-r3s/build-manifest.txt" >&2
  exit 2
fi

host_os="$(uname -s)"
host_arch="$(uname -m)"

if [ "$host_os" != "Linux" ]; then
  echo "NanoPi R3S OpenWrt SDK build must run on Linux x86_64." >&2
  echo "Current host is $host_os/$host_arch. Use a Linux x86_64 VM, container, or CI runner." >&2
  exit 2
fi

case "$host_arch" in
  x86_64|amd64)
    ;;
  *)
    echo "NanoPi R3S OpenWrt SDK build must run on Linux x86_64." >&2
    echo "Current host is $host_os/$host_arch. The official OpenWrt SDK is Linux-x86_64." >&2
    exit 2
    ;;
esac

if [ ! -d "$OPENWRT_SDK_DIR" ]; then
  echo "OPENWRT_SDK_DIR does not exist: $OPENWRT_SDK_DIR" >&2
  exit 2
fi

if [ ! -f "$OPENWRT_SDK_DIR/include/package.mk" ]; then
  echo "OPENWRT_SDK_DIR does not look like an OpenWrt SDK: $OPENWRT_SDK_DIR" >&2
  echo "Missing include/package.mk" >&2
  exit 2
fi

if [ ! -d "$OPENWRT_SDK_DIR/staging_dir" ]; then
  echo "OPENWRT_SDK_DIR is incomplete: $OPENWRT_SDK_DIR" >&2
  echo "Missing staging_dir. Use an extracted OpenWrt/iStoreOS SDK, not ImageBuilder or source root." >&2
  exit 2
fi

if [ ! -x "$OPENWRT_SDK_DIR/scripts/feeds" ]; then
  echo "OPENWRT_SDK_DIR is incomplete: $OPENWRT_SDK_DIR" >&2
  echo "Missing executable scripts/feeds." >&2
  exit 2
fi

if ! find "$OPENWRT_SDK_DIR/staging_dir" -maxdepth 2 -type d -name 'toolchain-*' | grep -q .; then
  echo "OPENWRT_SDK_DIR is incomplete: $OPENWRT_SDK_DIR" >&2
  echo "Missing staging_dir/toolchain-* for target compiler." >&2
  exit 2
fi

"$root/scripts/openwrt-stage-agent-package.sh"

echo "Building easytier-agent package with OpenWrt SDK..."
(
  cd "$OPENWRT_SDK_DIR"
  printf '%s\n' 'CONFIG_PACKAGE_easytier-agent=m' > .config
  make defconfig
  make package/easytier-agent/compile V=s
)

find "$OPENWRT_SDK_DIR/bin" -type f -name 'easytier-agent_*.ipk' -exec cp {} "$root/dist/nanopi-r3s/" \;

if ! ls "$root"/dist/nanopi-r3s/easytier-agent_*.ipk >/dev/null 2>&1; then
  echo "easytier-agent ipk was not produced by SDK build." >&2
  exit 1
fi

cat > "$root/dist/nanopi-r3s/build-manifest.txt" <<EOF
target=$OPENWRT_TARGET
subtarget=$OPENWRT_SUBTARGET
profile=$OPENWRT_PROFILE
packages=$OPENWRT_PACKAGES
sdk=$OPENWRT_SDK_DIR
status=agent ipk built
notes=Install dist/nanopi-r3s/easytier-agent_*.ipk on iStoreOS/R3S and run /usr/bin/easytier-agent --help.
EOF

echo "NanoPi R3S build manifest written to dist/nanopi-r3s/build-manifest.txt"
ls -lh "$root"/dist/nanopi-r3s/easytier-agent_*.ipk
