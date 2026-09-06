# Testing FinBot against a real model

A step-by-step run for one person, start to finish. It takes about two
hours of your attention plus model time. You will need Docker Desktop, the
three repositories, Plaid Sandbox keys, and one of the model hosts in step 2.

## What you are testing, in one minute

FinBot's gameplan engine computes every number a user sees: the targets, the
caps, the free cash, the grade. A language model never computes anything. It
only writes the sentences around those numbers — the plan explanation, the
"why" line under each target, the grade narration, the reply to a heads-up —
and it reads the heads-up line the user typed to find an amount in it.

Every sentence the model writes is checked before it is shown: if it contains
a number that is not in the data it was given, the sentence is thrown away, a
fixed template sentence is shown instead, and the reason is recorded. That
check is the **containment check**. The share of model replies that had to be
thrown away for inventing a number is the **fabricated-number rate**, and the
target is zero.

`LLM_PROVIDER` in `.env` selects what writes the sentences:

| Value | What happens |
| --- | --- |
| `template` (default) | No model is ever called. Every sentence is a fixed template with the engine's numbers filled in. |
| `ollama` | An Ollama server, in Docker or on your machine. Free. |
| `anthropic` | The Anthropic API. Fast, costs money, needs a key. |

Two things to find out:

1. **The fabricated-number rate** against a real model (step 4, the harness).
2. **Whether the screens behave with a model on** — above all the heads-up
   amount box, which no one has seen live yet (step 5).

Chat is not part of this test; it still answers from canned replies.

## 1. Get the code

