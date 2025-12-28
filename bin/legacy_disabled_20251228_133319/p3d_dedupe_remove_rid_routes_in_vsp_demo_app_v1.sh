#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
[ -x "$PY" ] || PY="$(command -v python3)"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_p3d_dedupe_${TS}"
echo "[BACKUP] ${APP}.bak_p3d_dedupe_${TS}"

"$PY" - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) Remove helper blocks injected by earlier patches (keep file clean)
for mark in [
    "VSP_P3_RID_BEST_UNIFY_RIDLATEST_V1",
    "VSP_P3B_FORCE_GATEWAY_RID_LATEST_BEST_V1",
]:
    s = re.sub(
        r'(?s)\n?# === '+re.escape(mark)+r' ===.*?# === END '+re.escape(mark)+r' ===\n?',
        "\n",
        s
    )

# 2) Remove ALL rid_best + rid_latest route blocks from vsp_demo_app.py
# (we will serve them via gateway middleware, so vsp_demo_app must import cleanly)
def drop_route(path: str, text: str) -> tuple[str,int]:
    pat = re.compile(
        r'(?s)^@app\.(?:get|route)\(\s*[\'"]'+re.escape(path)+r'[\'"][^\)]*\)\s*\n'
        r'(?:^@app\..*\n)*'
        r'^def\s+\w+\(.*?\):.*?'
        r'(?=^@app\.|^if\s+__name__\s*==|\Z)',
        re.MULTILINE
    )
    n = 0
    while True:
        m = pat.search(text)
        if not m:
            break
        text = text[:m.start()] + "\n# [P3D] removed route "+path+" (served by gateway middleware)\n" + text[m.end():]
        n += 1
    return text, n

s, n_best   = drop_route("/api/vsp/rid_best", s)
s, n_latest = drop_route("/api/vsp/rid_latest", s)

p.write_text(s, encoding="utf-8")
print(f"[OK] removed rid_best blocks: {n_best}")
print(f"[OK] removed rid_latest blocks: {n_latest}")
PY

# 3) Compile check
"$PY" -m py_compile "$APP"
echo "[OK] py_compile OK: $APP"

# 4) Import check gateway (must succeed now)
"$PY" -c "import wsgi_vsp_ui_gateway; print('IMPORT_OK')"
echo "[OK] gateway import OK"

# 5) Restart service
sudo systemctl restart "${SVC}"
sleep 0.5
sudo systemctl is-active --quiet "${SVC}" && echo "[OK] service active" || { echo "[ERR] service not active"; sudo systemctl status "${SVC}" --no-pager | sed -n '1,160p'; exit 3; }

# 6) Smoke: rid_best / rid_latest must come from gateway middleware now
echo "== [SMOKE] rid_best / rid_latest =="
curl -fsS "$BASE/api/vsp/rid_best"   | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("rid_best:", j.get("rid"))'
curl -fsS "$BASE/api/vsp/rid_latest" | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("rid_latest:", j.get("rid"), "mode:", j.get("mode"))'

echo "== [SMOKE] run_file_allow findings_unified.json (rid_latest) =="
RID_L="$(curl -fsS "$BASE/api/vsp/rid_latest" | "$PY" -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
if [ -n "$RID_L" ]; then
  curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID_L&path=findings_unified.json&limit=5" \
    | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("from=",j.get("from"),"len=",len(j.get("findings") or []))'
fi

echo "[DONE] p3d_dedupe_remove_rid_routes_in_vsp_demo_app_v1"
