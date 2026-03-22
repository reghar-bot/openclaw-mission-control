# Mission Control Dashboard — Implementation Spec

**Version:** 1.0  
**Date:** 2026-03-14  
**Classification:** Internal — Ragnar's eyes only  

---

## 1. FIRST PRINCIPLES EVALUATION

### 1.1 The 5-7 Critical Signals

After analyzing system health from the research reports, these are the ONLY signals that actually indicate if the system is healthy or broken:

| Signal | Why It Matters | Threshold |
|--------|---------------|-----------|
| **Cron Failure Rate** | 11 of 50 crons are failing (22%). This is the #1 indicator. | >10% failing = degraded, >20% = critical |
| **Consecutive Errors** | Single cron with 10+ consecutive errors means total pipeline breakdown (Champagne Brief currently at 4 errors, Cron Watchdog at 10). | ≥2 = warning, ≥5 = critical |
| **Delegation Status** | APPROVED tasks sitting unspawned for >4 hours is the #1 failure mode per Chief of Staff Analysis. | Any PENDING >4h = critical |
| **Budget Burn Rate** | Currently at $235/$250 with 17 days left. Projection shows overage imminent. | >$200 = warning, >$225 = critical, >$240 = emergency |
| **Session Count** | 197 sessions (threshold 150). Indicates context/memory pressure. | >150 = warning, >200 = critical |
| **Champagne Pipeline Status** | Monday deliverable to Camilla. Currently broken (research not reaching curation). | BLOCKED or missing = critical |
| **Disk/Resource Pressure** | Currently healthy (17GB/228GB, load 2.1) but early warning for system stability. | Disk >80% or load >3.0 = warning |

### 1.2 What Is Noise (Ignore These)

These look useful but add no signal:

- **Total cron count** — 42 crons is a vanity metric. What matters is how many are *failing*.
- **Model distribution** — 31 default, 6 Haiku, etc. This is infrastructure detail, not health.
- **Line counts of system files** — AGENTS.md at 166 lines vs 200 threshold. Noise.
- **Specific file listings** — research/ output directories have 33-96 files. Not actionable.
- **Never-fired crons list** — 10 crons haven't fired. Some are monthly. Not an immediate concern.
- **Individual session details** — 197 sessions is the signal; individual session names are noise.
- **Provider health for all providers** — Only care about currently active provider.

### 1.3 Data Flow Architecture

**Decision: Static HTML generation, NOT real-time polling.**

Why:
1. Cloudflare Pages serves static files only — no server-side execution
2. OpenClaw runs on Ragnar's Mac mini behind NAT — no inbound connections possible
3. Real-time polling would require exposing the Mac mini or running a relay

**Data Flow:**
```
OpenClaw Mac mini (Ragnar's home)
    ↓ Every 15 minutes (cron)
    Generates: mission-control-data.json
    ↓ Git push (auto-committed by cron)
GitHub repo: ragnar-openclaw/mission-control
    ↓ Cloudflare Pages auto-deploy
Public: https://mission-control.ragnar.work
    ↓ Client-side JS reads data.json
Browser renders dashboard (password gate first)
```

**Generation Frequency:** 15 minutes is the sweet spot:
- 5 minutes = unnecessary git noise + CF build quota burn
- 30 minutes = too slow for a "mission control" feel
- 15 minutes matches the self-healing monitor cron frequency

**Data Freshness Indicator:** Dashboard shows "Last updated: [timestamp]" and colors it yellow if >30min old, red if >60min old.

---

## 2. EXACT DATA SOURCES

### 2.1 Primary Sources (read directly)

| Data | Source File/Command | Parser |
|------|---------------------|--------|
| Cron status | `openclaw cron list --json` → `~/.openclaw/jobs.json` | JSON |
| System health | `workspace/SYSTEM-HEALTH.md` (to be created) | Markdown frontmatter |
| Delegations | `workspace/PENDING-DELEGATIONS.md` (to be created) | Custom parser |
| Budget | Cost tracker logs → `workspace/logs/cost-tracker-daily.json` | JSONL aggregate |
| Sessions | `openclaw sessions list --json` | JSON count only |
| Champagne status | `workspace/champagne-pipeline-status.json` (to be created) | JSON |
| Disk/Load | `df -h /`, `uptime` | Shell output parse |

