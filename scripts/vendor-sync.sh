#!/usr/bin/env sh
set -eu

EASYTIER_REPO="${EASYTIER_REPO:-https://github.com/EasyTier/EasyTier.git}"
LUCI_REPO="${LUCI_REPO:-https://github.com/EasyTier/luci-app-easytier.git}"

mkdir -p vendor

sync_repo() {
  name="$1"
  repo="$2"
  path="vendor/$name"

  if [ -d "$path/.git" ]; then
    echo "Updating $path"
    git -C "$path" fetch --all --tags --prune
  else
    echo "Cloning $repo -> $path"
    git clone "$repo" "$path"
  fi
}

sync_repo EasyTier "$EASYTIER_REPO"
sync_repo luci-app-easytier "$LUCI_REPO"

echo "Vendor repositories are ready."

