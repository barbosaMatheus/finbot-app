# FinBot

This repository version-controls the Docker Compose **dev environment**. The two
application repos are cloned into it separately and are git-ignored here, so
changes to them are never tracked or pushed from this parent repo.

- **`finbot/`** — the React Native (Expo SDK 56) mobile app, the frontend
  ([barbosaMatheus/finbot](https://github.com/barbosaMatheus/finbot.git)).
- **`finbot-api/`** — an Express + TypeScript backend scaffold
  ([barbosaMatheus/finbot-api](https://github.com/barbosaMatheus/finbot-api.git)).
- **`db`** (Docker) — a Postgres 16 instance the API depends on.

## Running with Docker (development)

The root `docker-compose.yml` runs all three services together with hot reload
for both the API and the Expo web client.

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

### 2. Configure environment

```bash
cp .env.example .env
```

Adjust values if you like; the defaults work out of the box.

### 3. Start everything

```bash
docker compose up --build
```

This builds and starts:

| Service | URL / Port                     | Notes                                        |
| ------- | ------------------------------ | -------------------------------------------- |
| `web`   | http://localhost:8081          | Expo web client with live hot reload         |
| `api`   | http://localhost:3000/health   | Express API; `/health` reports `db` status   |
| `db`    | `localhost:5432`               | Postgres 16 (user/pass/db default `finbot`)  |

Edit files under `finbot/src/` or `finbot-api/src/` and the changes reload
automatically. `GET http://localhost:3000/health` returns `"db": "up"` once the
API can reach Postgres.

### How it works / reliability notes

- Each container installs its **own Linux `node_modules`** into a named volume.
  Your macOS host `node_modules` are never mounted into the containers, which
  avoids native-binary mismatches. Source directories are bind-mounted so edits
  hot-reload.
- The `api` service waits for Postgres to pass its healthcheck
  (`depends_on: condition: service_healthy`) before starting.
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
