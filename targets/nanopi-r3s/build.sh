#!/usr/bin/env sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
profile_file="$root/targets/nanopi-r3s/openwrt-profile.env"

. "$profile_file"

mkdir -p "$root/dist/nanopi-r3s"

cat > "$root/dist/nanopi-r3s/build-manifest.txt" <<EOF
target=$OPENWRT_TARGET
subtarget=$OPENWRT_SUBTARGET
profile=$OPENWRT_PROFILE
packages=$OPENWRT_PACKAGES
notes=Use OpenWrt ImageBuilder or iStoreOS SDK in a Linux builder to compile packages/firmware.
EOF

echo "NanoPi R3S build manifest written to dist/nanopi-r3s/build-manifest.txt"
echo "Next step: wire this target to the selected OpenWrt/iStoreOS ImageBuilder release."

