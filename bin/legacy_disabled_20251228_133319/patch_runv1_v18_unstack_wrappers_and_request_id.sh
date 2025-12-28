#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

UIF="vsp_demo_app.py"
RAF="run_api/vsp_run_api_v1.py"

[ -f "$UIF" ] || { echo "[ERR] missing $UIF"; exit 1; }
[ -f "$RAF" ] || { echo "[ERR] missing $RAF"; exit 1; }

echo "== [0] stop service =="
systemctl --user stop vsp-ui-8910.service 2>/dev/null || true
sleep 1

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$UIF" "$UIF.bak_v18_${TS}"
cp -f "$RAF" "$RAF.bak_v18_${TS}"
echo "[BACKUP] $UIF.bak_v18_${TS}"
echo "[BACKUP] $RAF.bak_v18_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

# ---- (1) Unstack wrappers in vsp_demo_app.py: remove V14/V15 blocks only (keep V16) ----
p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# Remove only blocks that have proper END marker (safe delete)
patterns = [
  r"(?ms)\n?\s*# === VSP_RUN_V1_.*?V14.*? ===.*?# === END VSP_RUN_V1_.*?V14.*? ===\s*\n?",
  r"(?ms)\n?\s*# === VSP_RUN_V1_.*?V15.*? ===.*?# === END VSP_RUN_V1_.*?V15.*? ===\s*\n?",
  r"(?ms)\n?\s*# === VSP_RUNV1_V14.*? ===.*?# === END VSP_RUNV1_V14.*? ===\s*\n?",
  r"(?ms)\n?\s*# === VSP_RUNV1_V15.*? ===.*?# === END VSP_RUNV1_V15.*? ===\s*\n?",
]

rm = 0
for pat in patterns:
  t2, n = re.subn(pat, "\n", t)
  if n:
    rm += n
    t = t2

print("[UI] removed wrapper blocks:", rm)
p.write_text(t, encoding="utf-8")

# ---- (2) Patch run_api/vsp_run_api_v1.py: ensure success returns request_id + req_id ----
p = Path("run_api/vsp_run_api_v1.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# Must have def run_v1(
if not re.search(r"(?m)^\s*def\s+run_v1\s*\(", t):
  raise SystemExit("[ERR] run_v1 not found in run_api/vsp_run_api_v1.py")

# (2a) Success response: add request_id
# Replace common exact form if present
t_new, n1 = re.subn(
  r'__resp\s*=\s*jsonify\(\{\s*"ok"\s*:\s*True\s*,\s*"req_id"\s*:\s*req_id\s*,\s*"status_url"\s*:\s*f"/api/vsp/run_status_v1/\{req_id\}"\s*\}\)',
  '__resp = jsonify({"ok": True, "request_id": req_id, "req_id": req_id, "status_url": f"/api/vsp/run_status_v1/{req_id}"})',
  t
)

# If not matched, do a softer patch: find a jsonify({... ok True ... req_id ... status_url ...}) line
if n1 == 0:
  t_new2, n1b = re.subn(
    r'__resp\s*=\s*jsonify\(\{\s*"ok"\s*:\s*True\s*,\s*"req_id"\s*:\s*req_id\s*,\s*"status_url"\s*:\s*[^}]+\}\)',
    '__resp = jsonify({"ok": True, "request_id": req_id, "req_id": req_id, "status_url": f"/api/vsp/run_status_v1/{req_id}"})',
    t
  )
  t_new = t_new2
  n1 = n1b

# (2b) Spawn error path: ensure st carries request_id before jsonify(st)
# Insert before "__resp = jsonify(st)" only inside run_v1 block
# (safe-ish: add only if "jsonify(st)" exists)
if "jsonify(st)" in t_new and '"request_id"' not in t_new:
  t_new = t_new.replace(
    "__resp = jsonify(st)",
    "st.setdefault('request_id', req_id)\n    st.setdefault('req_id', req_id)\n    __resp = jsonify(st)",
    1
  )

p.write_text(t_new, encoding="utf-8")
print("[RUN_API] patched success request_id:", n1)

PY

echo "== [3] py_compile =="
python3 -m py_compile vsp_demo_app.py
python3 -m py_compile run_api/vsp_run_api_v1.py
echo "[OK] py_compile OK"

echo "== [4] restart service (kill stray pid holding 8910, then start) =="
PORT=8910
PIDS="$(ss -ltnp | awk -v p=":$PORT" '$4 ~ p {print $0}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u)"
for pid in $PIDS; do echo "[KILL] $pid"; kill -9 "$pid" 2>/dev/null || true; done
sleep 1

systemctl --user start vsp-ui-8910.service
sleep 1

echo "== [5] verify =="
echo "-- healthz --"
curl -sS -i http://127.0.0.1:8910/healthz | sed -n '1,80p'
echo
echo "-- run_v1 {} --"
curl -sS -i -X POST http://127.0.0.1:8910/api/vsp/run_v1 -H 'Content-Type: application/json' -d '{}' | sed -n '1,140p'
echo
echo "-- body --"
curl -sS -X POST http://127.0.0.1:8910/api/vsp/run_v1 -H 'Content-Type: application/json' -d '{}' | python3 - <<'PY'
import sys, json
s=sys.stdin.read().strip()
try:
  j=json.loads(s)
  print(json.dumps({k:j.get(k) for k in ["ok","request_id","req_id","status_url"]}, ensure_ascii=False))
except Exception as e:
  print(s)
PY

