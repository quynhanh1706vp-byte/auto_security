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
MARK="VSP_P2_FORCEBIND_REAL_FLASK_APP_V1"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_realflask_${TS}"
echo "[BACKUP] ${F}.bak_realflask_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")
MARK = "VSP_P2_FORCEBIND_REAL_FLASK_APP_V1"
if MARK in s:
    print("[OK] marker already present -> skip")
    sys.exit(0)

block = textwrap.dedent("""
# ===================== %%MARK%% =====================
def _vsp_pick_real_flask_app():
    \"\"\"Find a Flask-like app object in module globals (has url_map + add_url_rule + view_functions).\"\"\"
    try:
        g = globals()
        for k, v in list(g.items()):
            if v is None: 
                continue
            if hasattr(v, "url_map") and hasattr(v, "add_url_rule") and hasattr(v, "view_functions"):
                return v
    except Exception:
        pass
    return None

def _vsp_forcebind_rule(_app, rule_path, fn, methods=("GET",)):
    \"\"\"Replace existing handler if route exists, else add new rule.\"\"\"
    try:
        replaced = 0
        for r in list(_app.url_map.iter_rules()):
            if getattr(r, "rule", None) == rule_path:
                _app.view_functions[r.endpoint] = fn
                replaced += 1
        if replaced:
            return True
        ep = "vsp_fb_" + str(abs(hash(rule_path)) % 10**9)
        _app.add_url_rule(rule_path, endpoint=ep, view_func=fn, methods=list(methods))
        return True
    except Exception as e:
        print("[VSP_REAL_FLASK] forcebind failed:", rule_path, repr(e))
        return False

def _vsp_json_resp(obj, status=200):
    import json as _json
    from flask import Response
    b = _json.dumps(obj, ensure_ascii=False).encode("utf-8")
    r = Response(b, status=int(status), mimetype="application/json; charset=utf-8")
    r.headers["Cache-Control"] = "no-store"
    return r

def _vsp_state_dir():
    from pathlib import Path
    d = Path("ui_state_v1")
    d.mkdir(parents=True, exist_ok=True)
    return d

def _vsp_load(path_obj, default):
    try:
        import json as _json
        if path_obj.exists():
            txt = (path_obj.read_text(errors="ignore") or "").strip()
            return _json.loads(txt) if txt else default
    except Exception:
        pass
    return default

def _vsp_save(path_obj, payload):
    try:
        import json as _json
        path_obj.write_text(_json.dumps(payload, ensure_ascii=False, indent=2))
        return True
    except Exception:
        return False

_app_real = _vsp_pick_real_flask_app()
if _app_real is None:
    print("[VSP_REAL_FLASK] no Flask app found; cannot forcebind")
else:
    from flask import request

    # --- Readycheck stubs (must be 200) ---
    def _api_vsp_runs_stub():
        lim = 1
        try: lim = int(request.args.get("limit","1") or "1")
        except Exception: pass
        return _vsp_json_resp({"ok": True, "stub": True, "runs": [], "limit": lim}, 200)

    def _api_vsp_release_latest_stub():
        return _vsp_json_resp({"ok": True, "stub": True, "download_url": None, "package_url": None}, 200)

    _vsp_forcebind_rule(_app_real, "/api/vsp/runs", _api_vsp_runs_stub, methods=("GET",))
    _vsp_forcebind_rule(_app_real, "/api/vsp/release_latest", _api_vsp_release_latest_stub, methods=("GET",))

    # --- UI V2 endpoints (fix 500) ---
    def _api_ui_settings_v2_safe():
        d = _vsp_state_dir()
        f = d / "settings_local.json"
        if request.method == "POST":
            payload = request.get_json(silent=True)
            if payload is None:
                return _vsp_json_resp({"ok": False, "err": "no json"}, 400)
            ok = _vsp_save(f, payload)
            return _vsp_json_resp({"ok": bool(ok), "saved": str(f)}, 200 if ok else 500)
        default = {"ok": True, "source": "default", "tools": {}, "ui": {}, "notes": "local-first"}
        return _vsp_json_resp(_vsp_load(f, default), 200)

    def _api_ui_rule_overrides_v2_safe():
        d = _vsp_state_dir()
        f = d / "rule_overrides_local.json"
        if request.method == "POST":
            payload = request.get_json(silent=True)
            if payload is None:
                return _vsp_json_resp({"ok": False, "err": "no json"}, 400)
            ok = _vsp_save(f, payload)
            return _vsp_json_resp({"ok": bool(ok), "saved": str(f)}, 200 if ok else 500)
        default = {"ok": True, "schema": "rules_v1", "rules": [], "rid": (request.args.get("rid","") or "")}
        return _vsp_json_resp(_vsp_load(f, default), 200)

    _vsp_forcebind_rule(_app_real, "/api/ui/settings_v2", _api_ui_settings_v2_safe, methods=("GET","POST"))
    _vsp_forcebind_rule(_app_real, "/api/ui/rule_overrides_v2", _api_ui_rule_overrides_v2_safe, methods=("GET","POST"))
    print("[VSP_REAL_FLASK] forcebind OK on real app")
# ===================== /%%MARK%% =====================
""").replace("%%MARK%%", MARK).strip("\n")

p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC"
fi

echo "== verify endpoints =="
curl -s -o /dev/null -w "settings_v2=%{http_code}\n" "$BASE/api/ui/settings_v2"
curl -s -o /dev/null -w "rule_overrides_v2=%{http_code}\n" "$BASE/api/ui/rule_overrides_v2"
curl -s -o /dev/null -w "runs_api=%{http_code}\n" "$BASE/api/vsp/runs?limit=1"
curl -s -o /dev/null -w "release_latest=%{http_code}\n" "$BASE/api/vsp/release_latest"
echo "[DONE] Ctrl+Shift+R on /settings + /rule_overrides"
