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

# Install plugins
RUN openclaw plugins install as3445/dhanoosh \
  && openclaw plugins install elevenlabs \
  && openclaw plugins install firecrawl \
  && openclaw plugins install openrouter \
  && openclaw plugins install openai \
  && openclaw plugins install diffs \
  && openclaw plugins install memory-core \
  && openclaw plugins install brave

WORKDIR /app

# Wrapper deps
RUN npm install -g pnpm
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod --frozen-lockfile && pnpm store prune

COPY src ./src

ENV PORT=8080
EXPOSE 8080
CMD ["node", "src/server.js"]
