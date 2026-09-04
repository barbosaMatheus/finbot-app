# Financial analysis runtime — local operations guide (INFRA-002)

How to run, exercise, and debug the financial onboarding pipeline locally.
The canonical design is
[financial-onboarding-and-transaction-analysis.md](./financial-onboarding-and-transaction-analysis.md).

## Services

`docker compose up --build` starts:

| Service  | What it does |
| --- | --- |
| `db` | Postgres 16 + pgvector. Also hosts the `pgboss` queue schema. |
| `api` | Express API. Validates, persists, enqueues; never does long work in a request. |
| `worker` | Same image, `npm run worker`. Owns Plaid sync and the analysis pipeline. |
| `web` | Expo dev server. |

The worker and API both run migrations at startup (idempotent, transactional),
so either may boot first. Stop processing without losing queued jobs by
stopping just the worker: `docker compose stop worker`.

## The pipeline at a glance

```
link → exchange → INITIALIZE_ITEM_SYNC → SYNC_ITEM_TRANSACTIONS (per Item)
     → all Items terminal → CLASSIFY → RECONCILE → RECURRING → FACTS → REVIEW
     → review_ready → (delayed?) SEND_REVIEW_READY_NOTIFICATION
```

Job queue is pg-boss in Postgres (`PGBOSS_SCHEMA`, default `pgboss`). Retries
use bounded exponential backoff; exhausted jobs land on the `DEAD_LETTER`
queue and surface as failed Items/runs with a user-visible retry action.

## Webhooks locally

Plaid cannot reach `localhost`. Two options:

1. **Do nothing.** The worker polls `/transactions/sync` every
   `PLAID_SYNC_POLL_SECONDS` until Plaid reports
   `HISTORICAL_UPDATE_COMPLETE` (or the `PLAID_SYNC_POLL_TIMEOUT_SECONDS`
   window lapses, which completes the Item with the history it has —
   surfaced as limited-history coverage). Sandbox usually completes within
   seconds, so local development is fully functional without webhooks.
2. **Tunnel.** `ngrok http 3000`, then include
   `https://<tunnel>/plaid/webhook` as the `webhook` in link-token creation
   (or set it on the Item in the dashboard). Signature verification is on by
   default; every delivery must carry a valid `Plaid-Verification` JWT.
   `PLAID_WEBHOOK_VERIFY=false` is only for simulating deliveries by hand.

Sandbox webhook simulation:
`POST /sandbox/item/fire_webhook` with the Item's access token fires
`SYNC_UPDATES_AVAILABLE` at the registered URL.

## Sandbox test flow

1. Set real Sandbox credentials in `.env` (`PLAID_CLIENT_ID`, `PLAID_SECRET`).
2. Register/login in the app, connect an institution in Link
   (`user_good` / `pass_good`; pick an institution with checking + credit
   card to exercise reconciliation).
3. Optionally connect a second institution, then declare linking complete
   (`POST /onboarding/linking-complete`).
4. Watch the worker logs: sync commits, classification, links, streams,
   review build, and `review_ready`.
5. `GET /onboarding/status` drives the client; `GET
   /onboarding/financial-review` returns the snapshot.

## Push notifications

- The client registers Expo push tokens at `POST /notifications/push-tokens`.
- The worker sends via Expo's public push HTTP API — no server credential in
  the default setup. If your Expo project enables enhanced push security,
  supply `EXPO_ACCESS_TOKEN` and add the Authorization header in
  `finbot-api/src/services/push.service.ts` before deploying.
- A push is sent only when the review became ready later than
  `ANALYSIS_EXPECTED_WINDOW_SECONDS` after the run started, once per
  run/device (enforced by a unique send ledger).
- Web builds receive no push; the web app polls.

## Operator actions

- **Inspect queue state:** tables live in the `pgboss` schema; per-queue
  counts in `pgboss.queue`.
- **Replay after an incident:** jobs are idempotent references — re-enqueue
  by inserting through the API's supported entrypoints
  (`POST /onboarding/retry` per user) rather than editing business tables.
- **Dead letters:** rows remain on the `DEAD_LETTER` queue for redrive
  (`boss.redrive('DEAD_LETTER', ...)`); the dead-letter observer has already
  marked the affected Item/run failed so users see a retry action.
- **Disable analysis intake:** stop the worker; API enqueueing continues and
  jobs wait in Postgres.

## Production seams and known platform limitations

- Webhook URL, CORS origin, cookie security, JWT secrets, and the Plaid
  token encryption key all must be real values outside a laptop.
- The Expo push sender needs the enhanced-security access token if enabled.
- OAuth institutions require `PLAID_REDIRECT_URI` (registered in the Plaid
  dashboard) and, on Android, `PLAID_ANDROID_PACKAGE_NAME`.
- Hosted Link (web) needs `PLAID_HOSTED_LINK_REDIRECT_URI` to return the
  browser to the app.
- `docker-compose.prod.yml` predates the worker; production deployment needs
  a worker process (same image, `node dist/worker.js`) added when that path
  is next touched.
