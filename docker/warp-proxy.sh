#!/bin/sh
# Starts a local HTTP proxy on 127.0.0.1:$WARP_PROXY_PORT that tunnels traffic
# through Cloudflare WARP (free), so YouTube sees a Cloudflare IP instead of the
# hosting provider's datacenter IP.
#
# - wgcf registers a free WARP device and writes a WireGuard profile
# - wireproxy runs that WireGuard tunnel in userspace (no root, no kernel module)
#   and exposes it as an HTTP proxy
#
# Exits 0 once the proxy answers, non-zero otherwise (the caller then runs the
# bot without proxy).
set -eu

DIR="${WARP_DIR:-/tmp/warp}"
PORT="${WARP_PROXY_PORT:-8118}"
TRACE_URL="https://www.cloudflare.com/cdn-cgi/trace"

mkdir -p "$DIR"
cd "$DIR"

if [ ! -f wgcf-account.toml ]; then
  echo "[WARP] Registering a free WARP device..."
  wgcf register --accept-tos >/dev/null 2>&1 || { echo "[WARP] wgcf register failed"; exit 1; }
fi
wgcf generate >/dev/null 2>&1 || { echo "[WARP] wgcf generate failed"; exit 1; }

cat > wireproxy.conf <<EOF
WGConfig = $DIR/wgcf-profile.conf

[http]
BindAddress = 127.0.0.1:$PORT
EOF

echo "[WARP] Starting wireproxy on 127.0.0.1:$PORT..."
wireproxy -s -c wireproxy.conf &

i=0
while [ "$i" -lt 30 ]; do
  i=$((i + 1))
  sleep 1
  if trace=$(curl -fsS --max-time 5 -x "http://127.0.0.1:$PORT" "$TRACE_URL" 2>/dev/null); then
    warp=$(echo "$trace" | sed -n 's/^warp=//p')
    colo=$(echo "$trace" | sed -n 's/^colo=//p')
    echo "[WARP] Proxy up after ${i}s (warp=$warp, colo=$colo)"
    [ "$warp" = "on" ] || [ "$warp" = "plus" ] || { echo "[WARP] Traffic is not going through WARP"; exit 1; }
    exit 0
  fi
done

echo "[WARP] Proxy did not come up within 30s"
exit 1
