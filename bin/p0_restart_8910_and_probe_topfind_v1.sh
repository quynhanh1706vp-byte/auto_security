#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PORT="8910"
LOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.nohup.log"
mkdir -p "$(dirname "$LOG")"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need grep; need awk; need sed; need head; need python3

echo "== [0] quick reachability before restart =="
curl -fsS --connect-timeout 1 --max-time 3 "$BASE/api/vsp/rid_latest" >/dev/null 2>&1 \
  && echo "[OK] API reachable now" \
  || echo "[WARN] API not reachable / slow now"

echo "== [1] Find systemd service candidates (8910/vsp-ui) =="
cands="$(systemctl list-units --type=service --all 2>/dev/null \
  | awk 'tolower($0) ~ /(8910|vsp[-_ ]?ui|vsp ui)/ {print $1}' \
  | sed '/^$/d' | sort -u || true)"

if [ -n "${cands}" ]; then
  echo "[INFO] candidates:"
  echo "$cands" | sed 's/^/  - /'
  echo "== [2] Restart candidates =="
  while read -r svc; do
    [ -n "$svc" ] || continue
    echo "[DO] sudo systemctl restart $svc"
    sudo systemctl restart "$svc" || true
  done <<<"$cands"
else
  echo "[WARN] no systemd service matched. Will try process-based restart."
fi

echo "== [3] If still not reachable: process-based restart (best-effort) =="
if ! curl -fsS --connect-timeout 1 --max-time 3 "$BASE/api/vsp/rid_latest" >/dev/null 2>&1; then
  echo "[INFO] killing listeners on :$PORT (if any)"
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp 2>/dev/null | grep -E ":$PORT\b" || true
  fi

  # try to stop common runners
  pkill -f "gunicorn.*$PORT" 2>/dev/null || true
  pkill -f "wsgi_vsp_ui_gateway" 2>/dev/null || true
  pkill -f "vsp_demo_app\.py" 2>/dev/null || true

  # start via gunicorn if possible (preferred for wsgi gateway)
  PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python3"
  [ -x "$PY" ] || PY="$(command -v python3)"

  GUNI="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn"
  if [ ! -x "$GUNI" ]; then
    GUNI="$(command -v gunicorn 2>/dev/null || true)"
  fi

  if [ -n "${GUNI}" ] && [ -x "${GUNI}" ]; then
    echo "[DO] start gunicorn on 127.0.0.1:$PORT (log: $LOG)"
    nohup "$GUNI" -w 2 -b "127.0.0.1:$PORT" "wsgi_vsp_ui_gateway:app" >"$LOG" 2>&1 &
    sleep 0.8
  else
    echo "[WARN] gunicorn not found. fallback: run vsp_demo_app.py (log: $LOG)"
    nohup "$PY" vsp_demo_app.py >"$LOG" 2>&1 &
    sleep 0.8
  fi
fi

echo "== [4] Probe with sane timeouts (top_findings can be heavy) =="
echo "-- rid_latest --"
curl -fsS --connect-timeout 2 --max-time 6 "$BASE/api/vsp/rid_latest" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"rid=",j.get("rid"),"via=",j.get("via"))'

echo "-- top_findings (max-time 25s) --"
curl -fsS --connect-timeout 2 --max-time 25 "$BASE/api/vsp/top_findings_v1?limit=5" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("rid=",j.get("rid"),"rid_used=",j.get("rid_used"),"rid_raw=",j.get("rid_raw"),"items=",len(j.get("items") or []),"marker=",j.get("marker"))'

echo "-- trend --"
curl -fsS --connect-timeout 2 --max-time 10 "$BASE/api/vsp/trend_v1" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); pts=j.get("points") or []; print("ok=",j.get("ok"),"points=",len(pts),"first=", (pts[0] if pts else None))'

echo "== [5] If anything still fails, show last 80 lines of nohup log =="
tail -n 80 "$LOG" 2>/dev/null || true

echo "[DONE] Now Ctrl+Shift+R on /vsp5, check Console red errors."
