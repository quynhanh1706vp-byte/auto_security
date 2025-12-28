#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_alias_${TS}"
echo "[BACKUP] $F.bak_runv1_alias_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_RUN_V1_ALIAS_V1" in txt:
    print("[SKIP] already has VSP_RUN_V1_ALIAS_V1")
    raise SystemExit(0)

# detect app var
m = re.search(r"^\s*(\w+)\s*=\s*Flask\s*\(", txt, flags=re.M)
appvar = m.group(1) if m else "app"

block = f'''
# === VSP_RUN_V1_ALIAS_V1 ===
# Commercial contract: provide POST /api/vsp/run_v1 as stable entrypoint.
# Implementation: alias to existing /api/vsp/run (api_vsp_run) handler.
from flask import request, jsonify

@{appvar}.route("/api/vsp/run_v1", methods=["POST"])
def vsp_run_v1_alias():
    body = None
    try:
        body = request.get_json(silent=True)
    except Exception:
        body = None
    if not body:
        return jsonify({{"ok": False, "error": "MISSING_BODY"}}), 400

    fn = globals().get("api_vsp_run")
    if callable(fn):
        return fn()

    # If api_vsp_run not present for any reason, return jq-safe error
    return jsonify({{"ok": False, "error": "RUN_ALIAS_TARGET_MISSING", "final": True}}), 500
# === END VSP_RUN_V1_ALIAS_V1 ===
'''

# insert before __main__
mm = re.search(r"^\s*if\s+__name__\s*==\s*['\"]__main__['\"]\s*:\s*$", txt, flags=re.M)
if mm:
    txt2 = txt[:mm.start()] + block + "\n" + txt[mm.start():]
else:
    txt2 = txt + "\n" + block + "\n"

p.write_text(txt2, encoding="utf-8")
print("[OK] inserted VSP_RUN_V1_ALIAS_V1")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "== Smoke: /api/vsp/run_v1 must exist (not 404) =="
curl -sS -X POST "http://localhost:8910/api/vsp/run_v1" -H "Content-Type: application/json" \
  -d '{"mode":"local","profile":"FULL_EXT","target_type":"path","target":"/home/test/Data/SECURITY-10-10-v4"}' | head -c 300; echo

echo "== urlmap check (show run_v1) =="
python3 - <<'PY'
import flask, vsp_demo_app as mod
app=None
for k,v in vars(mod).items():
    if isinstance(v, flask.Flask):
        app=v; break
hits=[r.rule for r in app.url_map.iter_rules() if r.rule=="/api/vsp/run_v1"]
print("has /api/vsp/run_v1 =", bool(hits))
PY

tail -n 20 out_ci/ui_8910.log
