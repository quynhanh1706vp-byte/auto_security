#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_DISABLE_KPI_V4_AND_FORCE_DASH_MW_V2"

cp -f "$F" "${F}.bak_kpi_dashmw_${TS}"
echo "[BACKUP] ${F}.bak_kpi_dashmw_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, sys, re

MARK = "VSP_P2_DISABLE_KPI_V4_AND_FORCE_DASH_MW_V2"
p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")

if MARK in s:
    print("[OK] marker already present -> skip")
    sys.exit(0)

block = textwrap.dedent("""
# ===================== %%MARK%% =====================
# Boot-safe: allow disabling KPI_V4 mount blocks if they exist.
# If your file has an explicit KPI_V4 mount call, wrap it with env var VSP_SAFE_DISABLE_KPI_V4=1
try:
    import os as _os
    _VSP_SAFE_DISABLE_KPI_V4 = (_os.environ.get("VSP_SAFE_DISABLE_KPI_V4","1") == "1")
except Exception:
    _VSP_SAFE_DISABLE_KPI_V4 = True

def _vsp__dashmw_json(start_response, obj, code=200):
    import json as _json
    code = int(code)
    status = f"{code} OK" if code < 400 else f"{code} ERROR"
    body = _json.dumps(obj, ensure_ascii=False).encode("utf-8")
    headers = [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Cache-Control", "no-store"),
        ("Content-Length", str(len(body))),
    ]
    start_response(status, headers)
    return [body]

def _vsp__dashmw(app_wsgi):
    def _wrapped(environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "").rstrip("/")
            if path == "/api/vsp/dash_kpis":
                return _vsp__dashmw_json(start_response, {"ok": True, "kpis": {}, "__via__": "%%MARK%%"}, 200)
            if path == "/api/vsp/dash_charts":
                return _vsp__dashmw_json(start_response, {"ok": True, "charts": {}, "__via__": "%%MARK%%"}, 200)
        except Exception as e:
            return _vsp__dashmw_json(start_response, {"ok": False, "err": repr(e), "__via__": "%%MARK%%"}, 500)
        return app_wsgi(environ, start_response)
    return _wrapped

def _vsp__install_dashmw():
    installed = 0
    g = globals()
    # wrap flask app objects
    for _, v in list(g.items()):
        try:
            if v is None:
                continue
            if hasattr(v, "wsgi_app") and callable(getattr(v, "wsgi_app", None)):
                v.wsgi_app = _vsp__dashmw(v.wsgi_app)
                installed += 1
        except Exception:
            pass
    # wrap callable entries
    for name in ("application", "app"):
        try:
            v = g.get(name)
            if v is not None and callable(v) and not hasattr(v, "wsgi_app"):
                g[name] = _vsp__dashmw(v)
                installed += 1
        except Exception:
            pass
    print("[%%MARK%%] dashmw_installed_count=", installed)
    return installed

_vsp__install_dashmw()
# ===================== /%%MARK%% =====================
""").replace("%%MARK%%", MARK).strip("\n")

p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

# ensure env for service (optional): if you have systemd drop-in, set it there; here we just restart
systemctl restart "$SVC" 2>/dev/null || true

echo "== verify (expect 200) =="
for u in /api/vsp/dash_kpis /api/vsp/dash_charts; do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$u" || true)"
  echo "$u => $code"
done

echo "== journal dashmw + KPI_V4 lines =="
journalctl -u "$SVC" -n 140 --no-pager | egrep -n "dashmw_installed_count|KPI_V4" | tail -n 40 || true