### 2.2 Derived/Secondary Sources (calculated)

| Metric | Calculation |
|--------|-------------|
| Cron failure % | (crons with consecutiveErrors > 0) / (total enabled crons) |
| Critical error count | crons with consecutiveErrors >= 5 |
| Budget projection | (current spend / days elapsed) * 31 |
| System status | Derived from SYSTEM-HEALTH.md status field |
| Oldest PENDING delegation | max(now - approval_time) for all PENDING items |

### 2.3 Data Generator Script

**File:** `workspace/scripts/generate-mission-control-data.sh`

**Responsibility:** Run every 15 minutes, read all sources, output single JSON.

```bash
#!/bin/bash
# Runs every 15 minutes via cron
OUTPUT="/Users/reghar/.openclaw/workspace/mission-control-data.json"
TEMP="/tmp/mc-data-$$.json"

# 1. Cron status
openclaw cron list --json > /tmp/crons.json

# 2. System health (read if exists, else create default)
HEALTH_FILE="/Users/reghar/.openclaw/workspace/SYSTEM-HEALTH.md"

# 3. Pending delegations
DELEGATIONS_FILE="/Users/reghar/.openclaw/workspace/PENDING-DELEGATIONS.md"

# 4. Cost data (aggregate from daily logs)
COST_FILE="/Users/reghar/.openclaw/workspace/logs/cost-tracker-daily.json"

# 5. Build combined JSON
python3 /Users/reghar/.openclaw/workspace/scripts/compile-mission-control.py \
    --crons /tmp/crons.json \
    --health "$HEALTH_FILE" \
    --delegations "$DELEGATIONS_FILE" \
    --cost "$COST_FILE" \
    --output "$TEMP"

# 6. Atomic write
mv "$TEMP" "$OUTPUT"

# 7. Git commit and push (if changed)
cd /Users/reghar/.openclaw/workspace/mission-control-repo
cp "$OUTPUT" ./data.json
git add data.json
git diff --cached --quiet || git commit -m "auto: mission control data $(date -Iseconds)"
git push origin main
```

### 2.4 Output JSON Schema

```json
{
  "generated_at": "2026-03-14T16:30:00+01:00",
  "source_host": "Ragnar-Mac-mini",
  "system": {
    "status": "HEALTHY",
    "last_updated": "2026-03-14T16:15:00+01:00",
    "agents_operational": "19/19",
    "crons_healthy": "39/50",
    "gateway_running": true,
    "gateway_uptime_hours": 48
  },
  "cron_health": {
    "total_enabled": 50,
    "total_failing": 11,
    "failure_rate_percent": 22,
    "critical_errors": 2,
    "warning_errors": 4,
    "top_failures": [
      {"name": "Pip — Cron Watchdog", "errors": 10, "category": "CHANNEL_CONFIG"},
      {"name": "Champagne Brief — Inkwell", "errors": 4, "category": "TIMEOUT"},
      {"name": "Pip — System Status Board", "errors": 3, "category": "CHANNEL_CONFIG"}
    ]
  },
  "delegations": {
    "total_pending": 3,
    "oldest_hours": 26,
    "critical": [
      {"task": "1Password security incident", "approved": "2026-03-08T10:00:00Z", "agent": "Kodex", "hours_pending": 150}
    ]
  },
  "budget": {
    "current_spend": 235.0,
    "monthly_budget": 250.0,
    "percent_used": 94,
    "projected_month_end": 312.0,
    "days_remaining": 17,
    "status": "CRITICAL"
  },
  "sessions": {
    "active_count": 197,
    "threshold": 150,
    "status": "WARNING"
  },
  "resources": {
    "disk_used_gb": 17,
    "disk_total_gb": 228,
    "disk_percent": 11,
    "load_15min": 2.12,
    "status": "HEALTHY"
  },
  "pipelines": {
    "champagne": {
      "status": "BROKEN",
      "last_run": "2026-03-14T01:15:00Z",
      "error": "Research output not reaching curation",
      "next_scheduled": "2026-03-16T06:00:00Z"
    }
  }
}
```

