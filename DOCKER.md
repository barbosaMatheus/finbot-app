# Running FinBot with Docker

## Quick start

```bash
git clone <finbot-app-repo-url> finbot-app
cd finbot-app
./scripts/clone-apps.sh          # Windows: see "Cloning on Windows" below
docker compose up --build
```

That's it — no `.env` needed. Open http://localhost:8081.

Compose ships working defaults for every variable, so a fresh clone comes up as
long as the two inner app repos exist. You only need a `.env` to override
something, and the main reason to is Plaid credentials (see
[Connecting a bank](#connecting-a-bank)).

## Services

| Service | URL | Notes |
| ------- | --- | ----- |
| `web` | http://localhost:8081 | Expo web client (Metro, hot reload) |
| `api` | http://localhost:3000 | Express API — `/health` reports DB status |
| `db` | `localhost:5432` | Postgres 16 + pgvector |
| `ollama` | http://localhost:11434 | **Opt-in**, see [Ollama](#ollama-optional) |

`ollama` does not start by default: pulling a model is a multi-GB download and
nothing in `finbot-api` calls it yet.

## Prerequisites

- Docker Desktop (or Docker Engine + Compose v2.24 or newer)
- Git

Ports `8081`, `3000`, and `5432` must be free. If a local Postgres already owns
5432, either stop it or set `DB_PORT` in `.env`.

```bash
# macOS / Linux
lsof -nP -iTCP:5432 -sTCP:LISTEN

# Windows (PowerShell)
Get-NetTCPConnection -LocalPort 5432 -State Listen
```

## 1. Clone the app repos

`finbot/` and `finbot-api/` are separate repositories and are git-ignored here.
They must exist next to `docker-compose.yml` before Compose can build.

```bash
./scripts/clone-apps.sh
```

Or manually:

```bash
git clone https://github.com/barbosaMatheus/finbot-api.git finbot-api
git clone https://github.com/barbosaMatheus/finbot.git finbot
```

### Cloning on Windows

`scripts/clone-apps.sh` is a bash script. Run it from Git Bash or WSL, or just
run the two `git clone` commands above in PowerShell.

## 2. Configure environment (optional)

```bash
cp .env.example .env
```

Skip this and the defaults in `docker-compose.yml` apply. `.env.example` documents
every variable and which ones matter. Set your Plaid keys here when you want the
bank connection flow to work.

> `finbot-api/.env` is a *separate* file, used only when you run the API directly
> on your machine (`cd finbot-api && npm run dev`). Compose does not read it. See
> `finbot-api/.env.example`.

## 3. Start the stack

```bash
docker compose up --build
```

Startup order is enforced by healthchecks: `db` becomes healthy, then `api`
starts and runs its migrations, then `web` boots once `/health` responds.

## 4. Open the app

- Frontend: http://localhost:8081
- API health: http://localhost:3000/health

Seeded test user:

- Email: `user@test.com`
- Password: `1234qwer`

## Connecting a bank

The Plaid flow needs credentials. Put your Sandbox keys in `.env`:

```env
PLAID_CLIENT_ID=...
PLAID_SECRET=...
PLAID_ENV=sandbox
```

Then `docker compose up -d --force-recreate api`.

In Plaid Sandbox, log in with username `user_good` and password `pass_good`.

**How it behaves per platform:**

| Platform | Flow |
| -------- | ---- |
| Docker web (localhost:8081) | Plaid **Hosted Link** opens in a new browser tab; the app polls until you finish. Allow pop-ups. |
| iOS / Android dev build | The native Plaid Link SDK, presented in-app. |
| Expo Go | **Not supported** — Plaid Link ships custom native code. |

Plaid Link's native module has no web implementation, which is why the web
target uses Hosted Link instead. Both paths land on the same API endpoints and
store the same data.

To exercise the native path:

```bash
cd finbot
cp .env.example .env      # set EXPO_PUBLIC_API_BASE_URL to your machine's LAN IP
npx expo run:ios          # or run:android
```

A physical device cannot reach `http://localhost:3000` — that resolves to the
phone. Use your machine's LAN IP.

## Inspect the database

```bash
docker compose exec db psql -U finbot -d finbot
```

Leave psql with `\q`.

> Every `docker compose` command on this page must be run from the `finbot-app`
> directory — that is where `docker-compose.yml` lives. Running one from
> anywhere else fails with `no configuration file provided: not found`. To reach
> the database from any directory, address the container directly instead:
> `docker exec -it finbot-app-db-1 psql -U finbot -d finbot`

Useful checks:

```sql
SELECT email, on_boarding_complete, created_at
FROM users
ORDER BY created_at DESC
LIMIT 5;

SELECT institution_name, status, created_at
FROM plaid_items
ORDER BY created_at DESC;

SELECT name, mask, type, current_balance
FROM plaid_accounts
ORDER BY name;
```

One-liner without entering `psql`:

```bash
docker compose exec db psql -U finbot -d finbot -c "SELECT email, on_boarding_complete FROM users ORDER BY created_at DESC LIMIT 5;"
```

Plaid access tokens in `plaid_items.access_token_encrypted` are AES-256-GCM
ciphertext, not readable from a dump.

## Everyday commands

```bash
docker compose up                  # start (no rebuild)
docker compose up --build          # rebuild after Dockerfile / dependency changes
docker compose restart web         # restart one service
docker compose logs -f api         # follow one service's logs
docker compose down                # stop
```

**One-shot clean rebuild (Windows)** — `scripts\rebuild.cmd` (or `.\scripts\rebuild.ps1`) stops the project, drops the `node_modules` volumes, removes the images compose built and rebuilds them with `--no-cache`, then starts the stack again. Data is kept; `-WipeData` also drops the database and Ollama volumes, `-WithLlm` includes Ollama, `-NoStart` leaves the stack down, `-DryRun` prints the commands without running them.

Reset containers **and** volumes — wipes DB data and the container
`node_modules`:

```bash
docker compose down -v
docker compose up --build
```

`down -v` also deletes `ollama-data`, forcing a full model re-download. To keep
it, remove the other volumes by name instead:

```bash
docker compose down
docker volume rm finbot-app_db-data finbot-app_api-node-modules finbot-app_web-node-modules
```

## Ollama (optional)

```bash
docker compose --profile llm up
```

Pulls `tinyllama` on first start into the `ollama-data` volume. Override with
`OLLAMA_MODEL` and `OLLAMA_PORT` in `.env` — `11434` collides with a
host-installed Ollama, which is common.

`OLLAMA_URL` is passed to the API but nothing reads it yet; the RAG embedder in
`finbot-api/src/rag/text-embedder.ts` is a local deterministic vectorizer.

## Troubleshooting

**`env file .env not found`** — you're on Compose older than v2.24. Either
upgrade, or `cp .env.example .env`.

**Login returns 500** — `JWT_ACCESS_SECRET` / `JWT_REFRESH_SECRET` are missing.
Compose defaults them, so this means a `.env` is overriding them with blanks.

**`invalid client_id or secret provided`** — Plaid issues a *separate secret per
environment*. A Production secret returns this against Sandbox and vice versa.
The dashboard shows all of them under
[Developers → Keys](https://dashboard.plaid.com/developers/keys); make sure
`PLAID_SECRET` is the one matching your `PLAID_ENV`.

**Web loads but hot reload never fires** — Metro advertises the hostname in
`REACT_NATIVE_PACKAGER_HOSTNAME` (default `localhost`) to the browser for its
websocket. If you changed it to a LAN IP for device testing, browser HMR breaks;
change it back for browser work.

**Changed `API_PORT` and the app can't reach the API** — the client URL follows
`API_PORT` automatically, but the bundle only picks it up on restart:
`docker compose up -d --force-recreate web`.

**File edits don't reload (Windows)** — bind-mount file events can be dropped
outside WSL2. Keeping the repo inside the WSL2 filesystem is the reliable fix;
`docker compose restart web` clears a one-off stall.

**`.expo/`, `dist/`, root-owned files appearing in your source tree** — expected.
The containers run as root against the bind mount and write build artifacts
there. They are git-ignored.

## Notes

- Edit files under `finbot/src/` or `finbot-api/src/` and they hot-reload.
- Each service keeps its Linux `node_modules` in a named volume so host modules
  are never used inside the containers. Change `package.json` → rebuild.
- Migrations are plain `.sql` in `finbot-api/src/db/migrations/`, applied on API
  startup and tracked in the `schema_migrations` table.
- Native iOS/Android builds are not produced in Docker. Use local Expo
  (`npx expo run:ios`) or EAS Build.

## Production seam

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up --build -d
```

Selects the `prod` build targets, drops the source bind mounts, and tightens
restart policies. It is a skeleton — a real deployment still needs managed
secrets (not a committed `.env`), a reverse proxy with TLS, and a managed or
hardened Postgres. Set `PLAID_TOKEN_ENC_KEY`, `JWT_ACCESS_SECRET`, and
`JWT_REFRESH_SECRET` to real generated values; the dev defaults are public.
