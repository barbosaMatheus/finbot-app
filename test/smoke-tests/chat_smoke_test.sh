#!/usr/bin/env bash
set -euo pipefail

# End-to-end smoke test for POST /chat-prompt
# - starts only the services the chat endpoint needs (db, api) plus Ollama
#   via --profile llm. Leaves the worker and web app out for a faster boot.
# - waits for the API to report healthy
# - logs in as the seeded test user and keeps the session cookie
# - sends a prompt to the chat endpoint
#
# Passes as long as the model returns a response with a 2XX status.

# Chat goes through the API's model seam, so the stack must select a model
# host. The shell value wins over .env for compose interpolation.
export LLM_PROVIDER="${LLM_PROVIDER:-ollama}"
COMPOSE_CMD="docker compose --profile llm"
API_URL="${API_URL:-http://localhost:${API_PORT:-3000}}"
TEST_USER_EMAIL="${TEST_USER_EMAIL:-user@test.com}"
TEST_USER_PASSWORD="${TEST_USER_PASSWORD:-1234qwer}"
COOKIE_JAR="/tmp/finbot-smoke-cookies"
PROMPT_TEXT="What kind of model are you?"

# ANSI colors
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
NC="\033[0m"

cleanup() {
  rm -f "$COOKIE_JAR"
}

wait_for_http() {
  local url="$1"
  local timeout_seconds="${2:-180}"
  local interval=2
  local elapsed=0

  until curl -sS --max-time 2 -o /dev/null "$url"; do
    if [ "$elapsed" -ge "$timeout_seconds" ]; then
      printf "${RED}Timed out waiting for ${url}${NC}\n"
      $COMPOSE_CMD logs api --tail=200
      cleanup
      exit 1
    fi
    sleep $interval
    elapsed=$((elapsed + interval))
  done
}

trap cleanup EXIT

echo "Cleaning up any existing services..."
$COMPOSE_CMD down

echo "Starting db, api, and ollama (build)..."
$COMPOSE_CMD up --build -d db api ollama

echo "Waiting for the API to become healthy at ${API_URL}..."
wait_for_http "${API_URL}/health" 300

printf "${YELLOW}Logging in as ${TEST_USER_EMAIL}...${NC}\n"
login_status=$(curl -sS --max-time 30 -c "$COOKIE_JAR" -o /tmp/finbot-smoke-login.json -w '%{http_code}' \
  -X POST "${API_URL}/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${TEST_USER_EMAIL}\",\"password\":\"${TEST_USER_PASSWORD}\"}")

if [ "$login_status" -lt 200 ] || [ "$login_status" -ge 300 ]; then
  printf "${RED}Login failed with status ${login_status}${NC}\n"
  cat /tmp/finbot-smoke-login.json
  $COMPOSE_CMD logs api --tail=200
  exit 1
fi
printf "${GREEN}Login succeeded (status ${login_status})${NC}\n"

user_id=$(tr -d '\n' < /tmp/finbot-smoke-login.json | grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]+)"/\1/')

if [ -z "$user_id" ]; then
  printf "${RED}Could not extract user id from login response${NC}\n"
  cat /tmp/finbot-smoke-login.json
  $COMPOSE_CMD logs api --tail=200
  exit 1
fi
printf "${GREEN}Got user id ${user_id}${NC}\n"

printf "${YELLOW}Sending prompt to chat endpoint: \"${PROMPT_TEXT}\"${NC}\n"
payload=$(printf '{"userId":"%s","n":3,"userPromptText":"%s"}' "$user_id" "$PROMPT_TEXT")

resp=$(mktemp)
status=$(curl -sS --max-time 120 -b "$COOKIE_JAR" -o "$resp" -w '%{http_code}' \
  -X POST "${API_URL}/chat-prompt" \
  -H 'Content-Type: application/json' \
  -d "$payload")

if [ "$status" -ge 200 ] && [ "$status" -lt 300 ]; then
  printf "${GREEN}Chat smoke test succeeded (status ${status})${NC}\n"
  printf "Model response:\n"
  cat "$resp"
  printf "\n"
  rm -f "$resp"
  exit 0
fi

printf "${RED}Chat request failed with status ${status}${NC}\n"
cat "$resp"
rm -f "$resp"
$COMPOSE_CMD logs api --tail=200
exit 1