---

## 3. UI LAYOUT (Wireframe)

### 3.1 Password Gate (First Screen)

|                    MISSION CONTROL                       |
|              OPENCLAW SYSTEM DASHBOARD                   |
|                                                          |
|              [ Password Input Field ]                    |
|                                                          |
|                   [ Unlock ]                             |
|                                                          |
+----------------------------------------------------------+
```

**Password:** Simple SHA-256 hash check in client-side JS. Password is "ragnar2026" (Ragnar can change this). Not cryptographically secure (source visible) but keeps out casual browsers.

### 3.2 Main Dashboard Layout

```
+----------------------------------------------------------+
|  MISSION CONTROL                              [🔴 LIVE]  |
|  OpenClaw System Status              Last update: 16:30  |
+----------------------------------------------------------+
|                                                          |
|  +--------------+ +--------------+ +--------------+      |
|  | SYSTEM       | | CRON HEALTH  | | BUDGET       |      |
|  |              | |              | |              |      |
|  |   🟢         | |   🔴 22%     | |   🔴 94%     |      |
|  | HEALTHY      | | FAILING      | | USED         |      |
|  |              | | 11/50 down   | | $235/$250    |      |
|  +--------------+ +--------------+ +--------------+      |
|                                                          |
|  +--------------------------------------------------+   |
|  | ⚠️ CRITICAL ITEMS (Action Required)              |   |
|  |                                                  |   |
|  | 🔴 Champagne pipeline BROKEN — research not      |   |
|  |    reaching curation. 4 consecutive errors.      |   |
|  |                                                  |   |
|  | 🔴 Budget critical: 94% used, 17 days left.      |   |
|  |    Projected overage: $62. Auto-throttle active. |   |
|  |                                                  |   |
|  | 🟡 3 delegations PENDING >4 hours. Oldest: 150h  |   |
|  +--------------------------------------------------+   |
|                                                          |
|  +----------------------+ +-------------------------+   |
|  | CRON FAILURES        | | DELEGATIONS             |   |
|  | Top by error count:  | | Pending tasks: 3        |   |
|  |                      | |                         |   |
|  | 1. Cron Watchdog  10 | ░░░░░░░░░░░░░░░░░░░░░░  |   |
|  | 2. Champagne Ink   4 | 0h      12h      24h     |   |
|  | 3. Status Board    3 | [███░░░░░░░░░░░░░░░░░░] |   |
|  | 4. To-Do Tackler   2 | 26h oldest pending      |   |
|  |                      |                         |   |
|  | [View All 11]        | [View Details →]        |   |
|  +----------------------+ +-------------------------+   |
|                                                          |
|  +----------------------+ +-------------------------+   |
|  | RESOURCES            | | PIPELINES               |   |
|  |                      | |                         |   |
|  | Disk: 17GB / 228GB   | | 🍾 Champagne: 🔴 BROKEN |   |
|  | [████░░░░░░░░░░░░░░] | | 🤖 Automation: 🟡 IDLE  |   |
|  | 11% used             | | 📧 RE Daily: 🟢 PAUSED  |   |
|  |                      | |                         |   |
|  | Load: 2.12           | |                         |   |
|  | [███████░░░░░░░░░░░] | |                         |   |
|  | Sessions: 197/150    | |                         |   |
|  | ⚠️ Above threshold   | |                         |   |
|  +----------------------+ +-------------------------+   |
|                                                          |
+----------------------------------------------------------+
```

### 3.3 Color Scheme (Dark Ops)

**Background:** `#0d1117` (GitHub dark, not pure black — easier on eyes)  
**Card backgrounds:** `#161b22` with `#21262d` borders  
**Text:** `#c9d1d9` primary, `#8b949e` secondary  
**Accent colors:**
- 🟢 Healthy: `#238636` (success green)
- 🟡 Warning: `#d29922` (amber)
- 🔴 Critical: `#da3633` (red)
- 🔵 Info: `#58a6ff` (blue)

**Font:** System-ui stack — no external fonts to load. Monospace for data values.

