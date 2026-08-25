#!/usr/bin/env bash
#
# Clone (or update) the inner app repositories that the Docker Compose
# dev-environment depends on. These repos are git-ignored by the parent repo,
# so each dev pulls them in separately.
#
# Usage:
#   ./scripts/clone-apps.sh
#
set -euo pipefail

# Resolve the repo root (parent of this script's directory) so the script works
# regardless of where it's invoked from.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# app_dir -> git URL
APPS=(
  "finbot-api https://github.com/barbosaMatheus/finbot-api.git"
  "finbot https://github.com/barbosaMatheus/finbot.git"
)

for entry in "${APPS[@]}"; do
  dir="${entry%% *}"
  url="${entry#* }"

  if [ -d "$dir/.git" ]; then
    echo "==> '$dir' already cloned; pulling latest..."
    git -C "$dir" pull --ff-only
  elif [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
    echo "==> '$dir' exists and is not empty but is not a git repo; skipping."
  else
    echo "==> Cloning '$dir' from $url ..."
    git clone "$url" "$dir"
  fi
done

echo "Done. Next: cp .env.example .env && docker compose up --build"
