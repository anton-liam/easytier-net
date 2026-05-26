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
CACHE_DIR="$PROJECT_DIR/build/imagebuilder/$TARGET"
EASYTIER_BIN="$PROJECT_DIR/dist/aarch64/easytier-core"
INCLUDE_LUCI_APP="${EASYTIER_INCLUDE_LUCI:-1}"
LUCI_APP_VENDOR_DIR="${EASYTIER_LUCI_APP_VENDOR_DIR:-$PROJECT_DIR/vendor/luci-app-easytier}"
LUCI_APP_DIR="${EASYTIER_LUCI_APP_DIR:-$LUCI_APP_VENDOR_DIR/luci-app-easytier}"
IMAGEBUILDER_DOCKER_IMAGE="${EASYTIER_IMAGEBUILDER_DOCKER_IMAGE:-easytier-openwrt-builder:debian12}"
IMAGEBUILDER_DOCKERFILE="$PROJECT_DIR/scripts/Dockerfile.imagebuilder"

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

mkdir -p "$DIST_DIR" "$CACHE_DIR"

resolve_luci_app_dir() {
  [ "$INCLUDE_LUCI_APP" = "1" ] || return 0

  if [ -d "$LUCI_APP_DIR/luasrc" ]; then
    return 0
  fi

  if [ -n "${EASYTIER_LUCI_APP_DIR:-}" ]; then
    echo "ERROR: EASYTIER_LUCI_APP_DIR does not point to a LuCI package directory: $LUCI_APP_DIR" >&2
    echo "Expected a directory containing luasrc/." >&2
    exit 1
  fi

  echo "ERROR: luci-app-easytier submodule is not initialized: $LUCI_APP_DIR" >&2
  echo "Run: git submodule update --init --recursive" >&2
  echo "Or set EASYTIER_LUCI_APP_DIR to a package directory containing luasrc/." >&2
  exit 1
}

# Check that easytier-core aarch64 binary exists
if [ ! -f "$EASYTIER_BIN" ]; then
  echo "ERROR: $EASYTIER_BIN not found. Run 'make build-openwrt' first."
  exit 1
fi

resolve_luci_app_dir

