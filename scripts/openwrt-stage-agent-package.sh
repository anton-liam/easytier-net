#!/usr/bin/env sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
sdk_dir="${OPENWRT_SDK_DIR:?OPENWRT_SDK_DIR is required}"
easytier_dir="${EASYTIER_DIR:-$root/vendor/EasyTier}"
package_dir="$sdk_dir/package/easytier-agent"
rust_target="${RUST_TARGET:-aarch64-unknown-linux-musl}"
rust_toolchain="${RUST_TOOLCHAIN:-1.95}"
cargo_home="${OPENWRT_CARGO_HOME:-$root/build/openwrt-cargo-home}"

if [ ! -d "$sdk_dir" ]; then
  echo "OPENWRT_SDK_DIR does not exist: $sdk_dir" >&2
  exit 2
fi

if [ ! -f "$sdk_dir/include/package.mk" ]; then
  echo "OPENWRT_SDK_DIR does not look like an OpenWrt SDK: $sdk_dir" >&2
  echo "Missing include/package.mk" >&2
  exit 2
fi

if [ ! -d "$sdk_dir/staging_dir" ]; then
  echo "OPENWRT_SDK_DIR is incomplete: $sdk_dir" >&2
  echo "Missing staging_dir. Use an extracted OpenWrt/iStoreOS SDK, not ImageBuilder or source root." >&2
  exit 2
fi

if [ ! -x "$sdk_dir/scripts/feeds" ]; then
  echo "OPENWRT_SDK_DIR is incomplete: $sdk_dir" >&2
  echo "Missing executable scripts/feeds." >&2
  exit 2
fi

if ! find "$sdk_dir/staging_dir" -maxdepth 2 -type d -name 'toolchain-*' | grep -q .; then
  echo "OPENWRT_SDK_DIR is incomplete: $sdk_dir" >&2
  echo "Missing staging_dir/toolchain-* for target compiler." >&2
  exit 2
fi

if [ ! -d "$easytier_dir/easytier-agent" ]; then
  echo "EasyTier agent crate is missing: $easytier_dir/easytier-agent" >&2
  exit 2
fi

rm -rf "$package_dir"
mkdir -p "$package_dir/files/etc/config" "$package_dir/files/etc/init.d"

cat > "$package_dir/Makefile" <<EOF
include \$(TOPDIR)/rules.mk

PKG_NAME:=easytier-agent
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

PKG_BUILD_DIR:=\$(BUILD_DIR)/\$(PKG_NAME)-\$(PKG_VERSION)

include \$(INCLUDE_DIR)/package.mk

define Package/easytier-agent
  SECTION:=net
  CATEGORY:=Network
  TITLE:=EasyTier managed gateway policy agent
  DEPENDS:=+libc +ip-full +nftables +ca-bundle
endef

define Package/easytier-agent/description
  Node-side executor for EasyTier Web gateway full tunnel policies.
endef

define Build/Prepare
	mkdir -p \$(PKG_BUILD_DIR)
	cp -a $easytier_dir/. \$(PKG_BUILD_DIR)/
endef

define Build/Compile
	rustup target add --toolchain $rust_toolchain $rust_target
	cd \$(PKG_BUILD_DIR) && \\
	  CARGO_HOME=$cargo_home \\
	  CC_aarch64_unknown_linux_musl="\$(TARGET_CC)" \\
	  AR_aarch64_unknown_linux_musl="\$(TARGET_AR)" \\
	  CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER="\$(TARGET_CC)" \\
	  RUSTFLAGS="-C linker=\$(TARGET_CC)" \\
	  cargo build --release --target $rust_target -p easytier-agent
endef

define Package/easytier-agent/install
	\$(INSTALL_DIR) \$(1)/usr/bin
	\$(INSTALL_BIN) \$(PKG_BUILD_DIR)/target/$rust_target/release/easytier-agent \$(1)/usr/bin/easytier-agent
	\$(INSTALL_DIR) \$(1)/etc/init.d
	\$(INSTALL_BIN) ./files/etc/init.d/easytier-agent \$(1)/etc/init.d/easytier-agent
	\$(INSTALL_DIR) \$(1)/etc/config
	\$(INSTALL_CONF) ./files/etc/config/easytier_agent \$(1)/etc/config/easytier_agent
endef

\$(eval \$(call BuildPackage,easytier-agent))
EOF

cat > "$package_dir/files/etc/init.d/easytier-agent" <<'EOF'
#!/bin/sh /etc/rc.common

START=91
STOP=10
USE_PROCD=1

start_service() {
  local enabled web_base_url user_id machine_id internal_auth_token easytier_ipv4 easytier_iface execute

  enabled="$(uci -q get easytier_agent.main.enabled || echo 0)"
  [ "$enabled" = "1" ] || return 0

  web_base_url="$(uci -q get easytier_agent.main.web_base_url || true)"
  user_id="$(uci -q get easytier_agent.main.user_id || true)"
  machine_id="$(uci -q get easytier_agent.main.machine_id || true)"
  internal_auth_token="$(uci -q get easytier_agent.main.internal_auth_token || true)"
  easytier_ipv4="$(uci -q get easytier_agent.main.easytier_ipv4 || true)"
  easytier_iface="$(uci -q get easytier_agent.main.easytier_iface || true)"
  execute="$(uci -q get easytier_agent.main.execute || echo 0)"

  [ -n "$web_base_url" ] || { echo "missing easytier_agent.main.web_base_url" >&2; return 1; }
  [ -n "$user_id" ] || { echo "missing easytier_agent.main.user_id" >&2; return 1; }
  [ -n "$machine_id" ] || { echo "missing easytier_agent.main.machine_id" >&2; return 1; }
  [ -n "$internal_auth_token" ] || { echo "missing easytier_agent.main.internal_auth_token" >&2; return 1; }

  procd_open_instance
  procd_set_param command /usr/bin/easytier-agent run \
    --platform open-wrt \
    --web-base-url "$web_base_url" \
    --user-id "$user_id" \
    --machine-id "$machine_id" \
    --internal-auth-token "$internal_auth_token"
  [ -n "$easytier_ipv4" ] && procd_append_param command --easytier-ipv4 "$easytier_ipv4"
  [ -n "$easytier_iface" ] && procd_append_param command --easytier-iface "$easytier_iface"
  [ "$execute" = "1" ] && procd_append_param command --execute
  procd_set_param respawn 3600 5 5
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_close_instance
}
EOF

cat > "$package_dir/files/etc/config/easytier_agent" <<'EOF'
config agent 'main'
	option enabled '0'
	option web_base_url ''
	option user_id ''
	option machine_id ''
	option internal_auth_token ''
	option easytier_ipv4 ''
	option easytier_iface 'easytierw0'
	option execute '0'
EOF

echo "Staged OpenWrt package: $package_dir"
