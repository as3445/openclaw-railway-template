#!/bin/sh
set -eu

# Railway mounts the /data volume root-owned at runtime, regardless of any
# build-time chown. Fix ownership while we still have root, then re-exec this
# same script as the unprivileged `app` user so everything below — npm installs
# into /data, pruning, and the Node wrapper itself — runs without root.
if [ "$(id -u)" = "0" ]; then
  mkdir -p /data
  # /data holds a ~5GB persistent volume. Railway remounts its ROOT root-owned
  # each boot, but the CONTENTS (created by the app user) keep app ownership, so a
  # full `chown -R /data` over thousands of files on a network volume hangs long
  # enough to blow the deploy/healthcheck window (the first boot only passed because
  # /data was still empty). Chown just the mount root so app can write there.
  chown app:app /data
  exec gosu app "$0" "$@"
fi

VERSION="${OPENCLAW_VERSION:-latest}"
if [ "$VERSION" = "latest" ]; then
  echo "[entrypoint] resolving latest openclaw version..."
  VERSION="$(npm view openclaw version 2>/dev/null || true)"
  if [ -z "$VERSION" ]; then
    echo "[entrypoint] failed to resolve latest openclaw version" >&2
    exit 1
  fi
fi
echo "[entrypoint] openclaw version: $VERSION"

PREFIX="/data/openclaw-runtime/$VERSION"
ENTRY="$PREFIX/lib/node_modules/openclaw/dist/entry.js"

if [ ! -f "$ENTRY" ]; then
  echo "[entrypoint] installing openclaw@$VERSION into $PREFIX..."
  mkdir -p "$PREFIX"
  NPM_CONFIG_PREFIX="$PREFIX" npm install -g \
    "openclaw@$VERSION" \
    openclaw-plugin-google \
    @honcho-ai/openclaw-honcho
fi

if [ ! -f "$ENTRY" ]; then
  echo "[entrypoint] install failed: $ENTRY missing" >&2
  exit 1
fi

if [ -d /data/openclaw-runtime ]; then
  echo "[entrypoint] pruning old versions (keeping $VERSION)..."
  find /data/openclaw-runtime -mindepth 1 -maxdepth 1 -type d \
       ! -name "$VERSION" \
       -exec rm -rf {} + 2>/dev/null || true
fi

export OPENCLAW_ENTRY="$ENTRY"
echo "[entrypoint] OPENCLAW_ENTRY=$ENTRY"
echo "[entrypoint] starting wrapper..."
exec node src/server.js