if ! docker image inspect "$IMAGEBUILDER_DOCKER_IMAGE" >/dev/null 2>&1; then
  if [ -f "$IMAGEBUILDER_DOCKERFILE" ]; then
    echo "=== ImageBuilder Docker image '$IMAGEBUILDER_DOCKER_IMAGE' not found; building it once ==="
    if ! docker build --platform linux/amd64 \
      --build-arg HTTP_PROXY="${HTTP_PROXY:-${http_proxy:-}}" \
      --build-arg HTTPS_PROXY="${HTTPS_PROXY:-${https_proxy:-}}" \
      --build-arg ALL_PROXY="${ALL_PROXY:-${all_proxy:-}}" \
      -f "$IMAGEBUILDER_DOCKERFILE" \
      -t "$IMAGEBUILDER_DOCKER_IMAGE" \
      "$PROJECT_DIR/scripts"; then
      echo "=== Failed to build '$IMAGEBUILDER_DOCKER_IMAGE'; using debian:bookworm-slim ==="
      IMAGEBUILDER_DOCKER_IMAGE="debian:bookworm-slim"
    fi
  else
    echo "=== ImageBuilder Docker image '$IMAGEBUILDER_DOCKER_IMAGE' not found; using debian:bookworm-slim ==="
    IMAGEBUILDER_DOCKER_IMAGE="debian:bookworm-slim"
  fi
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
  -v "$CACHE_DIR":/cache \
  -v "$EASYTIER_BIN":/tmp/easytier-core:ro \
  -v "$LUCI_APP_DIR":/tmp/luci-app-easytier:ro \
  -v "$PROJECT_DIR/targets/$TARGET":/tmp/target-files:ro \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  -e EASYTIER_INCLUDE_LUCI="$INCLUDE_LUCI_APP" \
  --platform linux/amd64 \
  "$IMAGEBUILDER_DOCKER_IMAGE" \
  bash -c "
    set -eu

    # Install ImageBuilder dependencies only when using a plain Debian image.
    if ! command -v wget >/dev/null 2>&1 || ! command -v zstd >/dev/null 2>&1 || ! command -v gawk >/dev/null 2>&1; then
      if [ -z \"\${HTTP_PROXY:-}\" ] && [ -z \"\${http_proxy:-}\" ]; then
        sed -i 's|http://deb.debian.org|http://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || true
      fi
      apt-get update -qq
      apt-get install -y -qq wget zstd build-essential libncurses-dev gawk unzip file python3 >/dev/null 2>&1
    fi

    # Cache the ImageBuilder archive on the host, but extract it inside the
    # container so OpenWrt sees a case-sensitive Linux filesystem.
    if [ ! -f /cache/imagebuilder.tar.zst ] || [ ! -f /cache/.imagebuilder-url ] || [ \"\$(cat /cache/.imagebuilder-url)\" != '$IB_URL' ]; then
      echo '--- Downloading ImageBuilder ---'
      rm -rf /cache/ib /cache/dl /cache/imagebuilder.tar.zst
      wget -q '$IB_URL' -O /cache/imagebuilder.tar.zst
      printf '%s' '$IB_URL' > /cache/.imagebuilder-url
    else
      echo '--- Reusing cached ImageBuilder archive ---'
    fi

    rm -rf /cache/ib /tmp/ib
    mkdir -p /tmp/ib
    tar --zstd -xf /cache/imagebuilder.tar.zst -C /tmp/ib --strip-components=1

    cd /tmp/ib
    rm -rf files bin
    mkdir -p /cache/dl
    rm -rf dl
    ln -s /cache/dl dl

    # Create rootfs overlay: inject easytier binary + startup config
    mkdir -p files/usr/bin
    mkdir -p files/etc/init.d
    mkdir -p files/etc/uci-defaults
    mkdir -p files/etc/config
    mkdir -p files/etc/easytier

    # Copy easytier binary
    cp /tmp/easytier-core files/usr/bin/easytier-core
    chmod +x files/usr/bin/easytier-core

    # Install LuCI pages without replacing our minimal service scripts.
    # The image keeps the productized webclient service as the default entry.
    if [ \"\$EASYTIER_INCLUDE_LUCI\" = \"1\" ]; then
      mkdir -p files/usr/lib/lua/luci/controller
      mkdir -p files/usr/lib/lua/luci/model/cbi
      mkdir -p files/usr/lib/lua/luci/view
      cp -r /tmp/luci-app-easytier/luasrc/controller/* files/usr/lib/lua/luci/controller/
      cp -r /tmp/luci-app-easytier/luasrc/model/* files/usr/lib/lua/luci/model/
      cp -r /tmp/luci-app-easytier/luasrc/view/* files/usr/lib/lua/luci/view/

      if [ -d /tmp/luci-app-easytier/root/usr/share/easytier ]; then
        mkdir -p files/usr/share
        cp -r /tmp/luci-app-easytier/root/usr/share/easytier files/usr/share/
      fi
      if [ -f /tmp/luci-app-easytier/root/usr/share/rpcd/acl.d/luci-app-easytier.json ]; then
        mkdir -p files/usr/share/rpcd/acl.d
        cp /tmp/luci-app-easytier/root/usr/share/rpcd/acl.d/luci-app-easytier.json files/usr/share/rpcd/acl.d/
      fi
      if [ -f /tmp/luci-app-easytier/root/etc/easytier/config.toml ]; then
        cp /tmp/luci-app-easytier/root/etc/easytier/config.toml files/etc/easytier/config.toml
      fi

      cat > files/usr/share/rpcd/acl.d/luci-app-easytier-webclient.json <<'ACLEOF'
{
  "luci-app-easytier-webclient": {
    "description": "Grant UCI access for EasyTier webclient service",
    "read": {
      "uci": [ "easytier", "easytier_webclient", "easytier_agent" ],
      "cgi-io": [ "upload" ]
    },
    "write": {
      "uci": [ "easytier", "easytier_webclient", "easytier_agent" ]
    }
  }
}
ACLEOF
    fi

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
    local web_config
    local proxy_forward_by_system
    config_load easytier
    config_get_bool enabled core enabled 0
    config_get config_server core config_server ''
    config_get web_config core web_config ''
    config_get_bool proxy_forward_by_system core proxy_forward_by_system 1

    [ -n "\$config_server" ] || config_server="\$web_config"
    [ "\$enabled" = "1" ] || return
    [ -z \"\$config_server\" ] && return

    procd_open_instance
    if [ "\$proxy_forward_by_system" = "1" ]; then
        procd_set_param command /usr/bin/easytier-core -w \"\$config_server\" --proxy-forward-by-system
    else
        procd_set_param command /usr/bin/easytier-core -w \"\$config_server\"
    fi
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
INITEOF
    chmod +x files/etc/init.d/easytier

    # Web-console managed core service. LuCI status uses this service name
    # to expose a dedicated process switch for easytier-core -w.
    cat > files/etc/init.d/easytier-core-webclient <<'WEBCLIENTEOF'
#!/bin/sh /etc/rc.common

START=99
STOP=10
USE_PROCD=1

start_service() {
    local enabled
    local config_server
    local proxy_forward_by_system
    config_load easytier_webclient
    config_get_bool enabled main enabled 0
    config_get config_server main config_server ''
    config_get_bool proxy_forward_by_system main proxy_forward_by_system 1

    [ "\$enabled" = "1" ] || return
    [ -z "\$config_server" ] && return

    procd_open_instance
    if [ "\$proxy_forward_by_system" = "1" ]; then
        procd_set_param command /bin/sh -c 'date +%s > /tmp/easytier_time; exec "\$@"' easytier-webclient /usr/bin/easytier-core -w "\$config_server" --proxy-forward-by-system
    else
        procd_set_param command /bin/sh -c 'date +%s > /tmp/easytier_time; exec "\$@"' easytier-webclient /usr/bin/easytier-core -w "\$config_server"
    fi
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
WEBCLIENTEOF
    chmod +x files/etc/init.d/easytier-core-webclient

    # UCI defaults: keep local core disabled and enable webclient mode when
    # EASYTIER_CONFIG_SERVER is provided by .env.
    cat > files/etc/uci-defaults/99-easytier <<'UCIEOF'
#!/bin/sh
uci -q batch <<-EOT
    set easytier.core=easytier
    set easytier.core.enabled='0'
    set easytier.core.etcmd='web'
    set easytier.core.web_config='$DEFAULT_CONFIG_SERVER'
    set easytier.core.config_server=''
    set easytier.core.proxy_forward_by_system='1'
    set easytier.core.easytierbin='/usr/bin/easytier-core'
    set easytier.core.tunname='tun0'
    set easytier.core.dev_name='tun0'
    set easytier.core.web_enabled='0'
    set easytier_webclient.main=easytier_webclient
    set easytier_webclient.main.enabled='$DEFAULT_ENABLED'
    set easytier_webclient.main.config_server='$DEFAULT_CONFIG_SERVER'
    set easytier_webclient.main.proxy_forward_by_system='1'
    commit easytier
    commit easytier_webclient
EOT
/etc/init.d/easytier enable
/etc/init.d/easytier-core-webclient enable
[ '$DEFAULT_ENABLED' = '1' ] && /etc/init.d/easytier-core-webclient start
exit 0
UCIEOF
    chmod +x files/etc/uci-defaults/99-easytier

    # Build image
    echo '--- Building image ---'
    make image PROFILE='$PROFILE' FILES=files \
      PACKAGES='nftables ip-full kmod-nft-nat kmod-tun luci luci-base luci-compat luci-lib-jsonc uhttpd cgi-io curl ca-bundle'

    # Copy output with deterministic preference for squashfs sysupgrade images.
    echo '--- ImageBuilder outputs ---'
    find bin/targets -type f | sort

    IMAGE_OUT=\"\$(find bin/targets -type f -name '*squashfs-sysupgrade.img.gz' | sort | head -n 1)\"
    if [ -z \"\$IMAGE_OUT\" ]; then
      IMAGE_OUT=\"\$(find bin/targets -type f -name '*ext4-sysupgrade.img.gz' | sort | head -n 1)\"
    fi
    if [ -z \"\$IMAGE_OUT\" ]; then
      IMAGE_OUT=\"\$(find bin/targets -type f -name '*.img.gz' | sort | head -n 1)\"
    fi
    if [ -z \"\$IMAGE_OUT\" ]; then
      IMAGE_OUT=\"\$(find bin/targets -type f -name '*.img' | sort | head -n 1)\"
    fi

    if [ -z \"\$IMAGE_OUT\" ]; then
      echo 'ERROR: no image file found in ImageBuilder output' >&2
      exit 1
    fi

    case \"\$IMAGE_OUT\" in
      *.img.gz) cp \"\$IMAGE_OUT\" /dist/openwrt-${TARGET}.img.gz ;;
      *.img) cp \"\$IMAGE_OUT\" /dist/openwrt-${TARGET}.img ;;
      *) echo \"ERROR: unsupported image output: \$IMAGE_OUT\" >&2; exit 1 ;;
    esac
    chown \"\$HOST_UID:\$HOST_GID\" /dist/openwrt-${TARGET}.img* 2>/dev/null || true

    echo '--- Done ---'
    ls -lh /dist/
  "

echo "=== Image ready: $DIST_DIR/openwrt-${TARGET}.img.gz ==="
