#!/bin/sh
set -eu

ROLE=$(hostname)
echo "[$ROLE] starting..."

# TODO: if web, start easytier-web + easytier-core config-server
# if [ "$ROLE" = "web" ]; then
#   easytier-core --config-server ... &
#   easytier-web --listen 0.0.0.0:11211 &
# fi

echo "[$ROLE] ready"
sleep infinity
