#!/bin/sh
set -eu

# ===== TEMPORARY DIAGNOSTIC ENTRYPOINT =====
# Binds PORT so Railway marks the deploy active (enabling `railway ssh`/Console),
# then idles so we can reproduce the real boot by hand and find what hangs.
# Restore the real entrypoint after diagnosis.

if [ "$(id -u)" = "0" ]; then
  mkdir -p /data
  chown app:app /data
  exec gosu app "$0" "$@"
fi

echo "[diag] entrypoint reached as $(id -un)"
node -e 'const p=process.env.PORT||8080;require("http").createServer((_q,r)=>{r.writeHead(200);r.end("diag ok\n")}).listen(p,()=>console.log("[diag] keepalive listening on "+p))' &
echo "[diag] keepalive started; sleeping so container stays shell-able"
exec sleep infinity
