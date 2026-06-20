# Runtime image. openclaw is installed at startup into the persistent volume,
# allowing version control via the OPENCLAW_VERSION environment variable.
FROM node:22-bookworm
ENV NODE_ENV=production
# Home for the unprivileged `app` user; npm/pnpm caches land here at runtime.
ENV HOME=/home/app

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       ca-certificates \
       curl \
       git \
       procps \
       build-essential \
       python3 \
       pkg-config \
       gosu \
  && rm -rf /var/lib/apt/lists/*

# Unprivileged user the workload runs as. The container still starts as root so
# the entrypoint can chown the Railway volume (mounted root-owned at runtime),
# then drops to `app` via gosu before exec-ing anything else.
RUN useradd --system --create-home --home-dir /home/app \
      --shell /usr/sbin/nologin --uid 10001 app

RUN npm install -g @railway/cli && npm cache clean --force

RUN corepack enable && corepack prepare pnpm@9.15.4 --activate

# QMD markdown-search backend — standalone binary, not version-coupled to openclaw,
# so it stays baked in the image (must be on PATH; OpenClaw shells out to `qmd`).
# Keeps local memory/ + MEMORY.md searchable once the Honcho plugin takes the
# kind:"memory" slot. The Honcho plugin itself is installed at runtime by
# docker-entrypoint.sh, into the same npm prefix as openclaw. See docs/HONCHO.md.
RUN npm install -g @tobilu/qmd

# Claude Code CLI — provides the `claude` binary that OpenClaw's claude-cli agent
# backend spawns for model refs like `claude-cli/claude-opus-4-8`. Standalone and
# not version-coupled to openclaw, so it stays baked in the image. Authenticates
# non-interactively via the CLAUDE_CODE_OAUTH_TOKEN env var (a `claude setup-token`
# from a Claude subscription), letting the agent bill the Claude plan instead of
# the Anthropic API. The backend clears ANTHROPIC_API_KEY so subscription auth is used.
RUN npm install -g @anthropic-ai/claude-code && npm cache clean --force

WORKDIR /app

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod

COPY src ./src
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
  && mkdir -p /data \
  && chown -R app:app /app /data /home/app

# The container enters as root so the entrypoint can chown /data (Railway mounts
# the volume root-owned at runtime regardless of build-time chown), then the
# entrypoint immediately drops to the unprivileged `app` user via gosu. The
# long-running workload (wrapper + openclaw gateway + children) never runs as root.
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
