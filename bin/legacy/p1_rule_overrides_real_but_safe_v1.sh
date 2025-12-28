#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
BACK="${APP}.bak_ro_real_${TS}"
cp -f "$APP" "$BACK"
echo "[BACKUP] $BACK"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# ensure imports
if "from flask import" in s and "request" not in s:
    s=re.sub(r"from flask import ([^\n]+)", lambda m: m.group(0).rstrip()+", request", s, count=1)

if "import json" not in s:
    s="import json\n"+s
if "from pathlib import Path" not in s:
    s="from pathlib import Path\n"+s

# add helpers near top (after imports)
marker = "app = Flask(__name__"
idx = s.find(marker)
if idx==-1:
    raise SystemExit("[ERR] cannot locate Flask app init")

helpers = textwrap.dedent(r'''
# --- P1 Rule Overrides real-but-safe (persist under out_ci) ---
RO_DIR = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides")
RO_FILE = RO_DIR / "rule_overrides_v1.json"

def _ro_default():
    return {"ok": True, "degraded": True, "items": [], "note": "rule_overrides running in degraded-safe mode"}

def _ro_load():
    try:
        RO_DIR.mkdir(parents=True, exist_ok=True)
        if RO_FILE.exists():
            return json.loads(RO_FILE.read_text(encoding="utf-8"))
        return {"ok": True, "degraded": False, "items": []}
    except Exception as e:
        j=_ro_default()
        j["error"]=str(e)
        return j

def _ro_save(obj):
    try:
        RO_DIR.mkdir(parents=True, exist_ok=True)
        tmp = RO_FILE.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
        tmp.replace(RO_FILE)
        return True, None
    except Exception as e:
        return False, str(e)
''')

# insert helpers once
if "P1 Rule Overrides real-but-safe" not in s:
    s = s[:idx] + helpers + "\n" + s[idx:]

# replace existing rule_overrides endpoint if present, else add new
route_pat = r'@app\.route\(["\']\/api\/vsp\/rule_overrides_v1["\'][\s\S]*?\n(?=@app\.route|\Z)'
m = re.search(route_pat, s)
new_route = textwrap.dedent(r'''
@app.route("/api/vsp/rule_overrides_v1", methods=["GET","POST","PUT"])
def api_rule_overrides_v1():
    # Never-500 contract: always return JSON 200
    j = _ro_load()
    resp = None

    if request.method in ("POST","PUT"):
        try:
            payload = request.get_json(silent=True) or {}
            items = payload.get("items", payload.get("rules", payload.get("overrides")))
            if items is None:
                # allow sending whole object
                items = payload.get("data", [])
            if not isinstance(items, list):
                items = []
            out = {"ok": True, "degraded": False, "items": items}
            ok, err = _ro_save(out)
            if not ok:
                out["degraded"] = True
                out["note"] = "persist failed; returned degraded-safe"
                out["error"] = err
            j = out
        except Exception as e:
            j = _ro_default()
            j["error"] = str(e)

    resp = jsonify(j)
    # signal safe mode when degraded
    resp.headers["X-VSP-RO-SAFE"] = "1" if j.get("degraded") else "0"
    return resp, 200
''').strip()+"\n"

if m:
    s = s[:m.start()] + new_route + "\n" + s[m.end():]
else:
    # append near end
    s += "\n\n" + new_route

p.write_text(s, encoding="utf-8")
print("[OK] patched rule_overrides_v1 endpoint")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== quick probe =="
curl -sS "$BASE/api/vsp/rule_overrides_v1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"degraded=",j.get("degraded"),"items_len=",len(j.get("items") or []))'
