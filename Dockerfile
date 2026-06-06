# Runtime image. openclaw is installed at startup into the persistent volume,
# allowing version control via the OPENCLAW_VERSION environment variable.
FROM node:22-bookworm
ENV NODE_ENV=production

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       ca-certificates \
       curl \
       git \
       procps \
       build-essential \
       python3 \
       pkg-config \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g @railway/cli && npm cache clean --force

RUN corepack enable && corepack prepare pnpm@9.15.4 --activate

# QMD markdown-search backend — standalone binary, not version-coupled to openclaw,
# so it stays baked in the image (must be on PATH; OpenClaw shells out to `qmd`).
# Keeps local memory/ + MEMORY.md searchable once the Honcho plugin takes the
# kind:"memory" slot. The Honcho plugin itself is installed at runtime by
# docker-entrypoint.sh, into the same npm prefix as openclaw. See docs/HONCHO.md.
RUN npm install -g @tobilu/qmd

WORKDIR /app

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod

COPY src ./src
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh && mkdir -p /data

# We run as root so the entrypoint can mkdir/install into /data, which
# Railway mounts as root-owned at runtime regardless of build-time chown.
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
