#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
EP="/api/vsp/rid_latest"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*"; }
err(){ echo "[ERR] $*" >&2; exit 2; }

tmp="$(mktemp -d /tmp/vsp_smoke_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

need(){ command -v "$1" >/dev/null 2>&1 || err "missing: $1"; }
need curl; need python3; need head; need sed; need date

echo "SMOKE wait-json @ $(date) BASE=$BASE"
echo "== polling $EP for JSON 200 =="

stable=0
for i in $(seq 1 80); do
  hdr="$tmp/hdr.txt"
  body="$tmp/body.txt"
  code="$(curl -sS -D "$hdr" -o "$body" -w "%{http_code}" "$BASE$EP" || echo "000")"

  ctype="$(grep -i '^content-type:' "$hdr" | head -n 1 | sed 's/\r$//' || true)"
  first="$(head -n 1 "$body" 2>/dev/null || true)"

  if [ "$code" = "200" ]; then
    if python3 - "$body" <<'PY' >/dev/null 2>&1
import json,sys
p=sys.argv[1]
s=open(p,'rb').read()
if not s.strip(): raise SystemExit(2)
j=json.loads(s.decode('utf-8','replace'))
assert isinstance(j, dict)
assert 'rid' in j or 'ok' in j
PY
    then
      stable=$((stable+1))
      ok "try=$i HTTP=200 JSON_OK stable=$stable ctype=${ctype:-none}"
      # require 3 consecutive OK to be sure
      if [ "$stable" -ge 3 ]; then
        echo "== FINAL body =="
        python3 - <<'PY'
import json,sys,subprocess
import urllib.request
import os
import urllib.parse
PY
        cat "$body"
        echo
        ok "server is stable (3 consecutive JSON OK)"
        exit 0
      fi
    else
      stable=0
      warn "try=$i HTTP=200 but JSON_INVALID ctype=${ctype:-none} first_line=$(printf "%s" "$first" | head -c 120)"
    fi
  else
    stable=0
    warn "try=$i HTTP=$code ctype=${ctype:-none} first_line=$(printf "%s" "$first" | head -c 120)"
  fi

  sleep 0.25
done

echo "== last headers =="; head -n 80 "$tmp/hdr.txt" || true
echo "== last body =="; head -n 80 "$tmp/body.txt" || true
err "not stable JSON after polling"
