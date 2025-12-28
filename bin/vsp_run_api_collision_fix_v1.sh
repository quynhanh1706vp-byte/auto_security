#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TS="$(date +%Y%m%d_%H%M%S)"
echo "[ROOT] $(pwd)"
echo "[TS]   $TS"

backup() { [ -f "$1" ] && cp "$1" "$1.bak_collision_${TS}" && echo "[BACKUP] $1.bak_collision_${TS}"; }

# 1) Patch blueprint routes to /api/vsp/run_v1 and /api/vsp/run_status_v1/<req_id>
PYF="run_api/vsp_run_api_v1.py"
if [ ! -f "$PYF" ]; then
  echo "[ERR] missing $PYF (run the previous enable script first)"; exit 1
fi
backup "$PYF"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="replace").replace("\r\n","\n").replace("\r","\n")

# Change only route strings (avoid global replace on comments)
txt2 = txt
txt2 = re.sub(r'@bp_vsp_run_api_v1\.route\(\s*["\']/api/vsp/run["\']\s*,\s*methods=\[\s*["\']POST["\']\s*\]\s*\)',
              '@bp_vsp_run_api_v1.route("/api/vsp/run_v1", methods=["POST"])', txt2)
txt2 = re.sub(r'@bp_vsp_run_api_v1\.route\(\s*["\']/api/vsp/run_status/<req_id>["\']\s*,\s*methods=\[\s*["\']GET["\']\s*\]\s*\)',
              '@bp_vsp_run_api_v1.route("/api/vsp/run_status_v1/<req_id>", methods=["GET"])', txt2)

if txt2 == txt:
  # fallback: simple replace if decorator formatting differs
  txt2 = txt2.replace('"/api/vsp/run"', '"/api/vsp/run_v1"')
  txt2 = txt2.replace("'/api/vsp/run'", "'/api/vsp/run_v1'")
  txt2 = txt2.replace('"/api/vsp/run_status/<req_id>"', '"/api/vsp/run_status_v1/<req_id>"')
  txt2 = txt2.replace("'/api/vsp/run_status/<req_id>'", "'/api/vsp/run_status_v1/<req_id>'")

p.write_text(txt2, encoding="utf-8")
print("[OK] patched run_api routes to *_v1")
PY

python3 -m py_compile "$PYF"
echo "[OK] $PYF syntax OK"

# 2) Patch commercial panel to call *_v1 endpoints
JSF="static/js/vsp_runs_commercial_panel_v1.js"
if [ ! -f "$JSF" ]; then
  echo "[ERR] missing $JSF"; exit 1
fi
backup "$JSF"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_runs_commercial_panel_v1.js")
txt = p.read_text(encoding="utf-8", errors="replace")

# Replace only fetch URLs for run + status
txt = txt.replace("fetch('/api/vsp/run',", "fetch('/api/vsp/run_v1',")
txt = txt.replace("fetch(\"/api/vsp/run\",", "fetch(\"/api/vsp/run_v1\",")
txt = re.sub(r"fetch\('/api/vsp/run_status/'", "fetch('/api/vsp/run_status_v1/'", txt)
txt = re.sub(r'fetch\("/api/vsp/run_status/"', 'fetch("/api/vsp/run_status_v1/"', txt)

p.write_text(txt, encoding="utf-8")
print("[OK] patched commercial panel to use /api/vsp/run_v1 + /api/vsp/run_status_v1")
PY

# 3) Ensure blueprint is registered in vsp_demo_app.py (best-effort)
APP="vsp_demo_app.py"
if [ -f "$APP" ]; then
  backup "$APP"
  python3 - << 'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="replace").replace("\r\n","\n").replace("\r","\n")

if "VSP_RUN_API_BLUEPRINT_V1" not in txt:
    m = re.search(r'(?m)^\s*app\s*=\s*Flask\(.+\)\s*$', txt)
    inject = r'''

# === VSP_RUN_API_BLUEPRINT_V1 ===
try:
    from run_api.vsp_run_api_v1 import bp_vsp_run_api_v1
    app.register_blueprint(bp_vsp_run_api_v1)
    print("[VSP_RUN_API] registered blueprint: /api/vsp/run_v1 + /api/vsp/run_status_v1/<REQ_ID>")
except Exception as e:
    print("[VSP_RUN_API] WARN: cannot register run api blueprint:", e)
# === END VSP_RUN_API_BLUEPRINT_V1 ===
'''
    if m:
        pos = m.end()
        txt = txt[:pos] + inject + txt[pos:]
    else:
        txt += "\n" + inject
    p.write_text(txt, encoding="utf-8")
    print("[OK] injected blueprint register block into vsp_demo_app.py")
else:
    print("[SKIP] vsp_demo_app.py already has VSP_RUN_API_BLUEPRINT_V1")
PY
  python3 -m py_compile "$APP"
  echo "[OK] $APP syntax OK"
else
  echo "[WARN] vsp_demo_app.py not found (skip wiring)"
fi

# 4) Restart UI
pkill -f vsp_demo_app.py || true
mkdir -p out_ci
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1
echo "[OK] restarted UI"
tail -n 20 out_ci/ui_8910.log || true

# 5) Quick smoke checks
echo
echo "== SMOKE: endpoints =="
curl -s -I http://localhost:8910/api/vsp/run_v1 | head -n 1 || true
curl -s http://localhost:8910/api/vsp/runs_index_v3_fs?limit=1 | head -c 200; echo

cat << 'TXT'

======================
[E2E TEST - CURL (SAFE)]
======================

REQ_ID="$(curl -s -X POST http://localhost:8910/api/vsp/run_v1 \
  -H 'Content-Type: application/json' \
  -d '{"mode":"local","profile":"FULL_EXT","target_type":"path","target":"/home/test/Data/SECURITY-10-10-v4","max_critical":0,"max_high":10}' \
  | jq -r '.req_id')"
echo "REQ_ID=$REQ_ID"

# Poll until final=true
while true; do
  j="$(curl -s "http://localhost:8910/api/vsp/run_status_v1/$REQ_ID")"
  echo "$j" | jq '{req_id,status,final,gate,exit_code,ci_run_dir,vsp_run_id,flag,sync}'
  fin="$(echo "$j" | jq -r '.final')"
  if [ "$fin" = "true" ]; then
    echo "=== FINAL TAIL (last 80 lines) ==="
    echo "$j" | jq -r '.tail' | tail -n 80
    break
  fi
  sleep 2
done

======================
[UI TEST]
======================
Open: http://localhost:8910/#runs
- Run Scan Now → live tail → DONE/FAILED
TXT

