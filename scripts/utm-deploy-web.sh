#!/usr/bin/env sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

easy_tier_dir="${EASYTIER_DIR:-$root/.worktrees/gateway-full-tunnel/vendor/EasyTier}"
host="${UTM_WEB_HOST:-192.168.64.4}"
user="${UTM_WEB_USER:-anton}"
remote_dir="${UTM_REMOTE_DIR:-/tmp/EasyTier}"
api_host="${UTM_API_HOST:-http://$host:11211}"
db_path="${UTM_WEB_DB:-/var/lib/easytier/easytier-web.db}"
internal_token="${UTM_INTERNAL_AUTH_TOKEN:-easytier-lab-internal-token}"

if [ ! -d "$easy_tier_dir" ]; then
  echo "EasyTier workspace not found: $easy_tier_dir" >&2
  echo "Set EASYTIER_DIR=/path/to/EasyTier and retry." >&2
  exit 1
fi

echo "Syncing EasyTier source to $user@$host:$remote_dir"
(
  cd "$easy_tier_dir"
  COPYFILE_DISABLE=1 tar \
    --exclude='.git' \
    --exclude='target' \
    --exclude='node_modules' \
    --exclude='frontend-lib/node_modules' \
    --exclude='frontend/node_modules' \
    --exclude='._*' \
    --exclude='.DS_Store' \
    -czf - .
) | ssh "$user@$host" "set -eu; rm -rf '$remote_dir'; mkdir -p '$remote_dir'; tar -xzf - -C '$remote_dir'; find '$remote_dir' -name '._*' -delete"

echo "Building easytier-web embed on $host"
ssh "$user@$host" "set -eu; export PATH=\"\$HOME/.cargo/bin:\$PATH\"; cd '$remote_dir'; rm -rf target; CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_DEV_INCREMENTAL=false cargo build -p easytier-web --features embed; file target/debug/easytier-web"

echo "Installing and restarting easytier-web-embed on $host"
ssh "$user@$host" "set -eu; \
  sudo_with_password() { printf '%s\n' '${UTM_WEB_PASSWORD:-$user}' | sudo -S \"\$@\"; }; \
  if [ -x /usr/local/bin/easytier-web-embed ]; then sudo_with_password cp /usr/local/bin/easytier-web-embed /usr/local/bin/easytier-web-embed.bak.\$(date +%Y%m%d%H%M%S); fi; \
  pids=\$(pgrep -f '^/usr/local/bin/easytier-web-embed( |$)' || true); \
  if [ -n \"\$pids\" ]; then \
    sudo_with_password kill \$pids; \
    for _ in 1 2 3 4 5; do \
      remaining=\$(pgrep -f '^/usr/local/bin/easytier-web-embed( |$)' || true); \
      [ -z \"\$remaining\" ] && break; \
      sleep 1; \
    done; \
    remaining=\$(pgrep -f '^/usr/local/bin/easytier-web-embed( |$)' || true); \
    if [ -n \"\$remaining\" ]; then sudo_with_password kill -9 \$remaining; fi; \
  fi; \
  sudo_with_password install -m 0755 '$remote_dir/target/debug/easytier-web' /usr/local/bin/easytier-web-embed; \
  nohup /usr/local/bin/easytier-web-embed \
    -d '$db_path' \
    -p udp \
    -c 22020 \
    -a 11211 \
    --api-host '$api_host' \
    --internal-auth-token '$internal_token' \
    --console-log-level info \
    > /tmp/easytier-web-embed.log 2>&1 & \
  sleep 3; \
  pgrep -af '^/usr/local/bin/easytier-web-embed( |$)'; \
  curl --noproxy '*' -fsS -o /dev/null '$api_host/'"

echo "UTM web console is ready: $api_host"
