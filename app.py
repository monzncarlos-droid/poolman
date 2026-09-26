import json
import os
import time

from dotenv import load_dotenv
from flask import Flask, jsonify, render_template
import requests

load_dotenv()

app = Flask(__name__)

BTC_ADDRESS = os.environ.get("BTC_ADDRESS", "YOUR_ADDRESS")
if BTC_ADDRESS == "YOUR_ADDRESS":
    print("WARNING: BTC_ADDRESS is not set — create a .env file with BTC_ADDRESS=<your address>")

CKPOOL_URL = f"https://solo.ckpool.org/users/{BTC_ADDRESS}"
PUBLICPOOL_URL = f"https://public-pool.io:40557/api/client/{BTC_ADDRESS}"
PUBLICPOOL_NETWORK_URL = "https://public-pool.io:40557/api/network"
BTCPOWLAB_URL = f"https://btcpowlab-pool.com/public/v1/miner/{BTC_ADDRESS}"

# Shared upstream cache: multiple open dashboards (Pi kiosk + lab) poll every 30s
# each — serve them from one upstream fetch instead of hammering the pools.
CACHE_TTL = 25  # seconds, just under the 30s frontend refresh
_cache = {}


def cached(key, fetch_fn):
    now = time.time()
    hit = _cache.get(key)
    if hit and now - hit[0] < CACHE_TTL:
        return hit[1]
    data = fetch_fn()
    _cache[key] = (now, data)
    return data


def fetch_ckpool():
    """Fetch CKPool data. Handles NDJSON (multiple JSON objects concatenated) by parsing the first."""
    try:
        resp = requests.get(CKPOOL_URL, timeout=10)
        resp.raise_for_status()
        text = resp.text.strip()
        if not text:
            return {"error": "Empty response from CKPool"}
        # raw_decode parses the first complete JSON value and ignores anything
        # after it, which covers both plain JSON and NDJSON responses
        data, _ = json.JSONDecoder().raw_decode(text)
        return data
    except requests.RequestException as e:
        return {"error": f"CKPool unreachable: {e}"}
    except ValueError as e:
        return {"error": f"CKPool bad JSON: {e}"}


def fetch_publicpool():
    """Fetch Public Pool client data."""
    try:
        resp = requests.get(PUBLICPOOL_URL, timeout=10)
        resp.raise_for_status()
        return resp.json()
    except requests.RequestException as e:
        return {"error": f"Public Pool unreachable: {e}"}
    except ValueError as e:
        return {"error": f"Public Pool bad JSON: {e}"}


def fetch_btcpowlab():
    """Fetch the public BTC PoW Lab miner snapshot."""
    try:
        resp = requests.get(BTCPOWLAB_URL, timeout=10)
        resp.raise_for_status()
        return resp.json()
    except requests.RequestException as e:
        return {"error": f"BTC PoW Lab unreachable: {e}"}
    except ValueError as e:
        return {"error": f"BTC PoW Lab bad JSON: {e}"}


def fetch_network():
    """Fetch Bitcoin network info from Public Pool."""
    try:
        resp = requests.get(PUBLICPOOL_NETWORK_URL, timeout=10)
        resp.raise_for_status()
        return resp.json()
    except requests.RequestException as e:
        return {"error": f"Network info unreachable: {e}"}
    except ValueError as e:
        return {"error": f"Network info bad JSON: {e}"}


@app.route("/")
def home():
    return render_template("index.html")


@app.route("/lab")
def lab():
    return render_template("lab.html")


@app.route("/api/ckpool")
def api_ckpool():
    return jsonify(cached("ckpool", fetch_ckpool))


@app.route("/api/publicpool")
def api_publicpool():
    return jsonify(cached("publicpool", fetch_publicpool))


@app.route("/api/btcpowlab")
def api_btcpowlab():
    return jsonify(cached("btcpowlab", fetch_btcpowlab))


@app.route("/api/network")
def api_network():
    return jsonify(cached("network", fetch_network))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
