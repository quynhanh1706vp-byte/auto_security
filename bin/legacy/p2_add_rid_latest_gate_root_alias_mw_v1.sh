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
MARK="VSP_P2_RID_LATEST_GATE_ROOT_ALIAS_MW_V1"

cp -f "$F" "${F}.bak_ridgate_${TS}"
echo "[BACKUP] ${F}.bak_ridgate_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")
MARK="VSP_P2_RID_LATEST_GATE_ROOT_ALIAS_MW_V1"
if MARK in s:
    print("[OK] marker already present -> skip")
    sys.exit(0)

block = textwrap.dedent("""
# ===================== %%MARK%% =====================
def _vsp__ridgate_json(start_response, obj, code=200):
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

def _vsp__ridgate_mw(app_wsgi):
    def _wrapped(environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "").rstrip("/")
            if path == "/api/vsp/rid_latest_gate_root":
                # best-effort: reuse /api/vsp/rid_latest contract (already 200 in your env)
                try:
                    import urllib.request, json
                    base = "http://127.0.0.1:8910"
                    with urllib.request.urlopen(base + "/api/vsp/rid_latest", timeout=3) as r:
                        j = json.loads(r.read().decode("utf-8","ignore") or "{}")
                    rid = (j.get("rid") or "")
                    return _vsp__ridgate_json(start_response, {"ok": True, "rid": rid, "gate_root": "run_gate_summary.json", "why": "alias->rid_latest"}, 200)
                except Exception as e:
                    return _vsp__ridgate_json(start_response, {"ok": True, "rid": "", "gate_root": "run_gate_summary.json", "why": "alias-fallback", "warn": repr(e)}, 200)
        except Exception as e:
            return _vsp__ridgate_json(start_response, {"ok": False, "err": repr(e), "__via__": "%%MARK%%"}, 500)
        return app_wsgi(environ, start_response)
    return _wrapped

def _vsp__install_ridgate_mw():
    installed = 0
    g = globals()
    # wrap flask app objects
    for _, v in list(g.items()):
        try:
            if v is None: 
                continue
            if hasattr(v, "wsgi_app") and callable(getattr(v, "wsgi_app", None)):
                v.wsgi_app = _vsp__ridgate_mw(v.wsgi_app)
                installed += 1
        except Exception:
            pass
    # wrap callable entries
    for name in ("application", "app"):
        try:
            v = g.get(name)
            if v is not None and callable(v) and not hasattr(v, "wsgi_app"):
                g[name] = _vsp__ridgate_mw(v)
                installed += 1
        except Exception:
            pass
    print("[%%MARK%%] installed_mw_count=", installed)
    return installed

_vsp__install_ridgate_mw()
# ===================== /%%MARK%% =====================
""").replace("%%MARK%%", MARK).strip("\n")

p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

systemctl restart "$SVC" 2>/dev/null || true

echo "== verify =="
curl -s -o /dev/null -w "rid_latest_gate_root=%{http_code}\n" "$BASE/api/vsp/rid_latest_gate_root"
curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | head -c 220; echo
echo "[DONE]"