The model work lives on the `feature/gameplan-engine` branch of all three
repositories until the pull requests (finbot-api #21, finbot #24,
finbot-app #7) are merged. After the merge, `main` is right.

```bash
git clone https://github.com/barbosaMatheus/finbot-app.git   # skip if you have it
cd finbot-app
git checkout feature/gameplan-engine && git pull
scripts/clone-apps.sh          # first time only: clones finbot/ and finbot-api/
(cd finbot     && git fetch && git checkout feature/gameplan-engine && git pull)
(cd finbot-api && git fetch && git checkout feature/gameplan-engine && git pull)
```

If you have no `.env` yet: `cp .env.example .env` and put your Plaid Sandbox
keys in it (`PLAID_CLIENT_ID`, `PLAID_SECRET`). The harness in step 4 does not
need Plaid; the app walk in step 5 does.

## 2. Pick a model host

Pick one. **B is the one to use if your machine has a GPU or Apple silicon.**

### A. Ollama inside Docker (simplest, slow)

Docker Desktop gives the container no GPU, so the model runs on the CPU. A
harness run of 18 calls takes ten to thirty minutes. Fine for a first run.

In `.env`:

```env
LLM_PROVIDER=ollama
OLLAMA_MODEL=llama3.1
LLM_TIMEOUT_MS=300000
```

`llama3.1` is about 5 GB and is the model we measure against. The compose
default, `tinyllama`, is fast and produces mostly unusable output — do not
report numbers from it.

### B. Ollama installed on your machine (fast)

Install from [ollama.com](https://ollama.com), then:

```bash
ollama pull llama3.1
ollama list          # llama3.1 must be listed
```

In `.env`:

```env
LLM_PROVIDER=ollama
OLLAMA_MODEL=llama3.1
OLLAMA_URL=http://host.docker.internal:11434
LLM_TIMEOUT_MS=60000
```

Do **not** use `--profile llm` in the compose commands below; the containers
talk to the Ollama on your machine. On Linux, `host.docker.internal` is not
defined by default: add `extra_hosts: ["host.docker.internal:host-gateway"]`
to the `api` and `worker` services, and start Ollama with
`OLLAMA_HOST=0.0.0.0`.

### C. Anthropic API (fast, paid)

In `.env`:

```env
LLM_PROVIDER=anthropic
ANTHROPIC_API_KEY=sk-ant-...
LLM_TIMEOUT_MS=60000
```

The model defaults to `claude-opus-5` at low effort (`ANTHROPIC_MODEL`,
`ANTHROPIC_EFFORT` override). Every call is billed; a harness run is 18 calls.

## 3. Start the stack

**Fresh clone** (the containers have never run on this machine):

```bash
docker compose --profile llm up --build -d     # option A
docker compose up --build -d                   # option B or C
```

**You already had the stack running from `main`** — two things changed on
this branch that a plain restart does not pick up: a new dependency
(`@anthropic-ai/sdk`) that the container's `node_modules` volume does not
have, and two database migrations (015, 016) plus many new files that the
file watcher does not see.

```bash
docker compose exec api npm install
docker compose restart api worker
docker compose --profile llm up -d             # option A only: starts Ollama
```

On Windows, `scripts\rebuild.cmd -WithLlm` does the whole teardown and
no-cache rebuild in one go (`-DryRun` prints what it would run).

**Option A only** — the Ollama container pulls `OLLAMA_MODEL` on first start.
Wait for it:

```bash
docker compose logs -f ollama          # Ctrl+C once the pull reports success
docker compose exec ollama ollama list # llama3.1 listed = ready
```

Health check for everyone:

```bash
docker compose ps                      # api, worker, db, web (and ollama) up
docker compose logs api --tail 20      # migrations applied, listening on 3000
```

## 4. Run the harness

```bash
docker compose exec api npm run eval:gameplan
```

Run it inside the `api` container as shown; it inherits the model settings
and the database address from compose. Expect ten to thirty minutes on the
CPU, about a minute otherwise.

What it does: six pinned users go through the engine, and the run **fails
if any number drifts** from what is pinned (that part never touches a
model). Then, for each user, the plan explanation, a grade and a heads-up
reply are written by the configured model — 18 calls — and each is checked
for invented numbers.

What you see, in order:

1. A header: `gameplan eval · provider: ollama · scenarios: 6` (or
   `anthropic`). If it says `template`, `.env` was not picked up: check
   `LLM_PROVIDER` and re-run `docker compose up -d`.
2. Six lines, one per user, `✓` or `✗`. Any `✗` is a regression in the
   numbers and is the first thing to report.
3. A table with one row per model call:

   | Column | Meaning |
   | --- | --- |
   | `scenario` | which pinned user |
   | `call` | `plan`, `grade` or `diff` (the heads-up reply) |
   | `source` | `model` if the model's sentence was used, `template` if it was thrown away |
   | `fallback` | why it was thrown away: `client_error` (the host did not answer — timeout, wrong model name, wrong URL), `malformed` (the reply was not the JSON shape asked for), `number_invented` (the containment check fired), `no_provider` (no model configured) |
   | `invented` | the numbers the raw model text contained that were not in its input |

4. Two summary lines: how many calls the model answered, and
   `fabricated-number rate: X/N = P%`.
5. `regression: green` or a failure count. The command exits non-zero on a
   failure.

Run it **twice**. Models are not fully deterministic even at temperature 0,
and two runs tell us whether a fabricated number is a fluke.

Copy the complete output of both runs into your report.

## 5. Walk the app with the model on

Everything below is in the browser at <http://localhost:8081>. Plaid Sandbox
keys must be in `.env`.

1. **Sign up** with an email you have not used on this database, or log in
   as the seeded user (`user@test.com` / `1234qwer` unless your `.env` says
   otherwise).
2. **Onboarding.** Connect a bank: Plaid Hosted Link opens in a new tab
   (allow pop-ups) → search *First Platypus Bank* → `user_good` /
   `pass_good` → pick any accounts → finish → back in the app, declare
   linking done. Wait for the analysis (a minute or two).
3. **Review and confirm.** Accept or answer the review items, confirm.
   Confirming opens the first gameplan period and queues the plan build.
   Sandbox data has no usable income stream, so the period is a fixed
   weekly one; that is expected.
4. **Wait for the plan.** The worker builds it and calls the model for the
   plan narration and the why lines. Watch it:

   ```bash
   docker compose logs -f worker
   ```

   On the CPU this is minutes. Home shows the plan when it is done; the
   anchor screen says "No plan yet" with a "Check again" button until then.
5. **Home and anchor.** Home shows three targets. Open the anchor from the
   plan card. Each target has a why line. Read them against the numbers on
   the card: a why line must never name a figure that is not on screen.
6. **Heads-up, with an amount.** Under "Anything I should know this
   period?" type exactly:

   > car repair, about $300

   and press **Tell FinBot**. Expected: the amount box opens **pre-filled
   with 300** with a **Confirm** button. Press Confirm. Expected: one
   target's amount shrinks to make room, and the reply sentence says so.
   Note the amount before and after.
7. **Heads-up, without an amount.** Press **Add another** and type:

   > car trouble

   Expected: the box opens **empty**, with ballpark amount chips, and a
   **Skip** button. Press Skip. Expected: nothing on the plan changes and
   the reply says as much (it is kept as context for the plan).
8. **Got it** closes the anchor and marks the period acknowledged.
9. **Swap.** Back on the anchor, use the swap control on a target: the
   alternate replaces it and the control disappears.
10. **Settings** (from the anchor): change the anchor day and time of day,
    save, reopen — the choice is still there.

The grade narration is not reachable in a short walk (grades happen when a
period closes); the harness covers it.

For every step, write down what you saw, in one line, and take a screenshot
of anything that looks wrong. The most important thing you can catch is a
sentence that contradicts the numbers next to it.

## 6. Check where each sentence came from

The database records, for every sentence, whether the model or the template
wrote it. From the compose directory:

```bash
docker compose exec db psql -U finbot -d finbot
```

```sql
-- the plan narration per period (newest first)
SELECT plan_source, plan_fallback_reason, plan_model, created_at
FROM gameplan_periods ORDER BY created_at DESC LIMIT 5;

-- the why lines
SELECT why_source, count(*) FROM gameplan_targets GROUP BY 1;

-- heads-up replies
SELECT reply_source, count(*) FROM plan_revisions GROUP BY 1;

-- grades (empty until a period closes)
SELECT narration_source, narration_fallback_reason, count(*)
FROM period_grades GROUP BY 1, 2;
```

Leave psql with `\q`. The same summary per user, without SQL:

```bash
docker compose exec api npm run eval:gameplan -- --traffic
```

(It re-runs the harness first, then prints the "real traffic" table.)

Every fallback is also a warning in the logs:

```bash
docker compose logs api worker | grep "llm"
```

## 7. What to send back

- The complete harness output, both runs, and: model name, which host
  option (A, B or C), your machine (CPU or GPU).
- The walk (step 5) as a numbered list: pass, or what you saw instead, with
  screenshots.
- Any sentence — why line, reply, plan narration — that names a number not
  on the screen next to it. The containment check should have caught it,
  so if one reached the screen, that is the top finding.
- The results of the four queries in step 6.
- Anything that felt slow, and where.

## 8. Going back to plain sentences

```env
LLM_PROVIDER=template
```

then `docker compose up -d`. Templates are instant and never call a model.

## When something is off

- **`client_error` on every row.** The host did not answer in time or at
  all. Option A: `LLM_TIMEOUT_MS=300000`, and `docker compose exec ollama
  ollama list` must show the model. Option B: `curl
  http://localhost:11434/api/tags` from your machine must answer; if it
  does but the container fails, Ollama is bound to localhost only — set
  `OLLAMA_HOST=0.0.0.0` for the Ollama app and restart it. Option C: the
  key is wrong or has no credit.
- **`malformed` on many rows.** The model is not returning the requested
  JSON shape. Small models do this; report the model name and try
  `llama3.1` or larger.
- **`number_invented`.** This is the result we are after. Report the
  scenario, the call, and the invented numbers exactly as printed.
- **Port 11434 is taken** when starting option A: an Ollama on your machine
  owns it. Either switch to option B, or set `OLLAMA_PORT=11435` in `.env`.
- **The plan never appears** after confirming. `docker compose logs worker`
  — if it shows a model timeout, raise `LLM_TIMEOUT_MS` and `docker compose
  up -d`; if it shows a missing table, the migrations did not run —
  `docker compose restart api worker`.
- **The amount box never opens, even for "$300".** The parse call to the
  model failed; `docker compose logs api | grep llm` shows why. With
  `LLM_PROVIDER=template` it never opens, by design.
- **`provider: template` in the harness header** although `.env` says
  `ollama`. The containers were not recreated after the `.env` change:
  `docker compose up -d` (with `--profile llm` for option A).
