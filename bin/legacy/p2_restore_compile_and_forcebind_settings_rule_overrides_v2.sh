#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need head; need sed; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_FORCEBIND_UI_SETTINGS_RULE_OVERRIDES_V1"

echo "== [0] pick newest backup that compiles =="
BKP="$(python3 - <<'PY'
import glob, os, subprocess
F="wsgi_vsp_ui_gateway.py"
cands = sorted(glob.glob(F+".bak_*"), key=lambda p: os.path.getmtime(p), reverse=True)
def ok(path):
    try:
        subprocess.check_output(["python3","-m","py_compile",path], stderr=subprocess.STDOUT)
        return True
    except Exception:
        return False
for b in cands:
    if ok(b):
        print(b); break
PY
)"
[ -n "${BKP:-}" ] || { echo "[ERR] no compiling backup found for $F"; ls -1t ${F}.bak_* 2>/dev/null | head; exit 2; }

cp -f "$F" "${F}.bad_${TS}" 2>/dev/null || true
cp -f "$BKP" "$F"
echo "[OK] restored $F from $BKP (saved old as ${F}.bad_${TS})"

echo "== [1] append forcebind block (no f-string) =="
cp -f "$F" "${F}.bak_forcebind_${TS}"
python3 - <<'PY'
from pathlib import Path
import textwrap, re, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")

MARK = "VSP_P2_FORCEBIND_UI_SETTINGS_RULE_OVERRIDES_V1"
if MARK in s:
    print("[OK] marker already present -> skip")
    sys.exit(0)

block = textwrap.dedent("""
# ===================== %%MARK%% =====================
def _vsp_json_resp(obj, status=200):
    import json as _json
    from flask import Response
    b = _json.dumps(obj, ensure_ascii=False).encode("utf-8")
    r = Response(b, status=int(status), mimetype="application/json; charset=utf-8")
    r.headers["Cache-Control"] = "no-store"
    return r

def _vsp_forcebind_rule(_app, rule_path, fn, methods=("GET",)):
    \"\"\"Replace existing handler if route exists, else add new.\"\"\"
    try:
        replaced = 0
        for r in list(_app.url_map.iter_rules()):
            if getattr(r, "rule", None) == rule_path:
                _app.view_functions[r.endpoint] = fn
                replaced += 1
        if replaced:
            return True
        _app.add_url_rule(rule_path, endpoint=f"vsp_force_{rule_path}_{id(fn)}", view_func=fn, methods=list(methods))
        return True
    except Exception:
        return False

def _vsp_state_dir():
    from pathlib import Path
    d = Path("ui_state_v1")
    d.mkdir(parents=True, exist_ok=True)
    return d

def _vsp_load_json(path, default):
    try:
        import json as _json
        if path.exists():
            txt = path.read_text(errors="ignore") or ""
            return _json.loads(txt) if txt.strip() else default
    except Exception:
        pass
    return default

def _vsp_save_json(path, obj):
    try:
        import json as _json
        path.write_text(_json.dumps(obj, ensure_ascii=False, indent=2))
        return True
    except Exception:
        return False

def _api_ui_settings_v2():
    from flask import request
    d = _vsp_state_dir()
    f = d / "settings_local.json"
    if request.method == "POST":
        payload = request.get_json(silent=True)
        if payload is None:
            return _vsp_json_resp({"ok": False, "err": "no json"}, 400)
        ok = _vsp_save_json(f, payload)
        return _vsp_json_resp({"ok": bool(ok), "saved": str(f)}, 200 if ok else 500)
    default = {"ok": True, "source": "default", "tools": {}, "ui": {}, "notes": "local-first"}
    return _vsp_json_resp(_vsp_load_json(f, default), 200)

def _api_ui_rule_overrides_v2():
    from flask import request
    d = _vsp_state_dir()
    f = d / "rule_overrides_local.json"
    if request.method == "POST":
        payload = request.get_json(silent=True)
        if payload is None:
            return _vsp_json_resp({"ok": False, "err": "no json"}, 400)
        ok = _vsp_save_json(f, payload)
        return _vsp_json_resp({"ok": bool(ok), "saved": str(f)}, 200 if ok else 500)
    default = {"ok": True, "schema": "rules_v1", "rules": [], "rid": (request.args.get("rid","") if request else "")}
    return _vsp_json_resp(_vsp_load_json(f, default), 200)

try:
    _app_obj = app
except Exception:
    try:
        _app_obj = application
    except Exception:
        _app_obj = None

if _app_obj is not None:
    _vsp_forcebind_rule(_app_obj, "/api/ui/settings_v2", _api_ui_settings_v2, methods=("GET","POST"))
    _vsp_forcebind_rule(_app_obj, "/api/ui/rule_overrides_v2", _api_ui_rule_overrides_v2, methods=("GET","POST"))
# ===================== /%%MARK%% =====================
""").replace("%%MARK%%", MARK).strip("\n")

s2 = s + "\n\n" + block + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended forcebind block:", MARK)
PY

echo "== [2] compile check =="
python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== [3] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC"
  systemctl --no-pager --full status "$SVC" | sed -n '1,40p' || true
fi

echo "== [4] verify endpoints (expect 200) =="
curl -s -o /dev/null -w "settings_v2=%{http_code}\n" "$BASE/api/ui/settings_v2"
curl -s -o /dev/null -w "rule_overrides_v2=%{http_code}\n" "$BASE/api/ui/rule_overrides_v2"
echo "[DONE] Hard refresh /settings + /rule_overrides (Ctrl+Shift+R)"
