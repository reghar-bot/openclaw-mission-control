#!/bin/bash
set -euo pipefail

OPENCLAW="/opt/homebrew/bin/openclaw"
REPO_DIR="/Users/reghar/.openclaw/workspace/mission-control"
OUTPUT_DIR="$REPO_DIR/data"
OUTPUT_FILE="$OUTPUT_DIR/data.json"
GIT="/usr/bin/git"

mkdir -p "$OUTPUT_DIR"

# Collect cron data
CRONS=$("$OPENCLAW" cron list --json 2>/dev/null || echo '{"jobs":[]}')

# Collect gateway status
if "$OPENCLAW" gateway status 2>&1 | grep -q "running"; then
  GATEWAY="running"
  GW_PID=$("$OPENCLAW" gateway status 2>/dev/null | grep -oE 'pid [0-9]+' | grep -oE '[0-9]+' || echo "0")
else
  GATEWAY="down"
  GW_PID="0"
fi

# Collect agent/session counts
STATUS_OUT=$("$OPENCLAW" status 2>/dev/null || echo "")
AGENT_COUNT=$(echo "$STATUS_OUT" | grep -oE '[0-9]+ · [0-9]+ bootstrap' | grep -oE '^[0-9]+' || echo "0")
SESSION_COUNT=$(echo "$STATUS_OUT" | grep -oE 'sessions [0-9]+' | grep -oE '[0-9]+' || echo "0")

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export CRON_DATA="$CRONS"
export GW_STATUS="$GATEWAY"
export GW_PID_VAL="$GW_PID"
export AGENT_COUNT="$AGENT_COUNT"
export SESSION_COUNT="$SESSION_COUNT"
export SNAP_TIME="$TIMESTAMP"
export SNAP_OUTPUT="$OUTPUT_FILE"
export SNAP_DAY=$(date +"%d")
export SNAP_DAYS_IN_MONTH=$(python3 -c "import calendar, datetime; d=datetime.date.today(); print(calendar.monthrange(d.year,d.month)[1])")

python3 << 'PYEOF'
import json, os
from datetime import datetime, timezone

cron_raw = os.environ.get('CRON_DATA', '{"jobs":[]}')
gateway = os.environ.get('GW_STATUS', 'unknown')
gw_pid = int(os.environ.get('GW_PID_VAL', '0') or '0')
agent_count = int(os.environ.get('AGENT_COUNT', '0') or '0')
session_count = int(os.environ.get('SESSION_COUNT', '0') or '0')
timestamp = os.environ.get('SNAP_TIME', '')
output_file = os.environ.get('SNAP_OUTPUT', '/dev/stdout')
day_of_month = int(os.environ.get('SNAP_DAY', '1'))
days_in_month = int(os.environ.get('SNAP_DAYS_IN_MONTH', '31'))

try:
    crons_data = json.loads(cron_raw)
except json.JSONDecodeError:
    crons_data = {"jobs": []}

jobs = crons_data.get('jobs', [])
total = len(jobs)
failing = sum(1 for j in jobs if j.get('state', {}).get('consecutiveErrors', 0) >= 2)
warning_count = sum(1 for j in jobs if j.get('state', {}).get('consecutiveErrors', 0) == 1)
healthy = total - failing - warning_count

if failing >= 3:
    sys_status = "CRITICAL"
elif failing >= 1:
    sys_status = "DEGRADED"
elif warning_count >= 1:
    sys_status = "WARNING"
else:
    sys_status = "OK"

def ms_to_iso(ms):
    if not ms:
        return None
    try:
        return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).isoformat().replace('+00:00', 'Z')
    except:
        return None

crons = []
for j in jobs:
    state = j.get('state', {})
    sched = j.get('schedule', {})

    if sched.get('kind') == 'cron':
        schedule_str = sched.get('expr', '')
    elif sched.get('kind') == 'every':
        ms = sched.get('everyMs', 0)
        mins = ms // 60000
        schedule_str = f'every {mins}m'
    else:
        schedule_str = ''

    payload = j.get('payload', {})
    timeout_ms = payload.get('timeoutMs')
    timeout_seconds = payload.get('timeoutSeconds')
    if timeout_ms:
        timeout_seconds = timeout_ms // 1000

    last_error = state.get('lastError') or state.get('lastErrorReason')

    crons.append({
        'id': j.get('id', ''),
        'name': j.get('name', ''),
        'agentId': j.get('agentId') or j.get('sessionTarget', 'main'),
        'enabled': j.get('enabled', True),
        'schedule': schedule_str,
        'lastRunAt': ms_to_iso(state.get('lastRunAtMs')),
        'nextRunAt': ms_to_iso(state.get('nextRunAtMs')),
        'lastRunStatus': state.get('lastRunStatus') or state.get('lastStatus', 'unknown'),
        'lastDurationMs': state.get('lastDurationMs', 0),
        'consecutiveErrors': state.get('consecutiveErrors', 0),
        'lastError': last_error,
        'timeoutSeconds': timeout_seconds
    })

snapshot = {
    "generatedAt": timestamp,
    "generatorVersion": "1.1.0",
    "system": {
        "status": sys_status,
        "gatewayStatus": gateway,
        "gatewayPid": gw_pid,
        "sessionCount": session_count,
        "agentCount": agent_count
    },
    "budget": {
        "currentMonth": None,
        "limit": 250.00,
        "dayOfMonth": day_of_month,
        "daysInMonth": days_in_month,
        "projected": None,
        "status": "unknown"
    },
    "pipelines": [
        {"name": "Champagne Brief (Mon)", "schedule": "Mondays 06:00-09:00", "status": "ok", "statusNote": "Pipeline fix applied Mar 14 — Sigrid handles curation", "lastSuccess": "2026-03-14"},
        {"name": "To-Do Tackler (Nightly)", "schedule": "Daily 23:00", "status": "broken", "statusNote": "Sigrid timing out — needs runTimeoutSeconds >= 480", "lastSuccess": "2026-03-13"},
        {"name": "Nightly Maintenance", "schedule": "Daily 21:30", "status": "ok", "statusNote": "End-of-Day sequence running", "lastSuccess": "2026-03-14"},
        {"name": "RE Daily / Weekly", "schedule": "PAUSED", "status": "paused", "statusNote": "Cost-cutting — re-enable when cost pressure eases", "lastSuccess": "2026-03-01"}
    ],
    "crons": crons,
    "errors": {
        "total": failing + warning_count,
        "critical": failing,
        "warning": warning_count
    }
}

with open(output_file, 'w') as f:
    json.dump(snapshot, f, indent=2)

print(f"data.json written: {total} crons ({healthy} healthy, {warning_count} warning, {failing} failing) | gateway: {gateway} | status: {sys_status}")
PYEOF

# Push to GitHub so Cloudflare Pages auto-deploys
cd "$REPO_DIR"
"$GIT" add data/data.json
if "$GIT" diff --cached --quiet; then
  echo "No changes to data.json, skipping push."
else
  "$GIT" commit -m "chore: mission control snapshot [$TIMESTAMP]"
  "$GIT" push origin main
  echo "Pushed data.json to GitHub at $TIMESTAMP"
fi
