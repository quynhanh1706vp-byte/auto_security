#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== HEADERS =="
curl -sS -D- -o /tmp/runs20.json "$BASE/api/vsp/runs?limit=20" | egrep -i 'HTTP/|Content-Type|Content-Length|X-VSP-RUNS|Server|Date' || true

echo
echo "== BODY (first 320 chars) =="
head -c 320 /tmp/runs20.json; echo

echo
echo "== KEYS =="
cat /tmp/runs20.json | jq -r 'keys|join(",")' || true

echo
echo "== SNAPSHOT =="
cat /tmp/runs20.json | jq '{ok,limit,_scanned,items_len:(.items|length)}' -c || true
