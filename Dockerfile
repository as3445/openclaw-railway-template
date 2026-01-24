FROM node:22-bookworm

ENV NODE_ENV=production

# clawdbot includes native deps (e.g. sharp). In some Railway build environments,
# installing from npm may require build tools. Use full bookworm + build-essential.
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    python3 \
    make \
    g++ \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install wrapper deps
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

# Install clawdbot CLI
# Pin if desired: docker build --build-arg CLAWDBOT_VERSION=2026.1.23
ARG CLAWDBOT_VERSION=latest

# Sanity check: git must exist for installs that pull git-based deps.
RUN which git && git --version

RUN npm i -g "clawdbot@${CLAWDBOT_VERSION}" && npm cache clean --force

COPY src ./src

# Railway provides PORT. Wrapper listens on PORT; gateway runs internally.
EXPOSE 3000

CMD ["node", "src/server.js"]
