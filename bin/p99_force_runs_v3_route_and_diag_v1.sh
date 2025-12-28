#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need sed; need grep; need curl

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_p99_${TS}"
echo "[BACKUP] ${APP}.bak_p99_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# Must have P94 handler (you added earlier)
if "def vsp_p94_api_ui_runs_v3" not in s:
    raise SystemExit("[ERR] P94 handler not found (def vsp_p94_api_ui_runs_v3).")

marker="VSP_P99_FORCE_RUNS_V3_ROUTE_V1"
if marker in s:
    print("[OK] P99 already present")
    raise SystemExit(0)

patch = r'''
# VSP_P99_FORCE_RUNS_V3_ROUTE_V1
# Force /api/ui/runs_v3 to always use vsp_p94_api_ui_runs_v3 (avoid route conflict / legacy handlers).
try:
    _VSP_P99_KEEP = "vsp_p94_api_ui_runs_v3"
    _fn = globals().get(_VSP_P99_KEEP)
    if _fn is None:
        raise RuntimeError("P94 function missing in globals()")
    # Re-point ALL endpoints bound to /api/ui/runs_v3 to our handler
    for _r in list(app.url_map.iter_rules()):
        if _r.rule == "/api/ui/runs_v3" and ("GET" in getattr(_r, "methods", set())):
            try:
                app.view_functions[_r.endpoint] = _fn
            except Exception:
                pass
    # Also prune duplicate rules to reduce ambiguity (keep only endpoint name = _VSP_P99_KEEP)
    _to_remove=[]
    for _r in list(app.url_map.iter_rules()):
        if _r.rule == "/api/ui/runs_v3" and ("GET" in getattr(_r, "methods", set())) and _r.endpoint != _VSP_P99_KEEP:
            _to_remove.append(_r)
    for _r in _to_remove:
        try:
            if _r in app.url_map._rules:
                app.url_map._rules.remove(_r)
            lst = app.url_map._rules_by_endpoint.get(_r.endpoint)
            if lst and _r in lst:
                lst.remove(_r)
            if lst is not None and len(lst)==0:
                app.url_map._rules_by_endpoint.pop(_r.endpoint, None)
        except Exception:
            pass
except Exception as _e:
    try:
        print("[VSP_P99] force runs_v3 route failed:", _e)
    except Exception:
        pass
'''
p.write_text(s.rstrip()+"\n\n"+patch+"\n", encoding="utf-8")
print("[OK] appended P99 force-route block")
PY

echo "== [P99] py_compile =="
python3 -m py_compile "$APP"

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

if command -v systemctl >/dev/null 2>&1; then
  echo "== [P99] daemon-reload + restart =="
  sudo systemctl daemon-reload
  sudo systemctl restart "$SVC"
  sudo systemctl is-active "$SVC" --quiet && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }
fi

# Wait port up (avoid the earlier connect-refused race)
echo "== [P99] wait UI up =="
ok=0
for i in $(seq 1 120); do
  if curl -fsS --max-time 1 "$BASE/runs" -o /dev/null; then ok=1; break; fi
  sleep 0.1
done
[ "$ok" -eq 1 ] || { echo "[ERR] UI not reachable at $BASE"; exit 2; }

OUT="out_ci"; mkdir -p "$OUT"
EVID="$OUT/p99_diag_${TS}"; mkdir -p "$EVID"

echo "== [P99] DIAG: capture raw response for runs_v3 =="
URL="$BASE/api/ui/runs_v3?limit=50&include_ci=1"
curl -sS -D "$EVID/hdr.txt" "$URL" -o "$EVID/body.bin" || true
echo "--- headers head ---"
head -n 30 "$EVID/hdr.txt" || true
echo "--- body head (first 200 bytes) ---"
python3 - <<PY
from pathlib import Path
b=Path("$EVID/body.bin").read_bytes()
print("body_len=", len(b))
print(b[:200])
PY

echo "== [P99] parse JSON from saved body (no pipe break) =="
python3 - <<PY
import json, pathlib
data = pathlib.Path("$EVID/body.bin").read_bytes()
try:
    s = data.decode("utf-8", errors="replace").strip()
    j = json.loads(s)
    txt = str(j)
    print("json_ok=True ok=", j.get("ok"), "items=", len(j.get("items",[])), "has_VSP_CI=", ("VSP_CI_" in txt))
except Exception as e:
    print("json_ok=False err=", e)
PY

echo "[OK] P99 done. Evidence: $EVID"
