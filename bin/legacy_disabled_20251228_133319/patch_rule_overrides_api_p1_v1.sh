#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
PYF="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

grep -q '"/api/vsp/rule_overrides_v1"' "$PYF" && { echo "[OK] rule_overrides_v1 already exists"; exit 0; }

cp -f "$PYF" "$PYF.bak_ruleov_${TS}"
echo "[BACKUP] $PYF.bak_ruleov_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_RULE_OVERRIDES_API_P1_V1"
if MARK in s:
    print("[OK] already patched:", MARK); raise SystemExit(0)

addon=r'''
# -------------------- {MARK} --------------------
# Rule Overrides API (GET/POST) persisted on disk (audit-friendly)
import os, json, time
from flask import request, jsonify

_RULE_DIR = "/home/test/Data/SECURITY_BUNDLE/ui/out_ci"
_RULE_FILE = os.path.join(_RULE_DIR, "rule_overrides_v1.json")

def _rule_load():
    os.makedirs(_RULE_DIR, exist_ok=True)
    if not os.path.isfile(_RULE_FILE):
        return {"version": 1, "updated_at": "", "updated_by": "", "overrides": []}
    try:
        with open(_RULE_FILE, "r", encoding="utf-8", errors="replace") as f:
            j=json.load(f)
        if not isinstance(j, dict): 
            return {"version": 1, "updated_at": "", "updated_by": "", "overrides": []}
        j.setdefault("version", 1)
        j.setdefault("overrides", [])
        return j
    except Exception:
        return {"version": 1, "updated_at": "", "updated_by": "", "overrides": []}

def _rule_save(j):
    os.makedirs(_RULE_DIR, exist_ok=True)
    tmp=_RULE_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(j, f, ensure_ascii=False, indent=2)
    os.replace(tmp, _RULE_FILE)

@app.get("/api/vsp/rule_overrides_v1")
def vsp_rule_overrides_v1_get():
    j=_rule_load()
    return jsonify(j)

@app.post("/api/vsp/rule_overrides_v1")
def vsp_rule_overrides_v1_post():
    try:
        payload=request.get_json(force=True, silent=False) or {}
        if not isinstance(payload, dict):
            return jsonify({"ok":False,"error":"BAD_JSON"}), 400
        payload.setdefault("version", 1)
        payload.setdefault("overrides", [])
        payload["updated_at"]=time.strftime("%Y-%m-%dT%H:%M:%S%z")
        payload["updated_by"]=request.remote_addr or ""
        _rule_save(payload)
        return jsonify({"ok":True})
    except Exception as e:
        return jsonify({"ok":False,"error":"EXC","detail":str(e)}), 500
# ------------------ end {MARK} ------------------
'''.replace("{MARK}", MARK)

m=re.search(r"if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s)
s2 = (s[:m.start()] + addon + "\n\n" + s[m.start():]) if m else (s + "\n\n" + addon)
p.write_text(s2, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$PYF"
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh

echo "== self-check rule overrides =="
curl -sS http://127.0.0.1:8910/api/vsp/rule_overrides_v1 | head -c 240; echo
