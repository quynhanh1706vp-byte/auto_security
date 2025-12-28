#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_VSP5_ANCHOR_INJECT_AFTERREQ_SAFE_V2"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_anchorinj_${TS}"
echo "[BACKUP] ${F}.bak_anchorinj_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, re, textwrap

MARK="VSP_P2_VSP5_ANCHOR_INJECT_AFTERREQ_SAFE_V2"
p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")

if MARK in s:
    print("[OK] already patched:", MARK)
    py_compile.compile(str(p), doraise=True)
    raise SystemExit(0)

block = textwrap.dedent(f"""
# ===================== {MARK} =====================
# Guarantee anchor exists on /vsp5 HTML (only inject when missing; only text/html)
def __vsp_pick_flask_app_for_afterreq__():
    try:
        g = globals()
        for _k, _v in list(g.items()):
            if hasattr(_v, "after_request") and hasattr(_v, "route") and hasattr(_v, "url_map"):
                return _v
    except Exception:
        pass
    return None

def __vsp_inject_vsp5_anchor__(b: bytes) -> bytes:
    try:
        if b is None:
            return b
        if b'id="vsp-dashboard-main"' in b:
            return b
        ins = b'\\n<div id="vsp-dashboard-main"></div>\\n'
        m = re.search(br'<body[^>]*>', b, re.I)
        if m:
            return b[:m.end()] + ins + b[m.end():]
        m = re.search(br'<html[^>]*>', b, re.I)
        if m:
            return b[:m.end()] + b'\\n<body>\\n' + ins + b'\\n' + b[m.end():]
        return ins + b
    except Exception:
        return b

__vsp__app_for_afterreq = __vsp_pick_flask_app_for_afterreq__()
if __vsp__app_for_afterreq is not None:
    try:
        from flask import request as __vsp_req
    except Exception:
        __vsp_req = None

    @__vsp__app_for_afterreq.after_request
    def __vsp_afterreq_inject_anchor__(resp):
        try:
            if __vsp_req is None:
                return resp
            if __vsp_req.path != "/vsp5":
                return resp
            ct = (resp.headers.get("Content-Type") or "").lower()
            if ("text/html" not in ct) and (ct != ""):
                return resp
            data = resp.get_data()  # bytes
            new = __vsp_inject_vsp5_anchor__(data)
            if new != data:
                resp.set_data(new)
                try:
                    resp.headers["Content-Length"] = str(len(new))
                except Exception:
                    pass
        except Exception:
            pass
        return resp

    print("[{MARK}] installed after_request injector for /vsp5")
else:
    print("[{MARK}] WARN: no Flask app found for after_request injector")
# ===================== /{MARK} =====================
""").strip("\n") + "\n"

# Append near end (safe)
s2 = s + "\n" + block
p.write_text(s2, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] appended + py_compile OK:", MARK)
PY

echo "== restart service =="
sudo systemctl daemon-reload || true
sudo systemctl restart "$SVC"
sleep 0.6
sudo systemctl status "$SVC" -l --no-pager || true

echo "== verify live html anchor =="
curl -sS "$BASE/vsp5" | grep -n 'id="vsp-dashboard-main"' | head -n 3 || echo "MISSING"

echo "== note =="
echo "[DONE] If browser still old DOM: Ctrl+Shift+R on /vsp5"
