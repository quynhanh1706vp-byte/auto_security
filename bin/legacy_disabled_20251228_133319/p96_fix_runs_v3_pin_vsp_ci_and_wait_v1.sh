#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need curl

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_p96_runsv3_${TS}"
echo "[BACKUP] ${APP}.bak_p96_runsv3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P94_RUNS_V3_JSON_CACHE_CI_V1"
if marker not in s:
    print("[ERR] P94 block not found in vsp_demo_app.py")
    sys.exit(2)

# 1) change: limit -> limit_req + pin newest VSP_CI into first page
# Replace inside vsp_p94_api_ui_runs_v3()
# - limit = int(request.args.get("limit","200"))
s2=s

# Make limit_req
s2 = re.sub(r'limit\s*=\s*int\(request\.args\.get\("limit",\s*"200"\)\)',
            'limit_req = int(request.args.get("limit","200"))\n        limit_req = max(1, min(limit_req, 500))',
            s2, count=1)

# Cache key uses limit_req now
s2 = re.sub(r'key\s*=\s*f"ci=\{1 if include_ci else 0\}&limit=\{limit\}"',
            'key = f"ci={1 if include_ci else 0}&limit={limit_req}"',
            s2, count=1)

# Fetch wider list (up to 5000) then slice after pin
s2 = re.sub(r'items\s*=\s*_vsp_p94_list_runs_dirs\(include_ci=include_ci,\s*limit=limit\)',
            'items_all = _vsp_p94_list_runs_dirs(include_ci=include_ci, limit=5000)\n\n        # [P96] pin newest VSP_CI into first page to avoid RID mismatch when many RUN_ are newer\n        items = items_all\n        vsp_ci = [x for x in items_all if str(x.get("rid","")).startswith("VSP_CI_")]\n        if vsp_ci:\n            newest_ci = vsp_ci[0]\n            rest = [x for x in items_all if x is not newest_ci]\n            items = [newest_ci] + rest\n\n        items = items[:limit_req]',
            s2, count=1)

# Fix total=len(items) if still refers to items_all
s2 = re.sub(r'"total"\s*:\s*len\(items\)',
            '"total": len(items)',
            s2)

if s2 == s:
    print("[WARN] No changes applied (patterns may differ).")
else:
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched P94 runs_v3 to pin newest VSP_CI and slice after pin (P96)")
PY

echo "== [P96] py_compile =="
python3 -m py_compile "$APP"

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
if command -v systemctl >/dev/null 2>&1; then
  echo "== [P96] daemon-reload + restart =="
  sudo systemctl daemon-reload
  sudo systemctl restart "$SVC"
  sudo systemctl is-active "$SVC" --quiet && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }
fi

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [P96] wait port 8910 =="
ok=0
for i in $(seq 1 80); do
  if curl -fsS --max-time 1 "$BASE/runs" -o /dev/null; then ok=1; break; fi
  sleep 0.1
done
[ "$ok" -eq 1 ] || { echo "[ERR] UI not reachable at $BASE"; exit 2; }

echo "== [P96] smoke runs_v3 includes VSP_CI in first page =="
curl -fsS "$BASE/api/ui/runs_v3?limit=50&include_ci=1" -o /tmp/runs_v3.json
python3 - <<'PY'
import json
s=open("/tmp/runs_v3.json","r",encoding="utf-8",errors="replace").read()
j=json.loads(s)
txt=str(j)
print("ok=", j.get("ok"), "items=", len(j.get("items",[])), "has_VSP_CI=", ("VSP_CI_" in txt))
PY

echo "[OK] P96 done"
