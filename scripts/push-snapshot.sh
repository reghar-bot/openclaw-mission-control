#!/bin/bash
set -euo pipefail

REPO_DIR="/Users/reghar/.openclaw/workspace/mission-control"
LOG_DIR="$REPO_DIR/logs"
mkdir -p "$LOG_DIR"

cd "$REPO_DIR"

# Generate fresh snapshot
bash "$REPO_DIR/scripts/generate-snapshot.sh"

# Push if changed
git add data/snapshot.json
if ! git diff --cached --quiet; then
  git commit -m "snapshot $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  git push
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) — snapshot pushed" >> "$LOG_DIR/snapshot.log"
else
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) — no changes, skipped push" >> "$LOG_DIR/snapshot.log"
fi
