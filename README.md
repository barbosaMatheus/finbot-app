# FinBot

This repository version-controls the Docker Compose **dev environment**. The two
application repos are cloned into it separately and are git-ignored here, so
changes to them are never tracked or pushed from this parent repo.

Canonical cross-repository designs and implementation plans live in
**[docs/](docs/README.md)**.

- **`finbot/`** — the React Native (Expo SDK 56) mobile app, the frontend
  ([barbosaMatheus/finbot](https://github.com/barbosaMatheus/finbot.git)).
- **`finbot-api/`** — an Express + TypeScript backend scaffold
  ([barbosaMatheus/finbot-api](https://github.com/barbosaMatheus/finbot-api.git)).
- **`db`** (Docker) — a Postgres 16 instance the API depends on.

## Running with Docker (development)

The root `docker-compose.yml` runs the database, API, and Expo web client
together with hot reload. Full guide: **[DOCKER.md](DOCKER.md)**.

### 1. Clone the inner app repos

The `finbot/` and `finbot-api/` folders are git-ignored and must be cloned into
this directory. Use the helper script:

```bash
./scripts/clone-apps.sh
```

It clones both repos (and pulls the latest if they already exist). Or clone them
manually:

```bash
git clone https://github.com/barbosaMatheus/finbot-api.git finbot-api
git clone https://github.com/barbosaMatheus/finbot.git finbot
```

### 2. Configure environment (optional)

```bash
cp .env.example .env
```

Compose has a working default for every variable, so this step is only needed to
override something — most commonly your Plaid credentials.

### 3. Start everything

```bash
docker compose up --build
```

This builds and starts:

| Service | URL / Port                     | Notes                                          |
| ------- | ------------------------------ | ---------------------------------------------- |
| `web`   | `localhost:8081`               | Expo web client with live hot reload           |
| `api`   | `localhost:3000/health`        | Express API; `/health` reports `db` status     |
| `db`    | `localhost:5432`               | Postgres 16 + pgvector (defaults `finbot`)     |
| `ollama`| `localhost:11434`              | Opt-in: `docker compose --profile llm up`      |

Edit files under `finbot/src/` or `finbot-api/src/` and the changes reload
automatically. `GET http://localhost:3000/health` returns `"db": "up"` once the
API can reach Postgres.

### How it works / reliability notes

- Each container installs its **own Linux `node_modules`** into a named volume.
  Your host `node_modules` are never mounted into the containers, which avoids
  native-binary mismatches. Source directories are bind-mounted so edits
  hot-reload.
- Startup is ordered by healthchecks: `api` waits for Postgres, and `web` waits
  for the API's `/health` (`depends_on: condition: service_healthy`).
- If you change dependencies (`package.json`), rebuild so the volume picks up
  the new modules:

  ```bash
  docker compose up --build
  # or reset a single service's modules:
  docker compose down -v && docker compose up --build
  ```

- **Metro file watching:** Docker Desktop for macOS usually delivers file
  events fine. If web hot reload ever goes stale, restart just the web service:

  ```bash
  docker compose restart web
  ```

## Native builds (iOS / Android)

Native iOS and Android builds are **not** produced inside Docker:

- iOS builds require macOS + Xcode and cannot run in a Linux container.
- Android builds require a heavy Android SDK/JDK toolchain.

Use **[EAS Build](https://docs.expo.dev/build/introduction/)** (Expo's cloud
build service) for distributable iOS/Android artifacts:

```bash
cd finbot
npx eas-cli build --platform ios       # or android / all
```

Local device/simulator development still works on the host as usual
(`cd finbot && npx expo run:ios` / `run:android`). The Docker setup covers the
web + backend + database development loop.

## Production seam

`docker-compose.prod.yml` is a thin override that selects the `prod` build
targets, drops source bind mounts, and tightens restart policies:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up --build -d
```

It's intentionally a skeleton — before a real deployment you'll want managed
secrets, a reverse proxy + TLS, and a managed/hardened Postgres. The multi-stage
Dockerfiles already expose `build` and `prod` stages so the app isn't married to
a dev-only setup.

**Ollama Service**

- **Opt-in.** Start it with `docker compose --profile llm up`. It is excluded
  from the default stack because pulling a model is a multi-GB download and
  nothing in `finbot-api` calls Ollama yet.
- **Purpose:** A local Ollama runtime to serve a lightweight model (TinyLlama)
  for local testing. Model lifecycle and downloads stay managed by Ollama.
- **Compose file:** See [docker-compose.yml](docker-compose.yml) for the
  `ollama` service entry. It publishes `OLLAMA_PORT` (default `11434`) and
  stores models in a persistent Docker volume named `ollama-data`.
- **API integration:** The `api` service receives an `OLLAMA_URL` environment
  variable, defaulting to `http://ollama:11434`. Nothing reads it yet — the RAG
  embedder in `finbot-api/src/rag/text-embedder.ts` is a local deterministic
  vectorizer. The variable is in place for when that changes.
- **Model selection:** Set `OLLAMA_MODEL` in `.env` (default `tinyllama`).

**Notes / tips**

- If you want the API to target a remote Ollama host instead of the Compose
  service, set `OLLAMA_URL` in your `.env` or override the env when you run
  Compose.
- `11434` collides with a host-installed Ollama. Set `OLLAMA_PORT` to move it.
