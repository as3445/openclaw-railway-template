FROM node:22-bookworm-slim

ENV NODE_ENV=production

# clawdbot install pulls some deps via git; Railway build images can be slim.
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install wrapper deps
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

# Install clawdbot CLI
# Pin if desired: docker build --build-arg CLAWDBOT_VERSION=2026.1.23
ARG CLAWDBOT_VERSION=latest
RUN npm i -g "clawdbot@${CLAWDBOT_VERSION}" && npm cache clean --force

COPY src ./src

# Railway provides PORT. Wrapper listens on PORT; gateway runs internally.
EXPOSE 3000

CMD ["node", "src/server.js"]
