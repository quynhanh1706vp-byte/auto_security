#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_uiv2fix_${TS}"
echo "[BACKUP] ${F}.bak_uiv2fix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")

def drop_marked_block(text: str, marker: str) -> str:
    start = re.search(rf'(?m)^#\s*=+\s*{re.escape(marker)}\s*=+\s*$', text)
    end   = re.search(rf'(?m)^#\s*=+\s*/{re.escape(marker)}\s*=+\s*$', text)
    if not start or not end or end.start() < start.end():
        return text
    return text[:start.start()] + "\n" + text[end.end():]

# Remove the broken decorator-based block (causing AttributeError)
s2 = drop_marked_block(s, "VSP_P2_UIV2_BEFORE_REQUEST_BYPASS_FIX500_V1")

# Also remove the earlier forcebind block if present (avoid conflicting handlers)
s2 = drop_marked_block(s2, "VSP_P2_FORCEBIND_UI_SETTINGS_RULE_OVERRIDES_V1")

# Append a safe forcebind (route override) that never uses .before_request
MARK="VSP_P2_UIV2_ROUTE_FORCEBIND_SAFE_V1"
if MARK not in s2:
    block = textwrap.dedent(f"""
    # ===================== {MARK} =====================
    def _vsp_uiv2_json_resp(obj, status=200):
        import json as _json
        from flask import Response
        b = _json.dumps(obj, ensure_ascii=False).encode("utf-8")
        r = Response(b, status=int(status), mimetype="application/json; charset=utf-8")
        r.headers["Cache-Control"] = "no-store"
        return r

    def _vsp_uiv2_state_dir():
        from pathlib import Path
        d = Path("ui_state_v1")
        d.mkdir(parents=True, exist_ok=True)
        return d

    def _vsp_uiv2_load(path, default):
        try:
            import json as _json
            if path.exists():
                txt = (path.read_text(errors="ignore") or "").strip()
                return _json.loads(txt) if txt else default
        except Exception:
            pass
        return default

    def _vsp_uiv2_save(path, payload):
        try:
            import json as _json
            path.write_text(_json.dumps(payload, ensure_ascii=False, indent=2))
            return True
        except Exception:
            return False

    def _vsp_uiv2_replace_or_add(_app, path, fn, methods=("GET",)):
        \"\"\"If route exists -> replace its view func; else add new rule.\"\"\"
        try:
            replaced = 0
            for r in list(_app.url_map.iter_rules()):
                if getattr(r, "rule", None) == path:
                    _app.view_functions[r.endpoint] = fn
                    replaced += 1
            if replaced:
                return True
            _app.add_url_rule(path, endpoint=f"vsp_uiv2_{path}_{id(fn)}", view_func=fn, methods=list(methods))
            return True
        except Exception as e:
            print("[VSP_UIV2_SAFE] replace_or_add failed:", repr(e))
            return False

    # Prefer the real WSGI entry: application (gunicorn loads wsgi_vsp_ui_gateway:application)
    try:
        _app_uiv2 = application
    except Exception:
        _app_uiv2 = None

    if _app_uiv2 is not None and hasattr(_app_uiv2, "add_url_rule") and hasattr(_app_uiv2, "url_map"):
        from flask import request

        def _api_ui_settings_v2_safe():
            d = _vsp_uiv2_state_dir()
            f = d / "settings_local.json"
            if request.method == "POST":
                payload = request.get_json(silent=True)
                if payload is None:
                    return _vsp_uiv2_json_resp({{"ok": False, "err": "no json"}}, 400)
                ok = _vsp_uiv2_save(f, payload)
                return _vsp_uiv2_json_resp({{"ok": bool(ok), "saved": str(f)}}, 200 if ok else 500)
            default = {{"ok": True, "source": "default", "tools": {{}}, "ui": {{}}, "notes": "local-first"}}
            return _vsp_uiv2_json_resp(_vsp_uiv2_load(f, default), 200)

        def _api_ui_rule_overrides_v2_safe():
            d = _vsp_uiv2_state_dir()
            f = d / "rule_overrides_local.json"
            if request.method == "POST":
                payload = request.get_json(silent=True)
                if payload is None:
                    return _vsp_uiv2_json_resp({{"ok": False, "err": "no json"}}, 400)
                ok = _vsp_uiv2_save(f, payload)
                return _vsp_uiv2_json_resp({{"ok": bool(ok), "saved": str(f)}}, 200 if ok else 500)
            default = {{"ok": True, "schema": "rules_v1", "rules": [], "rid": (request.args.get("rid","") or "")}}
            return _vsp_uiv2_json_resp(_vsp_uiv2_load(f, default), 200)

        _vsp_uiv2_replace_or_add(_app_uiv2, "/api/ui/settings_v2", _api_ui_settings_v2_safe, methods=("GET","POST"))
        _vsp_uiv2_replace_or_add(_app_uiv2, "/api/ui/rule_overrides_v2", _api_ui_rule_overrides_v2_safe, methods=("GET","POST"))
    else:
        print("[VSP_UIV2_SAFE] application is not a Flask app; skip uiv2 forcebind.")
    # ===================== /{MARK} =====================
    """).strip("\n")
    s2 = s2 + "\n\n" + block + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] patched: drop broken before_request + safe forcebind routes")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC"
  systemctl --no-pager --full status "$SVC" | sed -n '1,40p' || true
fi

echo "== verify endpoints =="
curl -s -o /dev/null -w "settings_v2=%{http_code}\n" "$BASE/api/ui/settings_v2" || true
curl -s -o /dev/null -w "rule_overrides_v2=%{http_code}\n" "$BASE/api/ui/rule_overrides_v2" || true
curl -s -o /dev/null -w "/runs=%{http_code}\n" "$BASE/runs" || true
curl -s -o /dev/null -w "/settings=%{http_code}\n" "$BASE/settings" || true
echo "[DONE] Hard refresh Ctrl+Shift+R"
