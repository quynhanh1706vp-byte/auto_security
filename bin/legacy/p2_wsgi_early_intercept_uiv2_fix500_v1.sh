#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_WSGI_EARLY_UIV2_INTERCEPT_FIX500_V1"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "${F}.bak_wsgiuiv2_${TS}"
echo "[BACKUP] ${F}.bak_wsgiuiv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")

MARK="VSP_P2_WSGI_EARLY_UIV2_INTERCEPT_FIX500_V1"
if MARK in s:
    print("[OK] marker already present -> skip")
    sys.exit(0)

helpers = textwrap.dedent("""
# ===================== %%MARK%% =====================
def _vsp__wsgi_json(start_response, obj, code=200):
    import json as _json
    status = f"{int(code)} OK" if int(code) < 400 else f"{int(code)} ERROR"
    body = _json.dumps(obj, ensure_ascii=False).encode("utf-8")
    headers = [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Cache-Control", "no-store"),
        ("Content-Length", str(len(body))),
    ]
    start_response(status, headers)
    return [body]

def _vsp__wsgi_read_body(environ):
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

def _vsp__wsgi_uiv2_handle(environ, start_response):
    \"\"\"Early intercept for /api/ui/settings_v2 and /api/ui/rule_overrides_v2.
       Returns iterable(bytes) if handled, else None.
    \"\"\"
    try:
        path = (environ.get("PATH_INFO") or "")
        method = (environ.get("REQUEST_METHOD") or "GET").upper()

        if path not in ("/api/ui/settings_v2", "/api/ui/rule_overrides_v2"):
            return None

        from pathlib import Path as _Path
        import json as _json

        d = _Path("ui_state_v1")
        d.mkdir(parents=True, exist_ok=True)

        if path == "/api/ui/settings_v2":
            f = d / "settings_local.json"
            default = {"ok": True, "source": "default", "tools": {}, "ui": {}, "notes": "wsgi-early-intercept"}
        else:
            f = d / "rule_overrides_local.json"
            default = {"ok": True, "schema": "rules_v1", "rules": [], "notes": "wsgi-early-intercept"}

        if method == "POST":
            raw = _vsp__wsgi_read_body(environ)
            try:
                payload = _json.loads(raw.decode("utf-8", errors="ignore") or "{}")
            except Exception:
                return _vsp__wsgi_json(start_response, {"ok": False, "err": "invalid json"}, 400)
            try:
                f.write_text(_json.dumps(payload, ensure_ascii=False, indent=2))
                return _vsp__wsgi_json(start_response, {"ok": True, "saved": str(f), "__via__": "%%MARK%%"}, 200)
            except Exception as e:
                return _vsp__wsgi_json(start_response, {"ok": False, "err": repr(e), "__via__": "%%MARK%%"}, 500)

        # GET
        try:
            if f.exists():
                txt = (f.read_text(errors="ignore") or "").strip()
                if txt:
                    return _vsp__wsgi_json(start_response, _json.loads(txt), 200)
        except Exception:
            pass
        return _vsp__wsgi_json(start_response, default, 200)

    except Exception as e:
        return _vsp__wsgi_json(start_response, {"ok": False, "err": repr(e), "__via__": "%%MARK%%"}, 500)
# ===================== /%%MARK%% =====================
""").replace("%%MARK%%", MARK).strip("\n")

# append helpers near end (safe), then inject call at top of application()
s = s + "\n\n" + helpers + "\n"

def inject_into_wsgi_func(src: str, func_name: str) -> str:
    # Find def func_name(environ, start_response):
    m = re.search(rf'(?m)^(def\s+{re.escape(func_name)}\s*\(\s*environ\s*,\s*start_response\s*\)\s*:\s*)$', src)
    if not m:
        return src
    # Determine indentation inside function (4 spaces typical)
    ins_pos = m.end()
    inject = "\n    # [AUTO] early intercept for UI v2 (boot-safe)\n    _r = _vsp__wsgi_uiv2_handle(environ, start_response)\n    if _r is not None:\n        return _r\n"
    # Avoid duplicating
    if "_vsp__wsgi_uiv2_handle(environ, start_response)" in src[m.start(): m.start()+800]:
        return src
    return src[:ins_pos] + inject + src[ins_pos:]

s2 = inject_into_wsgi_func(s, "application")
s2 = inject_into_wsgi_func(s2, "app")  # fallback if they use def app(...) as wsgi entry
p.write_text(s2, encoding="utf-8")
print("[OK] patched:", MARK)
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
