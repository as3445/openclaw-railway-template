# Clawdbot Railway Template (1‑click deploy)

This repo packages **Clawdbot** for Railway with a small **/setup** web wizard so users can deploy and onboard **without running any commands**.

## What you get

- **Clawdbot Gateway + Control UI** (served at `/` and `/clawdbot`)
- A friendly **Setup Wizard** at `/setup` (protected by a password)
- Persistent state via **Railway Volume** (so config/credentials/memory survive redeploys)
- One-click **Export backup** (so users can migrate off Railway later)

## How it works (high level)

- The container runs a wrapper web server.
- The wrapper protects `/setup` with `SETUP_PASSWORD`.
- During setup, the wrapper runs `clawdbot onboard --non-interactive ...` inside the container, writes state to the volume, and then starts the gateway.
- After setup, **`/` is Clawdbot**. The wrapper reverse-proxies all traffic (including WebSockets) to the local gateway process.

## Railway deploy instructions (what you’ll publish as a Template)

In Railway Template Composer:

1) Create a new template from this GitHub repo.
2) Add a **Volume** mounted at `/data`.
3) Set the following variables:

Required:
- `SETUP_PASSWORD` — user-provided password to access `/setup`

Recommended:
- `CLAWDBOT_STATE_DIR=/data/.clawdbot`
- `CLAWDBOT_WORKSPACE_DIR=/data/workspace`

Optional:
- `CLAWDBOT_GATEWAY_TOKEN` — if not set, the wrapper generates one (not ideal). In a template, set it using a generated secret.
- `CLAWDBOT_VERSION` — if you pin via Docker build arg.

4) Enable **Public Networking** (HTTP). Railway will assign a domain.
5) Deploy.

Then:
- Visit `https://<your-app>.up.railway.app/setup`
- Complete setup
- Visit `https://<your-app>.up.railway.app/` and `/clawdbot`

## Local smoke test

```bash
docker build -t clawdbot-railway-template .

docker run --rm -p 8080:8080 \
  -e PORT=8080 \
  -e SETUP_PASSWORD=test \
  -e CLAWDBOT_STATE_DIR=/data/.clawdbot \
  -e CLAWDBOT_WORKSPACE_DIR=/data/workspace \
  -v $(pwd)/.tmpdata:/data \
  clawdbot-railway-template

# open http://localhost:8080/setup (password: test)
```
