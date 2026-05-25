#!/bin/bash
# Build OpenWrt firmware image with EasyTier pre-installed
# Uses OpenWrt ImageBuilder to inject easytier binary + config
#
# Usage: ./build-image.sh <target>
#   target: r3s | rpi4 | rpi5
set -eu

TARGET="${1:?Usage: $0 <r3s|rpi4|rpi5>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist/images"
EASYTIER_BIN="$PROJECT_DIR/dist/aarch64/easytier-core"

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$PROJECT_DIR/.env"
  set +a
fi

DEFAULT_CONFIG_SERVER="${EASYTIER_CONFIG_SERVER:-}"
DEFAULT_ENABLED="0"
if [ -n "$DEFAULT_CONFIG_SERVER" ]; then
  DEFAULT_ENABLED="1"
fi

mkdir -p "$DIST_DIR"

# Check that easytier-core aarch64 binary exists
if [ ! -f "$EASYTIER_BIN" ]; then
  echo "ERROR: $EASYTIER_BIN not found. Run 'make build-openwrt' first."
  exit 1
fi

# Device-specific ImageBuilder config
case "$TARGET" in
  r3s)
    IB_URL="https://downloads.openwrt.org/releases/24.10.1/targets/rockchip/armv8/openwrt-imagebuilder-24.10.1-rockchip-armv8.Linux-x86_64.tar.zst"
    PROFILE="friendlyarm_nanopi-r3s"
    DEVICE_TEMPLATE="dualport"
    ;;
  rpi4)
    IB_URL="https://downloads.openwrt.org/releases/24.10.1/targets/bcm27xx/bcm2711/openwrt-imagebuilder-24.10.1-bcm27xx-bcm2711.Linux-x86_64.tar.zst"
    PROFILE="rpi-4"
    DEVICE_TEMPLATE="singleport"
    ;;
  rpi5)
    IB_URL="https://downloads.openwrt.org/releases/24.10.1/targets/bcm27xx/bcm2712/openwrt-imagebuilder-24.10.1-bcm27xx-bcm2712.Linux-x86_64.tar.zst"
    PROFILE="rpi-5"
    DEVICE_TEMPLATE="singleport"
    ;;
  *)
    echo "ERROR: unknown target '$TARGET'. Use: r3s | rpi4 | rpi5"
    exit 1
    ;;
esac

echo "=== Building OpenWrt image for $TARGET ($PROFILE) ==="
if [ -n "$DEFAULT_CONFIG_SERVER" ]; then
  echo "=== Default config-server: $DEFAULT_CONFIG_SERVER ==="
else
  echo "=== Default config-server: disabled (set EASYTIER_CONFIG_SERVER in .env to enable) ==="
fi

docker run --rm \
  -v "$DIST_DIR":/dist \
  -v "$EASYTIER_BIN":/tmp/easytier-core:ro \
  -v "$PROJECT_DIR/targets/$TARGET":/tmp/target-files:ro \
  --platform linux/amd64 \
  debian:bookworm-slim \
  bash -c "
    set -eu

    # Install ImageBuilder dependencies
    apt-get update -qq
    apt-get install -y -qq wget zstd build-essential libncurses-dev gawk unzip file python3 >/dev/null 2>&1

    # Download and extract ImageBuilder
    cd /tmp
    echo '--- Downloading ImageBuilder ---'
    wget -q '$IB_URL' -O imagebuilder.tar.zst
    mkdir -p /tmp/ib
    tar --zstd -xf imagebuilder.tar.zst -C /tmp/ib --strip-components=1

    cd /tmp/ib

    # Create rootfs overlay: inject easytier binary + startup config
    mkdir -p files/usr/bin
    mkdir -p files/etc/init.d
    mkdir -p files/etc/uci-defaults

    # Copy easytier binary
    cp /tmp/easytier-core files/usr/bin/easytier-core
    chmod +x files/usr/bin/easytier-core

    # Copy target-specific files if they exist
    if [ -d /tmp/target-files/files ]; then
      cp -r /tmp/target-files/files/* files/ 2>/dev/null || true
    fi

    # Create procd init script
    cat > files/etc/init.d/easytier <<'INITEOF'
#!/bin/sh /etc/rc.common

START=99
STOP=10
USE_PROCD=1

start_service() {
    local enabled
    local config_server
    config_load easytier
    config_get_bool enabled core enabled 0
    config_get config_server core config_server ''

    [ "\$enabled" = "1" ] || return
    [ -z \"\$config_server\" ] && return

    procd_open_instance
    procd_set_param command /usr/bin/easytier-core -w \"\$config_server\"
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
INITEOF
    chmod +x files/etc/init.d/easytier

    # UCI defaults: enable easytier on first boot
    cat > files/etc/uci-defaults/99-easytier <<'UCIEOF'
#!/bin/sh
uci -q batch <<-EOT
    set easytier.core=easytier
    set easytier.core.enabled='$DEFAULT_ENABLED'
    set easytier.core.config_server='$DEFAULT_CONFIG_SERVER'
    commit easytier
EOT
/etc/init.d/easytier enable
exit 0
UCIEOF
    chmod +x files/etc/uci-defaults/99-easytier

    # Build image
    echo '--- Building image ---'
    make image PROFILE='$PROFILE' FILES=files \
      PACKAGES='nftables ip-full kmod-nft-nat kmod-tun luci luci-base uhttpd curl ca-bundle'

    # Copy output
    cp bin/targets/*/*/*.img.gz /dist/openwrt-${TARGET}.img.gz 2>/dev/null || \
    cp bin/targets/*/*/*.img /dist/openwrt-${TARGET}.img 2>/dev/null || \
    echo 'WARNING: no image file found in output'

    echo '--- Done ---'
    ls -lh /dist/
  "

echo "=== Image ready: $DIST_DIR/openwrt-${TARGET}.img.gz ==="
