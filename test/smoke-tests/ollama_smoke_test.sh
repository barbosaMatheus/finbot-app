#!/usr/bin/env bash
set -euo pipefail

# Simple smoke test for Ollama in docker-compose
# - starts only the ollama service (it lives behind the "llm" profile)
# - waits for Ollama to accept connections
# - attempts a sample generation via REST endpoint
#
# Only tears down what it started, so it will not stop a dev stack you already
# have running.

COMPOSE_CMD="docker compose --profile llm"
SERVICE="ollama"
MODEL="${OLLAMA_MODEL:-tinyllama}"
PORT="${OLLAMA_PORT:-11434}"
BASE_URL="http://localhost:${PORT}"

# ANSI colors
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
NC="\033[0m"

cleanup() {
  $COMPOSE_CMD stop "$SERVICE" >/dev/null 2>&1 || true
  $COMPOSE_CMD rm -f "$SERVICE" >/dev/null 2>&1 || true
}

echo "Starting the '$SERVICE' service (build)..."
$COMPOSE_CMD up --build -d "$SERVICE"

echo "Waiting for Ollama to accept connections on ${BASE_URL} ..."
timeout_seconds=300
interval=2
elapsed=0
until curl -sS --max-time 2 "$BASE_URL/" >/dev/null 2>&1; do
  if [ "$elapsed" -ge "$timeout_seconds" ]; then
    printf "${RED}Timed out waiting for Ollama on port ${PORT}${NC}\n"
    $COMPOSE_CMD logs "$SERVICE" --tail=200
    cleanup
    exit 1
  fi
  sleep $interval
  elapsed=$((elapsed + interval))
done
printf "${GREEN}Connection accepted on port ${PORT}${NC}\n"

# Accepting connections is not the same as having the model. The entrypoint
# pulls it on first boot, which can take a while on a cold volume.
printf "${YELLOW}Waiting for the '${MODEL}' model to finish pulling...${NC}\n"
elapsed=0
until $COMPOSE_CMD exec -T "$SERVICE" ollama list 2>/dev/null | grep -q "$MODEL"; do
  if [ "$elapsed" -ge "$timeout_seconds" ]; then
    printf "${RED}Timed out waiting for the '${MODEL}' model${NC}\n"
    $COMPOSE_CMD logs "$SERVICE" --tail=200
    cleanup
    exit 1
  fi
  sleep $interval
  elapsed=$((elapsed + interval))
done
printf "${GREEN}Model '${MODEL}' is available${NC}\n"

printf "${YELLOW}Sending sample prompt to generation endpoint...${NC}\n"
payload="{\"model\":\"${MODEL}\",\"prompt\":\"I am running a smoke test for Ollama in docker-compose\",\"stream\":false}"
echo "POST ${BASE_URL}/api/generate"
resp=$(curl -sS -X POST "${BASE_URL}/api/generate" -H "Content-Type: application/json" -d "$payload" || true)
if [ -n "$resp" ]; then
  printf "${GREEN}Received response from /api/generate:${NC}\n"
  echo "$resp" | sed -n '1,200p'
  printf "${GREEN}Smoke test succeeded (HTTP).${NC}\n"
  cleanup
  exit 0
fi

printf "${RED}Generation failed (no HTTP response). Dumping logs...${NC}\n"
$COMPOSE_CMD logs "$SERVICE" --tail=200
cleanup
exit 1
