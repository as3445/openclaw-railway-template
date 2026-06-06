# Honcho memory layer — deployment runbook

Self-hosted [Honcho](https://github.com/plastic-labs/honcho) as a persistent memory
layer for this OpenClaw deployment, running entirely inside the existing Railway
project. Honcho supplements file-based memory; it does not replace it.

> **Why a runbook and not config-as-code?** Railway's `railway.toml`/`railway.json`
> describes a *single* service (top-level keys are only `build`, `deploy`,
> `environments` — there is no `services` block). Postgres, Redis, and the two
> Honcho services are therefore separate Railway services with no in-repo
> representation. This document is the reproducibility story for that topology.
> (If you ever want it fully in git, the only option is the community Terraform
> provider `terraform-community-providers/railway` — deliberately not used here.)

## Topology

```
Railway project "Nox" (one environment)
├── Nox (this wrapper)   ← existing; entrypoint installs the Honcho plugin at runtime, image bakes QMD
├── honcho-api           ← NEW · plastic-labs/honcho · internal :8000 · runs DB migrations on boot
├── honcho-deriver       ← NEW · plastic-labs/honcho · background worker · no port · no migrations
├── postgres (pgvector)  ← NEW · image service
└── redis                ← NEW · image service
```

All four new services are **internal-only** — do not generate a public domain for
them. Railway does not bill private-network traffic; only public egress. Name them
in **lowercase-with-dashes** so the `.railway.internal` DNS hostname is predictable
(`honcho-api` → `honcho-api.railway.internal`).

---

## Phase 1 — Postgres (pgvector) + Redis

### 1.1 Postgres with pgvector

The **default Railway Postgres image does not include pgvector** and cannot add it
(`CREATE EXTENSION vector` fails). Use a pgvector-enabled image instead:

- **Preferred:** deploy Railway's **pgvector template** from the dashboard
  (Marketplace → search "pgvector"). It ships `pgvector/pgvector` with a volume.
- **Or** add an empty service from the Docker image `pgvector/pgvector:pg16`, attach
  a volume at `/var/lib/postgresql/data`, and set `POSTGRES_PASSWORD` / `POSTGRES_DB`.

> `railway add --database postgres` gives the **standard** Postgres (no pgvector) —
> don't use it for this.

After it's up, enable the extension once:

```bash
railway run -s postgres psql "$DATABASE_URL" -c 'CREATE EXTENSION IF NOT EXISTS vector;'
```

(Honcho auto-runs its own migrations on boot — see Phase 2 — but the `vector`
extension must exist first.)

### 1.2 Redis

```bash
railway add --database redis
```

The default Railway Redis is fine; no extensions needed.

---

## Phase 2 — Honcho API + Deriver

Both services build from the **same** GitHub repo `plastic-labs/honcho` (Railway
auto-detects its root `Dockerfile`). They differ only in start command. Create them
via the dashboard ("New → GitHub Repo → plastic-labs/honcho") or
`railway add` then point the service at the repo.

### 2.1 Start commands (override per service)

| Service | Start command | Notes |
|---|---|---|
| `honcho-api` | `sh docker/entrypoint.sh` | Runs `scripts/provision_db.py` (Alembic migrations) **then** `fastapi run src/main.py`. Do **not** skip the entrypoint or the DB won't be migrated. |
| `honcho-deriver` | `uv run python -m src.deriver` | Background worker. Does **not** run migrations. |

### 2.2 Environment variables (set on **both** services)

Use Railway [reference variables](https://docs.railway.com/reference/variables) to
pull connection details from the DB services. **Two gotchas baked in below:**

1. Honcho wants `DB_CONNECTION_URI` (not `DATABASE_URL`) and the SQLAlchemy/psycopg3
   scheme **`postgresql+psycopg://`** (not `postgresql://`). Construct it from the
   Postgres service's parts rather than referencing `DATABASE_URL` directly:
2. Honcho's cache var is **`CACHE_URL`** (not `REDIS_URL`) and needs
   **`CACHE_ENABLED=true`**.

```bash
# --- database (note the +psycopg scheme and the .railway.internal private host) ---
DB_CONNECTION_URI=postgresql+psycopg://${{postgres.PGUSER}}:${{postgres.POSTGRES_PASSWORD}}@${{postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/${{postgres.POSTGRES_DB}}

# --- cache ---
CACHE_ENABLED=true
CACHE_URL=redis://default:${{redis.REDIS_PASSWORD}}@${{redis.RAILWAY_PRIVATE_DOMAIN}}:6379/0?suppress=true

# --- auth: internal network only, no auth ---
AUTH_USE_AUTH=false

# --- LLM: Honcho's deriver/dialectic/summary default to gpt-5.4-mini; embeddings use
#     text-embedding-3-small. Both are OpenAI, so only this one key is needed.
#     (Keeping the default model = zero model-override env vars.) ---
LLM_OPENAI_API_KEY=<your-openai-key>

LOG_LEVEL=INFO
```

On **`honcho-api` only**, also set:

```bash
PORT=8000
```

> Adjust the `${{postgres...}}` / `${{redis...}}` service names to match what you
> actually named the services. If you used the pgvector template, its variable names
> may differ (e.g. `PGPASSWORD`) — check the service's Variables tab.

### 2.3 IPv6 caveat

If the **"Nox" Railway environment predates 2025-10-16**, internal DNS is IPv6-only
and services must bind to `::`. Honcho's Dockerfile binds `0.0.0.0`, which works on
newer (dual-stack) environments but can fail with connection timeouts on legacy ones.
Check the environment's age before debugging any `ENOTFOUND` / timeout against
`*.railway.internal`.

### 2.4 First-boot note

`honcho-api` runs Alembic migrations on first start (via the entrypoint). Cold builds
from source take a few minutes. Watch the deploy logs for the migration step to
complete before testing.

---

## Phase 3 — Wire the plugin into the gateway

The Honcho plugin is installed **at runtime** by `docker-entrypoint.sh` into the
`/data` volume (same npm prefix as openclaw, alongside `openclaw-plugin-google`), and
the QMD binary is baked into the image. What remains is **configuration of the running
gateway**, applied to the gateway *state* config on the volume
(`/data/.openclaw/openclaw.json`) — **not** the workspace `openclaw.json`, and **not**
the Nox repo (which is a read-only pull mirror).

> **Picking up the plugin on an existing volume.** The entrypoint only runs its
> install step when the openclaw runtime is missing (`if [ ! -f "$ENTRY" ]`). On a
> volume that already has openclaw installed, the new `@honcho-ai/openclaw-honcho`
> won't appear until that triggers. Force it by **bumping `OPENCLAW_VERSION`** (the
> prefix path changes, so it reinstalls and prunes the old version), or by deleting
> `/data/openclaw-runtime/<version>` and redeploying.

Apply config against the live gateway. Two equivalent routes:

- **A — edit the state config file** via a Railway shell on the Nox service, then
  restart the gateway. Simplest for a one-time setup.
- **B — `openclaw gateway call config.patch`** (RPC; needs a `baseHash` from
  `config.get`, rate-limited to 3 writes/60s). Scriptable but fiddlier.

### 3.1 Plugin entry (state config)

```json
{
  "plugins": {
    "allow": ["openclaw-honcho"],
    "entries": {
      "openclaw-honcho": {
        "config": {
          "baseUrl": "http://honcho-api.railway.internal:8000",
          "workspaceId": "openclaw"
        }
      }
    }
  }
}
```

No `apiKey` — `AUTH_USE_AUTH=false` on the server. `baseUrl` uses the internal host
from Phase 2 (match your actual service name).

### 3.2 Keep file-memory alive with QMD

Enabling the Honcho plugin makes it claim OpenClaw's `kind:"memory"` slot, which
evicts the built-in `memory-core`/`memory-lancedb` — the providers that currently
power memory search over `memory/` and `MEMORY.md`. To keep that search working
**alongside** Honcho, set the QMD backend. OpenClaw shells out to the `qmd` binary
(baked into the image) and **auto-registers** the workspace memory files as a
collection — you do **not** run `qmd collection add` yourself.

```json
{
  "memory": {
    "backend": "qmd",
    "qmd": {
      "command": "qmd",
      "includeDefaultMemory": true,
      "update": { "onBoot": true, "interval": "5m" },
      "limits": { "maxResults": 6, "timeoutMs": 4000 }
    }
  }
}
```

`includeDefaultMemory: true` auto-indexes `MEMORY.md` + `memory/**/*.md` relative to
the workspace (`/data/workspace`). If the memory dir is non-standard, add an explicit
path instead:

```json
"paths": [{ "name": "memory", "path": "/data/workspace/memory", "pattern": "**/*.md" }]
```

> **First QMD query downloads ~2GB of GGUF embedding models** (cached under
> `~/.cache/qmd/` on the volume). Expect a slow first search after deploy; subsequent
> ones are fast. The download is lazy (first use), not at boot.

> The existing `agents.defaults.memorySearch` block in the **workspace** config
> configures an embedding provider for the *old* backend and becomes inert under QMD
> (QMD does its own local embeddings). Leave it — it's harmless — unless you want to
> stop the provider call entirely, in which case remove it. It is **not** what keeps
> search alive; `memory.backend: "qmd"` is.

### 3.3 One-time memory migration (optional)

Seed Honcho from existing workspace memory (non-destructive — originals stay):

```bash
openclaw honcho setup
```

### 3.4 Restart

```bash
openclaw gateway restart
```

---

## Phase 4 — Verify

```bash
# Honcho API healthy (from a shell on any service in the project)
curl http://honcho-api.railway.internal:8000/health

# Plugin loaded
openclaw honcho status
```

In a chat session, confirm the agent has **both** tool sets:

- File memory (now served by QMD): `memory_search`, `memory_get`
- Honcho: `honcho_context`, `honcho_search_conclusions`, `honcho_search_messages`,
  `honcho_session`, `honcho_ask`

Send a test message and watch `honcho-api` logs for ingestion activity, and
`honcho-deriver` logs for conclusion extraction.

---

## Cost notes

- The deriver runs an LLM call per conversation turn to extract conclusions. Default
  `gpt-5.4-mini` is cheap for short extractions; monitor OpenAI usage. (Switching to
  `gpt-5.4-nano` would cut that ~4× — set the `*_MODEL_CONFIG__*` overrides if desired.)
- Postgres + Redis on Railway are usage-priced; a small Honcho instance is ~$2–5/mo
  for the DB.

## Gotchas recap

1. **pgvector** — default Railway Postgres can't add it; use the pgvector image/template.
2. **`DB_CONNECTION_URI`**, scheme **`postgresql+psycopg://`** — not `DATABASE_URL`, not `postgresql://`.
3. **`CACHE_URL` + `CACHE_ENABLED=true`** — Honcho has no `REDIS_URL`.
4. **API start command must run migrations** (`sh docker/entrypoint.sh`); deriver must not.
5. **Plugin/memory config goes in the gateway state config on the volume**, applied at
   runtime — not the workspace `openclaw.json`, not the Nox repo (read-only mirror).
   And the plugin **binary** installs at runtime via the entrypoint — bump
   `OPENCLAW_VERSION` to pull it onto an already-installed volume.
6. **QMD keeps file memory searchable** — but it's a backend swap, not an additive
   toggle; first query pulls ~2GB of models.
7. **IPv6** on pre-2025-10-16 environments — bind `::` if internal DNS won't connect.
8. **Internal-only services** — no public domain; cheaper and the secure default.