### 3.4 Responsive Behavior

- **Desktop (>1200px):** 3-column top row, 2-column lower rows
- **Tablet (768-1200px):** 2-column layout
- **Mobile (<768px):** Single column stack, hide secondary panels behind "Details" toggle

---

## 4. PASSWORD IMPLEMENTATION

### 4.1 Client-Side Gate

Since this is static HTML on Cloudflare Pages, authentication is client-side JavaScript:

```javascript
// Password gate
const CORRECT_HASH = 'a1b2c3d4...'; // SHA-256 of "ragnar2026"

function checkPassword(input) {
    const hash = sha256(input);
    if (hash === CORRECT_HASH) {
        localStorage.setItem('mc_auth', hash);
        showDashboard();
    } else {
        document.getElementById('error').textContent = 'Incorrect';
    }
}

// Auto-show if previously authenticated this session
if (localStorage.getItem('mc_auth') === CORRECT_HASH) {
    showDashboard();
}
```

**Security note:** This is NOT cryptographically secure. Anyone can view source and see the hash. It's a "keep honest people honest" gate, not protection against determined attackers. For Ragnar's use case (personal dashboard, no sensitive data displayed), this is acceptable.

### 4.2 Alternative: Cloudflare Access (Optional Upgrade)

If stronger security is needed later:
1. Enable Cloudflare Access on the Pages domain
2. Configure Google/GitHub OAuth with Ragnar's email only
3. Remove client-side password gate
4. Zero code changes to dashboard itself

---

## 5. DEPLOYMENT APPROACH

### 5.1 Repository Structure

```
ragnar-openclaw/mission-control/    # GitHub repo
├── .github/
│   └── workflows/
│       └── deploy.yml              # GitHub Actions (optional)
├── data/
│   └── data.json                   # Auto-updated by cron
├── src/
│   ├── index.html                  # Main dashboard HTML
│   ├── styles.css                  # Dark ops theme
│   └── app.js                      # Dashboard logic
├── README.md
└── CNAME                           # mission-control.ragnar.work
```

### 5.2 Deployment Flow

**Step 1: Initial Setup (Kodex/Dais one-time)**
1. Create GitHub repo `ragnar-openclaw/mission-control`
2. Push initial HTML/CSS/JS from Dais design
3. Configure Cloudflare Pages to deploy from repo
4. Set custom domain: `mission-control.ragnar.work`
5. Add DNS CNAME record pointing to Cloudflare

**Step 2: Auto-Update Setup (Kodex)**
1. Create `workspace/mission-control-repo/` as git clone of the repo
2. Add SSH deploy key to GitHub (read/write)
3. Configure `generate-mission-control-data.sh` to run every 15 minutes
4. Script generates JSON, commits if changed, pushes to trigger deploy

**Step 3: Cron Configuration**
```json
{
  "name": "Mission Control Data Refresh",
  "schedule": {"kind": "every", "everyMs": 900000},
  "payload": {
    "kind": "systemEvent",
    "text": "Run /Users/reghar/.openclaw/workspace/scripts/generate-mission-control-data.sh"
  },
  "timeoutSeconds": 60,
  "delivery": {"mode": "none"}
}
```

### 5.3 Cloudflare Pages Configuration

**Build settings:**
- Build command: `echo "Static site, no build needed"`
- Build output: `/`
- Root directory: `/`

**Environment:**
- Production branch: `main`
- Auto-deploy on push: enabled
- Preview deployments: disabled (only main branch)

### 5.4 Custom Domain

Ragnar needs to own a domain (suggest `ragnar.work` or use existing). DNS:
```
CNAME  mission-control  ragnar-openclaw.pages.dev
```

If no domain available, use `https://ragnar-openclaw.pages.dev` directly.

---

## 6. DIVISION OF WORK

### 6.1 What Dais (Designer) Needs to Deliver

**File:** `workspace-designer/mission-control/design-package-2026-03-14/`

