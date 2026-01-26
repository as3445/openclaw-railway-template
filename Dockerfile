# Build clawdbot from source to avoid npm packaging gaps (some dist files are not shipped).
FROM node:22-bookworm AS clawdbot-build

# Dependencies needed for clawdbot build
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    python3 \
    make \
    g++ \
  && rm -rf /var/lib/apt/lists/*

# Install Bun (clawdbot build uses it)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /clawdbot

# Pin to a known ref (tag/branch). If it doesn't exist, fall back to main.
ARG CLAWDBOT_GIT_REF=main
RUN git clone --depth 1 --branch "${CLAWDBOT_GIT_REF}" https://github.com/clawdbot/clawdbot.git .

# Patch: relax version requirements for packages that may reference unpublished versions
RUN find . -name 'package.json' -exec sed -i \
    -e 's/"clawdbot": ">=.*"/"clawdbot": "*"/g' \
    -e 's/"@typescript\/native-preview": "[^"]*"/"@typescript\/native-preview": "latest"/g' \
    {} + 2>/dev/null || true

RUN pnpm install
RUN pnpm build
ENV CLAWDBOT_PREFER_PNPM=1
RUN pnpm ui:install && pnpm ui:build


# Runtime image
FROM node:22-bookworm
ENV NODE_ENV=production

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Wrapper deps
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

# Copy built clawdbot
COPY --from=clawdbot-build /clawdbot /clawdbot

# Provide a clawdbot executable
RUN printf '%s\n' '#!/usr/bin/env bash' 'exec node /clawdbot/dist/entry.js "$@"' > /usr/local/bin/clawdbot \
  && chmod +x /usr/local/bin/clawdbot

COPY src ./src

ENV PORT=8080
EXPOSE 8080
CMD ["node", "src/server.js"]
