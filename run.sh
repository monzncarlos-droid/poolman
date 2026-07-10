#!/usr/bin/env bash
# Quick launch (Linux/macOS/Pi) — creates the venv and installs deps on first run,
# then starts the server (which serves BOTH dashboards).
# Usage: ./run.sh            # server only (the Pi kiosk opens its own browser)
#        ./run.sh lab        # also open the lab dashboard (/lab) in a browser
#        ./run.sh pi         # also open the Pi dashboard (/)
set -e
cd "$(dirname "$0")"

case "${1:-}" in
    lab) URL="http://localhost:5000/lab" ;;
    pi)  URL="http://localhost:5000/" ;;
    "")  URL="" ;;
    *)   echo "usage: ./run.sh [lab|pi]"; exit 1 ;;
esac

if [ ! -d venv ]; then
    echo "[poolman] Creating virtual environment..."
    python3 -m venv venv
fi

PY=venv/bin/python

if ! "$PY" -c "import flask, dotenv, requests" >/dev/null 2>&1; then
    echo "[poolman] Installing dependencies..."
    "$PY" -m pip install -r requirements.txt
fi

if [ ! -f .env ]; then
    echo "[poolman] WARNING: no .env file found. Create one with BTC_ADDRESS=<your address>."
fi

if [ -n "$URL" ]; then
    # In the background: wait until the server answers, then open the browser
    (
        up=0
        for _ in $(seq 1 30); do
            if curl -s -o /dev/null "$URL" 2>/dev/null; then up=1; break; fi
            sleep 0.5
        done
        if [ "$up" = "1" ]; then
            if command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL" >/dev/null 2>&1
            elif command -v open >/dev/null 2>&1; then open "$URL"
            fi
        fi
    ) &
    echo "[poolman] Will open $URL when the server is ready."
fi

echo "[poolman] Pi dashboard:  http://localhost:5000"
echo "[poolman] Lab dashboard: http://localhost:5000/lab"
echo "[poolman] Starting server... Ctrl+C to stop."
exec "$PY" app.py
