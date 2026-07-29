#!/usr/bin/env bash
set -euo pipefail

# Simple smoke test for Ollama in docker-compose
# - starts compose (build)
# - waits for Ollama to accept connections on localhost:11434
# - attempts a sample generation via REST endpoint

COMPOSE_CMD="docker compose"
CONTAINER_NAME="finbot-app-ollama-1"

# ANSI colors
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
NC="\033[0m"

echo "Starting docker compose (build)..."
$COMPOSE_CMD up --build -d

echo "Waiting for Ollama to accept connections on http://localhost:11434 ..."
timeout_seconds=180
interval=2
elapsed=0
until curl -sS --max-time 2 http://localhost:11434/ >/dev/null 2>&1; do
  if [ "$elapsed" -ge "$timeout_seconds" ]; then
    printf "${RED}Timed out waiting for Ollama on port 11434${NC}\n"
    $COMPOSE_CMD logs $CONTAINER_NAME --tail=200
    exit 1
  fi
  sleep $interval
  elapsed=$((elapsed + interval))
done
printf "${GREEN}Connection accepted on port 11434${NC}\n"

printf "${YELLOW}Sending sample prompt to generation endpoint...${NC}\n"
payload='{"model":"tinyllama","prompt":"I am running a smoke test for Ollama in docker-compose"}'
echo "POST http://localhost:11434/api/generate"
resp=$(curl -sS -X POST "http://localhost:11434/api/generate" -H "Content-Type: application/json" -d "$payload" || true)
if [ -n "$resp" ]; then
  printf "${GREEN}Received response from /api/generate:${NC}\n"
  echo "$resp" | sed -n '1,200p'
  printf "${GREEN}Smoke test succeeded (HTTP).${NC}\n"
  $COMPOSE_CMD down
  exit 0
fi

printf "${RED}Generation failed (no HTTP response). Dumping logs...${NC}\n"
$COMPOSE_CMD logs ollama --tail=200
$COMPOSE_CMD down
exit 1
