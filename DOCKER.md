# Running FinBot with Docker

This repo runs three services via Compose:

| Service | URL | Notes |
| ------- | --- | ----- |
| `web` | http://localhost:8081 | Expo web client |
| `api` | http://localhost:3000 | Express API (`/health` reports DB status) |
| `db` | `localhost:5432` | Postgres 16 + pgvector |

## Prerequisites

- Docker Desktop (or Docker Engine + Compose plugin)
- Git

Port `5432` must be free. If something else is already using it (for example a local Postgres install), stop that process or change `DB_PORT` in `.env`.

```bash
lsof -nP -iTCP:5432 -sTCP:LISTEN
```

## 1. Clone this repo

```bash
git clone <finbot-app-repo-url> finbot-app
cd finbot-app
```

## 2. Clone the app repos

`finbot/` and `finbot-api/` are separate repos and must exist next to `docker-compose.yml`.

```bash
./scripts/clone-apps.sh
```

Or manually:

```bash
git clone https://github.com/barbosaMatheus/finbot-api.git finbot-api
git clone https://github.com/barbosaMatheus/finbot.git finbot
```

## 3. Configure environment

```bash
cp .env.example .env
cp finbot-api/.env.example finbot-api/.env
```

Defaults are fine for local development.

## 4. Start the stack

```bash
docker compose up --build
```

Wait until:

- `db` is healthy
- API logs show it is listening on port `3000`
- Web/Metro is serving on port `8081`

## 5. Open the app

- Frontend: http://localhost:8081
- API health: http://localhost:3000/health

Seeded test user (from `.env`):

- Email: `user@test.com`
- Password: `1234qwer`

## 6. Inspect the database (optional)

```bash
docker compose exec db psql -U finbot -d finbot
```

Useful checks:

```sql
SELECT email, on_boarding_complete, created_at
FROM users
ORDER BY created_at DESC
LIMIT 5;

SELECT full_name, updated_at
FROM user_info
ORDER BY updated_at DESC
LIMIT 5;

SELECT user_id, source, left(context, 120) AS preview, created_at
FROM context_documents
ORDER BY created_at DESC
LIMIT 5;
```

One-liner without entering `psql`:

```bash
docker compose exec db psql -U finbot -d finbot -c "SELECT email, on_boarding_complete FROM users ORDER BY created_at DESC LIMIT 5;"
```

## Everyday commands

Start (no rebuild):

```bash
docker compose up
```

Rebuild after Dockerfile or dependency changes:

```bash
docker compose up --build
```

Restart only the web service:

```bash
docker compose restart web
```

Stop:

```bash
docker compose down
```

Reset containers **and** volumes (wipes DB data and container `node_modules`):

```bash
docker compose down -v
docker compose up --build
```

## Notes

- Edit files under `finbot/src/` or `finbot-api/src/` and they hot-reload in the containers.
- Each service keeps Linux `node_modules` in a named volume so host macOS modules are not used inside Docker.
- The web service must bind Metro on all interfaces (`--host lan`) so http://localhost:8081 works from your machine. That is already configured in `finbot/Dockerfile` and `docker-compose.yml`.
- Native iOS/Android builds are not produced in Docker. Use local Expo/EAS for those.
