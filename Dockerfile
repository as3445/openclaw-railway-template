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

# Stage dhanoosh plugin source (will be copied to volume at startup)
RUN git clone --depth 1 https://github.com/as3445/dhanoosh.git /opt/dhanoosh

WORKDIR /app

# Wrapper deps
RUN npm install -g pnpm
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod --frozen-lockfile && pnpm store prune

COPY src ./src

ENV PORT=8080
EXPOSE 8080

# At startup: copy dhanoosh plugin into the volume-mounted extensions dir,
# then start the server. The extensions dir lives on the persistent volume
# (/data/workspace/.openclaw/extensions/) which isn't available at build time.
CMD ["sh", "-c", "mkdir -p /data/workspace/.openclaw/extensions && rm -rf /data/workspace/.openclaw/extensions/dhanoosh && cp -r /opt/dhanoosh /data/workspace/.openclaw/extensions/dhanoosh && echo '[dhanoosh] installed to extensions dir' && ls /data/workspace/.openclaw/extensions/dhanoosh/; exec node src/server.js"]
