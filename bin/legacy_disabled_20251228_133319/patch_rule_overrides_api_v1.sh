#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_rule_overrides_${TS}"
echo "[BACKUP] $F.bak_rule_overrides_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RULE_OVERRIDES_API_V1 ==="
if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

block = r'''
%s
VSP_RULE_OVERRIDES_PATH = "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/vsp_rule_overrides_v1.json"

def _vsp_rule_overrides_default_v1():
    return {
        "ok": True,
        "version": 1,
        "updated_at": None,
        "rules": [],
        "note": "Commercial: rules apply on findings at read-time (Data Source / Reports).",
    }

def _vsp_rule_overrides_load_v1():
    try:
        import json, os
        if os.path.isfile(VSP_RULE_OVERRIDES_PATH):
            with open(VSP_RULE_OVERRIDES_PATH, "r", encoding="utf-8", errors="ignore") as f:
                d = json.load(f)
            if isinstance(d, dict) and "rules" in d:
                d.setdefault("ok", True)
                d.setdefault("version", 1)
                return d
    except Exception:
        pass
    return _vsp_rule_overrides_default_v1()

def _vsp_rule_overrides_save_v1(payload: dict):
    import json, os, datetime
    os.makedirs(os.path.dirname(VSP_RULE_OVERRIDES_PATH), exist_ok=True)
    payload = payload if isinstance(payload, dict) else _vsp_rule_overrides_default_v1()
    payload.setdefault("version", 1)
    payload["updated_at"] = datetime.datetime.utcnow().isoformat() + "Z"
    if "rules" not in payload or not isinstance(payload["rules"], list):
        payload["rules"] = []
    with open(VSP_RULE_OVERRIDES_PATH, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    return payload

@app.route("/api/vsp/rule_overrides_v1", methods=["GET","POST"])
def api_vsp_rule_overrides_v1():
    # GET: return current override file (or default)
    if request.method == "GET":
        d = _vsp_rule_overrides_load_v1()
        return jsonify(d)

    # POST: save new overrides
    try:
        payload = request.get_json(force=True, silent=True) or {}
    except Exception:
        payload = {}
    saved = _vsp_rule_overrides_save_v1(payload)
    saved["ok"] = True
    return jsonify(saved)
# --- end rule overrides ---
''' % TAG

# Insert block near end of file (safe)
t2 = t.rstrip() + "\n\n" + block + "\n"
p.write_text(t2, encoding="utf-8")
print("[OK] appended rule overrides API")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"
fuser -k 8910/tcp 2>/dev/null || true
[ -x bin/restart_8910_gunicorn_commercial_v5.sh ] && bin/restart_8910_gunicorn_commercial_v5.sh || true
echo "[DONE] patch_rule_overrides_api_v1"
