#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed; need grep

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "== [1] snapshot current broken wsgi =="
cp -f "$W" "${W}.bak_broken_${TS}"
echo "[SNAPSHOT] ${W}.bak_broken_${TS}"

echo "== [2] find latest compiling backup and restore =="
python3 - <<'PY'
from pathlib import Path
import py_compile, time, shutil, re, sys

w = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)

def ok_compile(p: Path) -> bool:
    try:
        py_compile.compile(str(p), doraise=True)
        return True
    except Exception:
        return False

good = None
for p in baks:
    if ok_compile(p):
        good = p
        break

if good is None:
    print("[ERR] cannot find any compiling backup wsgi_vsp_ui_gateway.py.bak_*")
    sys.exit(2)

shutil.copy2(good, w)
print(f"[OK] restored wsgi from: {good}")
PY

echo "== [3] append safe v3->v2 proxy endpoint (HTTP proxy, no handler coupling) =="
python3 - <<'PY'
from pathlib import Path
import re, textwrap

W = Path("wsgi_vsp_ui_gateway.py")
s = W.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P2_KPI_V3_PROXY_HTTP_V1"

# remove any previous broken proxy blocks we might have appended
s = re.sub(r'(?s)\n#\s*====================\s*VSP_P2_RUNS_KPI_V3_PROXY_V1.*?\n#\s*====================\s*/VSP_P2_RUNS_KPI_V3_PROXY_V1.*?\n', "\n", s)
s = re.sub(r'(?s)\n#\s*====================\s*VSP_P2_RUNS_KPI_V3_PROXY_V1_APPEND.*?\n#\s*====================\s*/VSP_P2_RUNS_KPI_V3_PROXY_V1_APPEND.*?\n', "\n", s)

if marker in s:
    print("[OK] marker exists; skip append")
else:
    block = r"""
# ===================== VSP_P2_KPI_V3_PROXY_HTTP_V1 =====================
# Goal: never 500 on legacy /api/ui/runs_kpi_v3 calls. Proxy to v2 endpoint.
# This is intentionally implemented as an HTTP proxy to avoid coupling to internal handler names.
try:
    from flask import request, jsonify, Response
except Exception:
    request = None
    jsonify = None
    Response = None

@app.route("/api/ui/runs_kpi_v3")
def vsp_ui_runs_kpi_v3_proxy():
    import time, json
    try:
        import urllib.request, urllib.parse
        days = "30"
        if request is not None:
            days = request.args.get("days", "30")
        qs = urllib.parse.urlencode({"days": str(days)})
        url = f"http://127.0.0.1:8910/api/ui/runs_kpi_v2?{qs}"
        with urllib.request.urlopen(url, timeout=3.0) as r:
            data = r.read()
        if Response is not None:
            return Response(data, mimetype="application/json")
        # fallback
        return (data, 200, {"Content-Type": "application/json"})
    except Exception as e:
        if jsonify is not None:
            return jsonify(ok=False, err=str(e), ts=int(time.time())), 200
        return (json.dumps({"ok": False, "err": str(e), "ts": int(time.time())}), 200, {"Content-Type": "application/json"})
# ===================== /VSP_P2_KPI_V3_PROXY_HTTP_V1 =====================
"""
    s = s.rstrip() + "\n\n" + textwrap.dedent(block).lstrip("\n")
    print("[OK] appended v3->v2 proxy block")

W.write_text(s, encoding="utf-8")
PY

echo "== [4] compile check =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== [5] restart service =="
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.8

echo "== [6] sanity =="
echo "-- v2 --"
curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | head -c 260; echo
echo "-- v3 (proxy) --"
curl -sS "$BASE/api/ui/runs_kpi_v3?days=30" | head -c 260; echo

echo "[DONE] p2_recover_wsgi_then_proxy_kpi_v3_v1"
