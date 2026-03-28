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

# Stage triage-gate plugin (will be copied to volume at startup)
RUN npm install --prefix /opt/openclaw-triage-gate openclaw-triage-gate@latest && \
    mv /opt/openclaw-triage-gate/node_modules/openclaw-triage-gate /opt/openclaw-triage-gate-pkg && \
    rm -rf /opt/openclaw-triage-gate

WORKDIR /app

# Wrapper deps
RUN npm install -g pnpm
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod --frozen-lockfile && pnpm store prune

COPY src ./src

ENV PORT=8080
EXPOSE 8080

# At startup: install triage-gate plugin to the global extensions dir on the
# persistent volume. Only copy if the dir doesn't already exist (so manual
# fixes and openclaw plugin install updates persist across redeploys).
CMD ["sh", "-c", "mkdir -p /data/.openclaw/extensions && if [ ! -d /data/.openclaw/extensions/openclaw-triage-gate ]; then cp -r /opt/openclaw-triage-gate-pkg /data/.openclaw/extensions/openclaw-triage-gate && echo '[triage-gate] installed to global extensions'; else echo '[triage-gate] already installed, skipping copy'; fi; rm -rf /tmp/jiti; exec node src/server.js"]
