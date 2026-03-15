#!/bin/bash
set -euo pipefail

REPO_DIR="/Users/reghar/.openclaw/workspace/mission-control"
LOG_DIR="$REPO_DIR/logs"
mkdir -p "$LOG_DIR"

cd "$REPO_DIR"

# Generate fresh snapshot
bash "$REPO_DIR/scripts/generate-snapshot.sh"

# Push if changed
git add data/data.json data/snapshot.json
if ! git diff --cached --quiet; then
  git commit -m "chore: mission control snapshot [$(date -u +%Y-%m-%dT%H:%M:%SZ)]"
  git push
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) — snapshot pushed" >> "$LOG_DIR/snapshot.log"
else
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) — no changes, skipped push" >> "$LOG_DIR/snapshot.log"
fi

# Force Cloudflare Pages deploy (don't rely on GitHub webhook)
/opt/homebrew/bin/wrangler pages deploy "$REPO_DIR" --project-name openclaw-mission-control --branch main --commit-dirty=true >> "$LOG_DIR/snapshot.log" 2>&1 || echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) — wrangler deploy failed" >> "$LOG_DIR/snapshot.log"
