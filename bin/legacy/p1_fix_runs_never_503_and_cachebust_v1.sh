#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need jq

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

# --- 1) Patch gateway: never return 5xx for /api/vsp/runs (commercial degrade) ---
cp -f "$GW" "${GW}.bak_runs_never503_${TS}"
echo "[BACKUP] ${GW}.bak_runs_never503_${TS}"

python3 - <<PY
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_RUNS_NEVER_503_MW_V1"
if MARK in s:
    print("[OK] gateway mw already present")
    raise SystemExit(0)

# detect flask variable name
m = re.search(r'^(\\s*)(application|app)\\s*=\\s*Flask\\(', s, flags=re.M)
var = m.group(2) if m else "application"

# insert right after Flask() line
ins = f"""
# {MARK} {var}
@{var}.after_request
def _vsp_p1_runs_never_503(resp):
    try:
        # local import: avoid touching global imports
        from flask import request, jsonify
        if request.path == "/api/vsp/runs":
            code = getattr(resp, "status_code", 200) if resp is not None else 500
            if code >= 500:
                payload = {{
                    "ok": False,
                    "degraded": True,
                    "rid_latest": None,
                    "items": [],
                    "error": "runs endpoint degraded (auto-mapped from %s)" % code
                }}
                r = jsonify(payload)
                r.status_code = 200
                r.headers["X-VSP-RUNS-DEGRADED"] = "1"
                r.headers["Cache-Control"] = "no-store"
                return r
    except Exception:
        pass
    return resp
"""

# find insertion point
if m:
    line_start = m.start()
    # insert after end of that line
    line_end = s.find("\n", m.end())
    if line_end == -1: line_end = len(s)
    s2 = s[:line_end+1] + ins + s[line_end+1:]
else:
    # fallback: append at end
    s2 = s + "\n" + ins

p.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK, "var=", var)
PY

# --- 2) Fix templates cache-bust bootjs: exactly one ?v=TS ---
python3 - <<PY
from pathlib import Path
import re

TS="${TS}"
tpls=[
  Path("templates/vsp_5tabs_enterprise_v2.html"),
  Path("templates/vsp_dashboard_2025.html"),
  Path("templates/vsp_data_source_v1.html"),
  Path("templates/vsp_rule_overrides_v1.html"),
]
js_pat = re.compile(r'/static/js/vsp_p1_page_boot_v1\\.js(?:\\?v=[^"]*)?')
for t in tpls:
    if not t.exists():
        continue
    s=t.read_text(encoding="utf-8", errors="replace")
    s2=js_pat.sub(f'/static/js/vsp_p1_page_boot_v1.js?v={TS}', s)
    # also fix accidental double ?v cases
    s2=s2.replace(f'.js?v={TS}?v=', f'.js?v={TS}')
    if s2!=s:
        t.write_text(s2, encoding="utf-8")
        print("[OK] template fixed:", t.name)
PY

# --- 3) Restart UI (prefer your known runner) ---
if [ -x bin/p1_ui_8910_single_owner_start_v2.sh ]; then
  echo "[INFO] restart via bin/p1_ui_8910_single_owner_start_v2.sh"
  bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null 2>&1 || true
else
  echo "[WARN] missing bin/p1_ui_8910_single_owner_start_v2.sh; manual restart needed"
fi

# --- 4) Verify: runs never 5xx (loop) ---
BASE="${BASE:-http://127.0.0.1:8910}"
echo "== verify /api/vsp/runs?limit=1 x20 =="
for i in $(seq 1 20); do
  code="$(curl -sS -o /tmp/runs.json -w '%{http_code}' "$BASE/api/vsp/runs?limit=1" || true)"
  ok="$(jq -r '.ok // empty' /tmp/runs.json 2>/dev/null || true)"
  deg="$(jq -r '.degraded // empty' /tmp/runs.json 2>/dev/null || true)"
  printf "%02d) http=%s ok=%s degraded=%s\n" "$i" "$code" "$ok" "$deg"
  sleep 0.15
done

echo "[NEXT] Mở Incognito /vsp5 (khuyến nghị) hoặc Ctrl+F5. Nếu trước đó bị 503, giờ UI sẽ không còn chết vì 5xx nữa."