| Deliverable | Format | Notes |
|-------------|--------|-------|
| `index.html` | HTML | Complete dashboard with password gate, all panels |
| `styles.css` | CSS | Dark ops theme, responsive breakpoints |
| `app.js` | JavaScript | Password gate, data rendering, auto-refresh |
| `sample-data.json` | JSON | Sample data for visual testing |
| `README.md` | Markdown | Design notes, color reference, animation specs |

**Design Requirements:**
- Password gate: centered, minimal, "enter the vault" feel
- Main dashboard: information-dense, no whitespace waste
- Status cards: big number + label + mini-chart/trend
- Critical items panel: red left border, bold text, clear hierarchy
- Auto-refresh: every 60 seconds, with visual "updating..." indicator
- Mobile: functional, but desktop is primary use case

**Technical Constraints for Dais:**
- No external API calls (data loaded from local `data.json`)
- No external fonts (system fonts only)
- No frameworks (vanilla JS, keep it simple)
- Single HTML file acceptable (no build step)

### 6.2 What Kodex (Developer) Needs to Build

**Scripts:**

1. **`scripts/generate-mission-control-data.sh`**
   - Runs every 15 minutes
   - Reads all data sources
   - Outputs valid JSON
   - Git commit + push if changed

2. **`scripts/compile-mission-control.py`**
   - Python helper called by shell script
   - Parses markdown files (SYSTEM-HEALTH.md, PENDING-DELEGATIONS.md)
   - Aggregates cost data
   - Calculates derived metrics
   - Outputs final JSON

3. **`scripts/setup-mission-control-repo.sh`**
   - One-time setup script
   - Clones GitHub repo to workspace
   - Configures git user and SSH key
   - Tests push to verify

**Data Infrastructure (to be created):**

1. **`workspace/SYSTEM-HEALTH.md`**
   - Updated by monitoring crons
   - Format: YAML frontmatter + markdown body
   - Contains: status, timestamp, agent counts, gateway status, budget

2. **`workspace/PENDING-DELEGATIONS.md`**
   - Updated when tasks are APPROVED
   - Format: table with task, approval time, agent, status
   - Updated when tasks are spawned/completed

3. **`workspace/champagne-pipeline-status.json`**
   - Updated by champagne pipeline crons
   - Contains: current step, status, last error, next scheduled

**Cron Setup:**
- Add `Mission Control Data Refresh` cron (15 min interval, 60s timeout)
- Ensure it runs on `assistant` agent (lightweight)

### 6.3 Integration Steps

1. **Kodex creates data infrastructure first** (SYSTEM-HEALTH.md, PENDING-DELEGATIONS.md, scripts)
2. **Kodex tests data generation** locally until JSON output is valid
3. **Dais designs dashboard** using sample-data.json for visual testing
4. **Kodex integrates** design into mission-control-repo
5. **Kodex deploys** to Cloudflare Pages
6. **Kodex verifies** end-to-end: cron → git → Pages → browser

---

## 7. SUCCESS CRITERIA

The dashboard is done when:

- [ ] Password gate works (blocks access without password)
- [ ] Dashboard loads at custom domain
- [ ] Data refreshes within 15 minutes of source changes
- [ ] All 7 critical signals display correctly
- [ ] Visual hierarchy: critical items are most prominent
- [ ] Mobile view is functional (if not beautiful)
- [ ] Ragnar can view it from his phone anywhere in the world

---

## 8. APPENDIX: ERROR CLASSIFICATION MAPPING

For the cron health panel, map `lastError` strings to categories:

| Error Pattern | Category | Color | Display |
|--------------|----------|-------|---------|
| `channel.*required`, `recipient.*required` | CHANNEL_CONFIG | 🔴 | Config |
| `timed out`, `timeout` | TIMEOUT | 🟡 | Timeout |
| `credit balance`, `credit exhausted` | PROVIDER_CREDIT | 🔴 | Credits |
| `file not found`, `no such file` | UPSTREAM_MISSING | 🟡 | Missing |
| `write failed`, `edit failed` | WRITE_FAILED | 🔴 | Write |
| `message.*failed`, `delivery failed` | DELIVERY_FAILED | 🟡 | Delivery |
| (anything else) | UNKNOWN | 🟡 | Unknown |

---

*End of spec. Ready for Kodex implementation and Dais design.*