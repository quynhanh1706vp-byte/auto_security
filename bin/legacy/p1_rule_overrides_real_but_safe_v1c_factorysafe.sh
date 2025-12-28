#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
BACK="${APP}.bak_ro_real_v1c_${TS}"
cp -f "$APP" "$BACK"
echo "[BACKUP] $BACK"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# --- ensure imports ---
if "import json" not in s:
    s="import json\n"+s
if "from pathlib import Path" not in s:
    s="from pathlib import Path\n"+s

m=re.search(r"(?m)^from flask import ([^\n]+)$", s)
if m:
    names=[x.strip() for x in m.group(1).split(",")]
    for need in ("request","jsonify"):
        if need not in names:
            names.append(need)
    s = s[:m.start()] + f"from flask import {', '.join(names)}\n" + s[m.end():]
else:
    # add minimal (safe even if duplicate)
    s="from flask import request, jsonify\n"+s

# --- remove any existing decorator route for rule_overrides_v1 (avoid NameError/app missing) ---
route_pat = r'@app\.route\(\s*["\']\/api\/vsp\/rule_overrides_v1["\'][\s\S]*?\n(?=@app\.route|\Z)'
s = re.sub(route_pat, "", s)

# --- insert helpers once ---
if "P1 Rule Overrides real-but-safe" not in s:
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
''').strip()+"\n\n"

    ins=0
    for mm in re.finditer(r"(?m)^(import .+|from .+ import .+)\s*$", s):
        ins=mm.end()
    s=s[:ins]+"\n"+helpers+s[ins:]

# --- ensure handler exists (NO decorator) ---
if "def api_rule_overrides_v1(" not in s:
    handler = textwrap.dedent(r'''
def api_rule_overrides_v1():
    # Never-500 contract: always return JSON 200
    j = _ro_load()
    if request.method in ("POST","PUT"):
        try:
            payload = request.get_json(silent=True) or {}
            items = payload.get("items", payload.get("rules", payload.get("overrides")))
            if items is None:
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
    resp.headers["X-VSP-RO-SAFE"] = "1" if j.get("degraded") else "0"
    return resp, 200
''').strip()+"\n\n"
    s = s.rstrip()+"\n\n"+handler

# --- register route: prefer create_app() if present ---
if re.search(r"(?m)^\s*def\s+create_app\s*\(", s) and "/api/vsp/rule_overrides_v1" not in s:
    # insert add_url_rule before first "return app" inside create_app
    lines=s.splitlines(True)
    out=[]
    in_ca=False
    ca_indent=None
    inserted=False
    for ln in lines:
        if (not in_ca) and re.match(r"^\s*def\s+create_app\s*\(", ln):
            in_ca=True
            ca_indent=len(ln)-len(ln.lstrip())
            out.append(ln)
            continue
        if in_ca and (ca_indent is not None):
            # detect leaving create_app by dedent
            cur_indent=len(ln)-len(ln.lstrip())
            if ln.strip() and cur_indent<=ca_indent and not ln.lstrip().startswith("#"):
                in_ca=False
            if in_ca and (not inserted) and re.match(r"^\s*return\s+app\s*$", ln):
                ind=" "*(cur_indent)
                out.append(ind + 'app.add_url_rule("/api/vsp/rule_overrides_v1", "api_rule_overrides_v1", api_rule_overrides_v1, methods=["GET","POST","PUT"])\n')
                inserted=True
        out.append(ln)
    s="".join(out)
    if not inserted:
        # fallback: append registration near end (for global app)
        s += '\n# [WARN] could not locate "return app" inside create_app; not registered there.\n'
else:
    # fallback: if global app exists, register once at end (safe if app exists)
    if re.search(r"(?m)^\s*app\s*=", s) and "add_url_rule(\"/api/vsp/rule_overrides_v1\"" not in s:
        s += '\ntry:\n    app.add_url_rule("/api/vsp/rule_overrides_v1", "api_rule_overrides_v1", api_rule_overrides_v1, methods=["GET","POST","PUT"])\nexcept Exception:\n    pass\n'

p.write_text(s, encoding="utf-8")
print("[OK] patched rule_overrides_v1 factory-safe (v1c)")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== probe GET =="
curl -sS "$BASE/api/vsp/rule_overrides_v1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"degraded=",j.get("degraded"),"items_len=",len(j.get("items") or []))' || true
