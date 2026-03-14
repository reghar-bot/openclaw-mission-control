# Mission Control Dashboard — Build Brief

## What
A single self-contained HTML dashboard that visualizes all OpenClaw crons and agent activity.

## How it works
1. `scripts/generate.py` calls `openclaw cron list --json`, parses the JSON, and generates `index.html`
2. `index.html` is entirely static — no server needed. Open in browser or display via canvas.
3. A refresh script or cron will regenerate every 10 minutes.

## Data source
Run: `openclaw cron list --json`
This returns a JSON object with `jobs` array. Each job has:
- id, name, agentId, enabled, schedule (kind/expr/tz), payload (kind/model/timeoutSeconds)
- state: nextRunAtMs, lastRunAtMs, lastRunStatus, lastDurationMs, consecutiveErrors, lastError
- delivery (mode/channel/to)

## Views to build

### 1. Status Grid (main view)
All crons as cards, sorted by nextRunAtMs. Each card shows:
- Cron name (truncated if needed)
- Agent badge (color-coded by agentId: main=blue, researcher=purple, writer=green, developer=orange, assistant=gray, strategist=teal, nolea-analyst=pink)
- Status indicator: ✅ ok | ⚠️ warning (1 error) | 🔴 critical (2+ errors) | ⏸ disabled
- Next run: relative time ("in 3h 22m")
- Last run: relative time + duration ("4m ago, 82s")
- Model: small badge if sonnet/opus/haiku

### 2. Timeline (next 24h)
Horizontal timeline of upcoming crons, grouped by hour. Visual bar chart of cron density per hour. Click a cron to highlight its card in the grid.

### 3. Pipeline Groups
Known pipelines should be grouped:
- Champagne Pipeline (Mon): 8 steps (Pre-fetch 05:50 → Sigrid 06:00 → Curation 07:00 → Brief 08:00 → Judge 08:08 → Editor-in-Chief 08:18 → Approval 08:30 → Send 09:00)
- RE Daily (Mon-Thu): 5 steps
- Automation Scout: 3 steps
- Nightly: Audit → Memory → QMD → Doctor
- Advisory Council (Sunday): Briefs → Pre-prep → Board → Review

### 4. Activity Feed
Last 10 crons that ran, with status and duration. "X ran Y seconds ago — ok/error".

## Design requirements
- Dark theme (matches Ragnar's aesthetic)
- No external dependencies — pure HTML/CSS/JS, inline everything
- Tailwind CDN is OK (or just write clean CSS)
- Responsive — works on Mac mini display and mobile
- Generated timestamp at top: "Last updated: [time]"
- Auto-meta-refresh every 5 minutes: `<meta http-equiv="refresh" content="300">`

## File structure
```
mission-control/
  scripts/
    generate.py          # main generator script
  index.html             # generated output (gitignored or committed)
  README.md
```

## Agent badges / color map
- main → #3B82F6 (blue)
- researcher → #8B5CF6 (purple)  
- writer → #10B981 (green)
- developer → #F97316 (orange)
- assistant → #6B7280 (gray)
- strategist → #0D9488 (teal)
- nolea-analyst → #EC4899 (pink)

## Status colors
- ok → green (#22C55E)
- error (1x) → yellow (#EAB308)
- error (2x+) → red (#EF4444)
- disabled → gray (#6B7280)

## When done
1. Run `python3 scripts/generate.py` — confirm index.html is generated successfully
2. Run `openclaw system event --text "Done: Mission Control Dashboard built — index.html ready in workspace/mission-control/" --mode now`
