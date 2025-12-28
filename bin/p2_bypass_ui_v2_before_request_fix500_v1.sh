#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_UIV2_BEFORE_REQUEST_BYPASS_FIX500_V1"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_uiv2_bypass_${TS}"
echo "[BACKUP] ${F}.bak_uiv2_bypass_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")
MARK = "VSP_P2_UIV2_BEFORE_REQUEST_BYPASS_FIX500_V1"

if MARK in s:
    print("[OK] marker already present -> skip")
    sys.exit(0)

block = textwrap.dedent("""
# ===================== %%MARK%% =====================
def _vsp__uiv2_json_resp(obj, status=200):
    import json as _json
    from flask import Response
    b = _json.dumps(obj, ensure_ascii=False).encode("utf-8")
    r = Response(b, status=int(status), mimetype="application/json; charset=utf-8")
    r.headers["Cache-Control"] = "no-store"
    return r

def _vsp__uiv2_state_dir():
    from pathlib import Path
    d = Path("ui_state_v1")
    d.mkdir(parents=True, exist_ok=True)
    return d

def _vsp__uiv2_load(path, default):
    try:
        import json as _json
        if path.exists():
            txt = (path.read_text(errors="ignore") or "").strip()
            return _json.loads(txt) if txt else default
    except Exception:
        pass
    return default

def _vsp__uiv2_save(path, payload):
    try:
        import json as _json
        path.write_text(_json.dumps(payload, ensure_ascii=False, indent=2))
        return True
    except Exception:
        return False

try:
    _app_obj_uiv2 = app
except Exception:
    try:
        _app_obj_uiv2 = application
    except Exception:
        _app_obj_uiv2 = None

if _app_obj_uiv2 is not None:
    from flask import request

    @_app_obj_uiv2.before_request
    def _vsp__uiv2_bypass_fix500():
        try:
            pth = request.path or ""
            if pth == "/api/ui/settings_v2":
                d = _vsp__uiv2_state_dir()
                f = d / "settings_local.json"
                if request.method == "POST":
                    payload = request.get_json(silent=True)
                    if payload is None:
                        return _vsp__uiv2_json_resp({"ok": False, "err": "no json"}, 400)
                    ok = _vsp__uiv2_save(f, payload)
                    return _vsp__uiv2_json_resp({"ok": bool(ok), "saved": str(f)}, 200 if ok else 500)
                default = {"ok": True, "source": "default", "tools": {}, "ui": {}, "notes": "local-first"}
                return _vsp__uiv2_json_resp(_vsp__uiv2_load(f, default), 200)

            if pth == "/api/ui/rule_overrides_v2":
                d = _vsp__uiv2_state_dir()
                f = d / "rule_overrides_local.json"
                if request.method == "POST":
                    payload = request.get_json(silent=True)
                    if payload is None:
                        return _vsp__uiv2_json_resp({"ok": False, "err": "no json"}, 400)
                    ok = _vsp__uiv2_save(f, payload)
                    return _vsp__uiv2_json_resp({"ok": bool(ok), "saved": str(f)}, 200 if ok else 500)
                default = {"ok": True, "schema": "rules_v1", "rules": [], "rid": (request.args.get("rid","") or "")}
                return _vsp__uiv2_json_resp(_vsp__uiv2_load(f, default), 200)

        except Exception as e:
            # never crash the app
            return _vsp__uiv2_json_resp({"ok": False, "err": str(e), "__patched__": "%%MARK%%"}, 500)
        return None
# ===================== /%%MARK%% =====================
""").replace("%%MARK%%", MARK).strip("\n")

p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended before_request bypass:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC"
fi

echo "== verify endpoints =="
curl -s -o /dev/null -w "settings_v2=%{http_code}\n" "$BASE/api/ui/settings_v2"
curl -s -o /dev/null -w "rule_overrides_v2=%{http_code}\n" "$BASE/api/ui/rule_overrides_v2"

echo "[DONE] Ctrl+Shift+R on /settings and /rule_overrides"
