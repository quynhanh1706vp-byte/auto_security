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
MARK="VSP_P2_UIV2_WSGI_MW_FORCE200_V1"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_uiv2mw_${TS}"
echo "[BACKUP] ${F}.bak_uiv2mw_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")

MARK="VSP_P2_UIV2_WSGI_MW_FORCE200_V1"
if MARK in s:
    print("[OK] marker already present -> skip")
    sys.exit(0)

block = textwrap.dedent("""
# ===================== %%MARK%% =====================
def _vsp__mw_json(start_response, obj, code=200):
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

def _vsp__mw_read_body(environ):
    try:
        clen = int(environ.get("CONTENT_LENGTH") or "0")
    except Exception:
        clen = 0
    if clen <= 0:
        return b""
    try:
        return environ["wsgi.input"].read(clen) or b""
    except Exception:
        return b""

def _vsp__uiv2_mw(app_wsgi):
    \"\"\"WSGI middleware: intercept UI v2 endpoints before any Flask/routes/if-path logic.\"\"\"
    def _wrapped(environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "")
            # tolerate trailing slash + possible prefixes
            p0 = path.rstrip("/")
            if p0 in ("/api/ui/settings_v2", "/api/ui/rule_overrides_v2"):
                method = (environ.get("REQUEST_METHOD") or "GET").upper()

                from pathlib import Path as _Path
                import json as _json

                d = _Path("ui_state_v1")
                d.mkdir(parents=True, exist_ok=True)

                if p0.endswith("/settings_v2"):
                    f = d / "settings_local.json"
                    default = {"ok": True, "source": "default", "tools": {}, "ui": {}, "notes": "wsgi-mw"}
                else:
                    f = d / "rule_overrides_local.json"
                    default = {"ok": True, "schema": "rules_v1", "rules": [], "notes": "wsgi-mw"}

                if method == "POST":
                    raw = _vsp__mw_read_body(environ)
                    try:
                        payload = _json.loads(raw.decode("utf-8", errors="ignore") or "{}")
                    except Exception:
                        return _vsp__mw_json(start_response, {"ok": False, "err": "invalid json", "__via__": "%%MARK%%"}, 400)
                    try:
                        f.write_text(_json.dumps(payload, ensure_ascii=False, indent=2))
                        return _vsp__mw_json(start_response, {"ok": True, "saved": str(f), "__via__": "%%MARK%%"}, 200)
                    except Exception as e:
                        return _vsp__mw_json(start_response, {"ok": False, "err": repr(e), "__via__": "%%MARK%%"}, 500)

                # GET
                try:
                    if f.exists():
                        txt = (f.read_text(errors="ignore") or "").strip()
                        if txt:
                            return _vsp__mw_json(start_response, _json.loads(txt), 200)
                except Exception:
                    pass
                return _vsp__mw_json(start_response, default, 200)

        except Exception as e:
            return _vsp__mw_json(start_response, {"ok": False, "err": repr(e), "__via__": "%%MARK%%"}, 500)

        return app_wsgi(environ, start_response)
    return _wrapped

def _vsp__install_uiv2_mw():
    installed = 0
    g = globals()

    # 1) Wrap any Flask app objects (have .wsgi_app)
    for k, v in list(g.items()):
        try:
            if v is None: 
                continue
            if hasattr(v, "wsgi_app") and callable(getattr(v, "wsgi_app", None)):
                v.wsgi_app = _vsp__uiv2_mw(v.wsgi_app)
                installed += 1
        except Exception:
            pass

    # 2) Wrap callable WSGI entries (application/app variables)
    for name in ("application", "app"):
        try:
            v = g.get(name)
            if v is not None and callable(v) and not hasattr(v, "wsgi_app"):
                g[name] = _vsp__uiv2_mw(v)
                installed += 1
        except Exception:
            pass

    print("[%%MARK%%] installed_mw_count=", installed)
    return installed

_vsp__install_uiv2_mw()
# ===================== /%%MARK%% =====================
""").replace("%%MARK%%", MARK).strip("\n")

p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || true
fi

echo "== verify endpoints (expect 200) =="
curl -s -o /dev/null -w "settings_v2=%{http_code}\n" "$BASE/api/ui/settings_v2"
curl -s -o /dev/null -w "rule_overrides_v2=%{http_code}\n" "$BASE/api/ui/rule_overrides_v2"
echo "[DONE] Ctrl+Shift+R /settings + /rule_overrides"
