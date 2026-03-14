#!/bin/bash
set -euo pipefail

OUTPUT_DIR="/Users/reghar/.openclaw/workspace/mission-control/data"
OUTPUT_FILE="$OUTPUT_DIR/snapshot.json"
mkdir -p "$OUTPUT_DIR"

# Source zshrc to get openclaw in PATH
source /Users/reghar/.zshrc 2>/dev/null || true

# Collect cron data
CRONS=$(openclaw cron list --json 2>/dev/null || echo '{"jobs":[]}')

# Collect gateway status
if openclaw gateway status 2>&1 | grep -q "running"; then
  GATEWAY="running"
else
  GATEWAY="down"
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export CRON_DATA="$CRONS"
export GW_STATUS="$GATEWAY"
export SNAP_TIME="$TIMESTAMP"
export SNAP_OUTPUT="$OUTPUT_FILE"

python3 << 'PYEOF'
import json, os

cron_raw = os.environ.get('CRON_DATA', '{"jobs":[]}')
gateway = os.environ.get('GW_STATUS', 'unknown')
timestamp = os.environ.get('SNAP_TIME', '')
output_file = os.environ.get('SNAP_OUTPUT', '/dev/stdout')

try:
    crons = json.loads(cron_raw)
except json.JSONDecodeError:
    crons = {"jobs": []}

jobs = crons.get('jobs', [])
total = len(jobs)
failing = sum(1 for j in jobs if j.get('state', {}).get('consecutiveErrors', 0) >= 2)
warning = sum(1 for j in jobs if j.get('state', {}).get('consecutiveErrors', 0) == 1)
healthy = total - failing - warning

snapshot = {
    "generated_at": timestamp,
    "summary": {
        "total_crons": total,
        "healthy": healthy,
        "warning": warning,
        "failing": failing,
        "gateway": gateway
    },
    "crons": jobs
}

with open(output_file, 'w') as f:
    json.dump(snapshot, f, indent=2)

print(f"Snapshot written to {output_file} at {timestamp} ({total} crons, {healthy} healthy, {failing} failing)")
PYEOF
