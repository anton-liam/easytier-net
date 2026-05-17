#!/usr/bin/env sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
profile_file="$root/targets/nanopi-r3s/openwrt-profile.env"

. "$profile_file"

OPENWRT_VERSION="${OPENWRT_VERSION:-24.10.5}"
SDK_FILENAME="${SDK_FILENAME:-openwrt-sdk-${OPENWRT_VERSION}-${OPENWRT_TARGET}-${OPENWRT_SUBTARGET}_gcc-13.3.0_musl.Linux-x86_64.tar.zst}"
SDK_BASE_URL="${SDK_BASE_URL:-https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${OPENWRT_TARGET}/${OPENWRT_SUBTARGET}}"
SDK_URL="${SDK_URL:-$SDK_BASE_URL/$SDK_FILENAME}"
SHA256SUMS_URL="${SHA256SUMS_URL:-$SDK_BASE_URL/sha256sums}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-$root/build/openwrt-sdk-downloads}"
SDK_PARENT_DIR="${SDK_PARENT_DIR:-$root/build/openwrt-sdk}"

mkdir -p "$DOWNLOAD_DIR" "$SDK_PARENT_DIR" "$root/dist/nanopi-r3s"

archive="$DOWNLOAD_DIR/$SDK_FILENAME"
sha256sums="$DOWNLOAD_DIR/sha256sums-${OPENWRT_VERSION}-${OPENWRT_TARGET}-${OPENWRT_SUBTARGET}"

echo "Downloading checksum:"
echo "  $SHA256SUMS_URL"
curl -fL "$SHA256SUMS_URL" -o "$sha256sums"

expected_line="$(grep "[ *]$SDK_FILENAME\$" "$sha256sums" || true)"
if [ -z "$expected_line" ]; then
  echo "Checksum file does not contain $SDK_FILENAME" >&2
  exit 2
fi

verify_archive() {
  (
    cd "$DOWNLOAD_DIR"
    if command -v sha256sum >/dev/null 2>&1; then
      printf '%s\n' "$expected_line" | sha256sum -c -
    else
      expected_hash="$(printf '%s\n' "$expected_line" | awk '{ print $1 }')"
      actual_hash="$(shasum -a 256 "$SDK_FILENAME" | awk '{ print $1 }')"
      if [ "$expected_hash" != "$actual_hash" ]; then
        echo "$SDK_FILENAME: FAILED" >&2
        exit 1
      fi
      echo "$SDK_FILENAME: OK"
    fi
  )
}

if [ -f "$archive" ] && verify_archive; then
  echo "Reusing verified SDK archive: $archive"
else
  echo "Downloading OpenWrt SDK:"
  echo "  $SDK_URL"
  curl -C - -fL "$SDK_URL" -o "$archive"
  verify_archive
fi

if ! command -v tar >/dev/null 2>&1; then
  echo "tar is required to extract the SDK." >&2
  exit 2
fi

if ! command -v zstd >/dev/null 2>&1; then
  echo "zstd is required to extract $SDK_FILENAME." >&2
  echo "Install zstd on the Linux x86_64 builder, then rerun make fetch-nanopi-r3s-sdk." >&2
  exit 2
fi

echo "Extracting SDK into $SDK_PARENT_DIR"
tar -I zstd -xf "$archive" -C "$SDK_PARENT_DIR"

sdk_dir="$(find "$SDK_PARENT_DIR" -maxdepth 1 -type d -name "openwrt-sdk-${OPENWRT_VERSION}-${OPENWRT_TARGET}-${OPENWRT_SUBTARGET}_*" | sort | tail -n 1)"
if [ -z "$sdk_dir" ]; then
  echo "SDK extraction completed but SDK directory was not found under $SDK_PARENT_DIR" >&2
  exit 1
fi

cat > "$root/dist/nanopi-r3s/sdk-env.sh" <<EOF
export OPENWRT_SDK_DIR='$sdk_dir'
export EASYTIER_DIR='${EASYTIER_DIR:-$root/vendor/EasyTier}'
EOF

echo "SDK ready: $sdk_dir"
echo "Next:"
echo "  . dist/nanopi-r3s/sdk-env.sh"
echo "  make build TARGET=nanopi-r3s"
