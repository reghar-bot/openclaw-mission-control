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

# Read agent improvement backlog for Mission Control visibility
BACKLOG_FILE="/Users/reghar/.openclaw/workspace/AGENT-IMPROVEMENT-BACKLOG.md"
if [ -f "$BACKLOG_FILE" ]; then
  export AGENT_BACKLOG_MD=$(cat "$BACKLOG_FILE")
else
  export AGENT_BACKLOG_MD=''
fi

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

# Read budget data from cost-status.json
COST_STATUS_FILE="/Users/reghar/.openclaw/workspace/logs/cost-status.json"
if [ -f "$COST_STATUS_FILE" ]; then
  export COST_STATUS=$(cat "$COST_STATUS_FILE")
else
  export COST_STATUS='{}'
fi

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

# Parse cost-status.json for budget data
cost_raw = os.environ.get('COST_STATUS', '{}')
try:
    cost_data = json.loads(cost_raw)
except json.JSONDecodeError:
    cost_data = {}
budget_month_usd = cost_data.get('month_usd')
budget_monthly_limit = cost_data.get('budget_monthly', 200)
budget_daily_limit = cost_data.get('budget_daily', 5)

backlog_md = os.environ.get('AGENT_BACKLOG_MD', '')

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
    elif sched.get('kind') == 'at':
        at_val = sched.get('at', '')
        schedule_str = f'at {at_val}' if at_val else ''
    else:
        schedule_str = ''

    payload = j.get('payload', {})
    timeout_ms = payload.get('timeoutMs')
    timeout_seconds = payload.get('timeoutSeconds')
    if timeout_ms:
        timeout_seconds = timeout_ms // 1000

    last_error = state.get('lastError') or state.get('lastErrorReason')

    raw_status = state.get('lastRunStatus') or state.get('lastStatus') or 'unknown'
    last_dur = state.get('lastDurationMs')

    crons.append({
        'id': j.get('id', ''),
        'name': j.get('name', ''),
        'agentId': j.get('agentId') or j.get('sessionTarget', 'main'),
        'enabled': j.get('enabled', True),
        'schedule': schedule_str,
        'lastRunAt': ms_to_iso(state.get('lastRunAtMs')),
        'nextRunAt': ms_to_iso(state.get('nextRunAtMs')),
        'lastRunStatus': raw_status,
        'lastDurationMs': last_dur,
        'consecutiveErrors': state.get('consecutiveErrors', 0),
        'lastError': last_error,
        'timeoutSeconds': timeout_seconds
    })

backlog_items = []
if backlog_md:
    lines = backlog_md.splitlines()
    in_table = False
    for line in lines:
        if line.startswith('| Issue | Category | Owner | Status | Decision Level | Next Review Date | Notes |'):
            in_table = True
            continue
        if not in_table:
            continue
        if line.startswith('|---'):
            continue
        if not line.startswith('|'):
            if backlog_items:
                break
            continue
        parts = [part.strip() for part in line.strip().strip('|').split('|')]
        if len(parts) != 7:
            continue
        backlog_items.append({
            'issue': parts[0],
            'category': parts[1],
            'owner': parts[2],
            'status': parts[3],
            'decisionLevel': parts[4],
            'nextReviewDate': parts[5],
            'notes': parts[6],
        })

backlog_summary = {
    'total': len(backlog_items),
    'byDecisionLevel': {
        'auto': sum(1 for item in backlog_items if item.get('decisionLevel') == 'auto'),
        'review': sum(1 for item in backlog_items if item.get('decisionLevel') == 'review'),
        'your-call': sum(1 for item in backlog_items if item.get('decisionLevel') == 'your-call'),
    },
    'items': backlog_items,
}

snapshot = {
    "generatedAt": timestamp,
    "generatorVersion": "1.3.0",
    "system": {
        "status": sys_status,
        "gatewayStatus": gateway,
        "gatewayPid": gw_pid,
        "sessionCount": session_count,
        "agentCount": agent_count
    },
    "budget": {
        "currentMonth": budget_month_usd,
        "limit": budget_monthly_limit,
        "dayOfMonth": day_of_month,
        "daysInMonth": days_in_month,
        "projected": round(budget_month_usd / day_of_month * days_in_month, 2) if budget_month_usd and day_of_month > 0 else None,
        "status": (
            "critical" if budget_month_usd is not None and budget_month_usd >= budget_monthly_limit * 0.9
            else "warning" if budget_month_usd is not None and budget_month_usd >= budget_monthly_limit * 0.7
            else "ok" if budget_month_usd is not None
            else "unknown"
        )
    },
    "pipelines": [
        {"name": "Champagne Brief (Mon)", "schedule": "Mondays 06:00-09:00", "status": "ok", "statusNote": "Pipeline fix applied Mar 14 — Sigrid handles curation", "lastSuccess": "2026-03-14"},
        {"name": "To-Do Tackler (Nightly)", "schedule": "Daily 23:00", "status": "ok", "statusNote": "Sigrid timeout fixed (600s) — running ok since Mar 14", "lastSuccess": "2026-03-14"},
        {"name": "Nightly Maintenance", "schedule": "Daily 21:30", "status": "ok", "statusNote": "End-of-Day sequence running", "lastSuccess": "2026-03-14"},
        {"name": "RE Daily / Weekly", "schedule": "PAUSED", "status": "paused", "statusNote": "Cost-cutting — re-enable when cost pressure eases", "lastSuccess": "2026-03-01"}
    ],
    "crons": crons,
    "errors": {
        "total": failing + warning_count,
        "critical": failing,
        "warning": warning_count
    },
    "agentImprovementBacklog": backlog_summary
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
