# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Poolman is a Bitcoin solo mining dashboard ("TangNet Mining Ops") — a Flask app that aggregates live stats from CKPool and Public Pool into terminal-style web UIs. Designed to run as a kiosk on a Raspberry Pi 5 with a small dedicated screen, plus a more elaborate "lab" dashboard for desktop monitors.

## Running the App

Quick launch from the repo root (creates venv + installs deps on first run). The server hosts both dashboards; the argument picks which page to auto-open in a browser:
```bash
.\run.ps1 [lab|pi|kiosk|none|stop]   # Windows, defaults to lab; kiosk detaches the server
./run.sh [lab|pi]                    # Linux / macOS / Pi, defaults to server-only
```

Or manually:
```bash
pip install -r requirements.txt
python app.py
```

Config via `.env` file (loaded by python-dotenv) or environment variable:
```
BTC_ADDRESS=your_btc_address_here
```

Server starts on `http://0.0.0.0:5000`. Both dashboards auto-refresh via AJAX every 30 seconds.

## Architecture

- **`app.py`** — Flask backend: serves two page routes (`/` and `/lab`) plus three JSON API proxy endpoints
- **`templates/index.html`** — Pi dashboard: green-on-black terminal aesthetic, tabbed interface (All / CKPool / Public Pool), responsive down to 480px
- **`templates/lab.html`** — Lab dashboard ("Operation TangNet"): three-panel command center with Rick & Morty / The Patriot theme, odds calculator, snake timeline. Designed for 16" monitors
- **`poolman.service`** — systemd unit for Pi auto-start
- **`start-kiosk.sh`** — Chromium kiosk launcher

### Data Flow

Flask proxies three external APIs (all keyed on `BTC_ADDRESS`):
- **CKPool** (`/api/ckpool`): `https://solo.ckpool.org/users/{addr}` — may return NDJSON, `fetch_ckpool()` handles this by parsing the first complete JSON object
- **Public Pool** (`/api/publicpool`): `https://public-pool.io:40557/api/client/{addr}`
- **Network** (`/api/network`): `https://public-pool.io:40557/api/network`

Frontend fetches these three endpoints every 30s and renders data client-side. All CSS/JS is inline in each template (no build step, no external assets).

### Key Frontend Concepts (shared by both dashboards)

- **Ghost workers**: When a worker drops from the API, it stays visible as offline for up to 1 hour (`GHOST_EXPIRY`). Public Pool workers use session-based eviction (new session = evict oldest ghost 1:1)
- **Worker status**: Online (<3 min since last seen), Stale (3-5 min, yellow), Offline (>5 min, red)
- **Codenames**: Generic worker names (BTC addresses, "worker") get replaced with themed codenames (PICKLE RICK, LAKEMAN, etc.)
- **Hashrate parsing**: CKPool returns hashrate as strings like "1.46T" — `parseHashrateString()` normalizes to H/s

### Lab Dashboard Extras (`/lab`)

- **Odds Calculator**: `expected_seconds = (difficulty * 2^32) / hashrate`, maps result to historical eras
- **Snake Timeline**: 20 milestones from Big Bang to present, portal marker shows where your expected wait lands
- **Rick quotes**: Each era has a unique quip calibrated to your mining futility

## Pi Deployment

1. Copy files to the Pi
2. Create `.env` with your `BTC_ADDRESS`
3. Edit `poolman.service`: set `User` and `WorkingDirectory`
4. `sudo cp poolman.service /etc/systemd/system/ && sudo systemctl enable --now poolman`
5. Add `start-kiosk.sh` to autostart for kiosk mode
