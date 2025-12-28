#!/usr/bin/env bash
set -euo pipefail

URL="${1:-http://127.0.0.1:8910/runs}"
echo "[URL] $URL"

H="$(curl -sS "$URL")"

echo "== scripts (src=) =="
echo "$H" | grep -nEoi '<script[^>]+src=[^>]+>' | head -n 80 || true
echo
echo "== extract src/href candidates =="
echo "$H" | grep -Eo 'src=["'"'"'][^"'"'"']+|href=["'"'"'][^"'"'"']+' | sed 's/^src=//;s/^href=//' | tr -d '"' | tr -d "'" | head -n 120 || true
echo
echo "== quick find bundle keywords =="
echo "$H" | grep -nE 'vsp_bundle|bundle|static/js|/static/js|\.js\?|\.css\?' | head -n 120 || true
