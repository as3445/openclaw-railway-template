# Runtime image — installs openclaw from npm (no source build needed).
FROM node:22-bookworm
ENV NODE_ENV=production

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    build-essential \
    gcc \
    g++ \
    make \
    procps \
    file \
    git \
    python3 \
    pkg-config \
    sudo \
  && rm -rf /var/lib/apt/lists/*

# Install Railway CLI
RUN npm install -g @railway/cli && npm cache clean --force

# Install Homebrew (must run as non-root user)
RUN useradd -m -s /bin/bash linuxbrew \
  && echo 'linuxbrew ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

USER linuxbrew
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

USER root
RUN chown -R root:root /home/linuxbrew/.linuxbrew
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

# Install openclaw from npm
RUN npm install -g openclaw

WORKDIR /app

# Wrapper deps
RUN npm install -g pnpm
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod --frozen-lockfile && pnpm store prune

COPY src ./src

ENV PORT=8080
EXPOSE 8080

# At startup: install/update triage-gate plugin from npm into the persistent
# extensions dir. Uses '*' to grab the absolute latest version (any dist-tag).
CMD ["sh", "-c", "mkdir -p /data/.openclaw/extensions && echo '[triage-gate] installing latest version...' && npm install --prefix /tmp/triage-gate-install openclaw-triage-gate@'*' 2>&1 | tail -1 && rm -rf /data/.openclaw/extensions/openclaw-triage-gate && cp -r /tmp/triage-gate-install/node_modules/openclaw-triage-gate /data/.openclaw/extensions/openclaw-triage-gate && rm -rf /tmp/triage-gate-install && echo '[triage-gate] installed' ; rm -rf /tmp/jiti; exec node src/server.js"]
