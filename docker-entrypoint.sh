#!/bin/sh
set -eu
# ===== TEMPORARY DIAGNOSTIC ENTRYPOINT (bind :8080 first, then reproduce boot) =====
if [ "$(id -u)" = "0" ]; then
  mkdir -p /data
  chown app:app /data
  exec gosu app "$0" "$@"
fi

# Bind the port immediately so Railway marks the deploy active + shell-able,
# regardless of whether the real boot below hangs.
node -e 'const p=process.env.PORT||8080;require("http").createServer((_q,r)=>{r.writeHead(200);r.end("diag\n")}).listen(p,()=>console.log("[diag] listening on "+p))' &
KEEPALIVE=$!

# Reproduce the real boot IN THE BACKGROUND, logging each step to /tmp/boot.log,
# so we can read exactly where it hangs via ssh without blocking the keepalive.
(
  echo "[boot] start $(date)"
  VERSION="${OPENCLAW_VERSION:-latest}"
  echo "[boot] VERSION=$VERSION"
  PREFIX="/data/openclaw-runtime/$VERSION"
  ENTRY="$PREFIX/lib/node_modules/openclaw/dist/entry.js"
  echo "[boot] du -sh /data:"; du -sh /data 2>&1 | head
  echo "[boot] ls /data:"; ls -la /data 2>&1 | head -30
  echo "[boot] ENTRY exists?"; test -f "$ENTRY" && echo yes || echo no
  echo "[boot] done $(date)"
) > /tmp/boot.log 2>&1 &

echo "[diag] keepalive pid=$KEEPALIVE; boot probe running -> /tmp/boot.log; idling"
wait "$KEEPALIVE"
