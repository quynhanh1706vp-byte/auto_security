#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_topfind_v2_${TS}"
echo "[BACKUP] ${APP}.bak_topfind_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Ensure imports we need (idempotent)
def ensure_import(line: str):
    global s
    if re.search(r'^\s*' + re.escape(line) + r'\s*$', s, flags=re.M):
        return
    m = re.search(r'^(?:import .*|from .* import .*)(?:\n(?:import .*|from .* import .*))*\n', s, flags=re.M)
    if m:
        s = s[:m.end()] + line + "\n" + s[m.end():]
    else:
        s = line + "\n" + s

for line in ["import os", "import json", "import glob", "import time", "import re", "from datetime import datetime"]:
    ensure_import(line)

# 1) Disable any existing route decorator(s) for /api/vsp/top_findings_v1 (avoid double-register)
#    We only rewrite the decorator line path; function can remain for debug/legacy but won't shadow.
s2, n = re.subn(
    r'@app\.route\(\s*([\'"])/api/vsp/top_findings_v1\1\s*,',
    r'@app.route(\1/api/vsp/_disabled_top_findings_v1\1,',
    s
)
s = s2

# 2) Helpers (idempotent)
helper_marker = "VSP_P0_TOP_FINDINGS_HELPERS_V2"
helper_block = f"""
# {helper_marker}
def _vsp__sanitize_path(pth: str) -> str:
    if not pth:
        return ""
    pth = pth.replace("\\\\", "/")
    pth = re.sub(r'^/+', '', pth)
    parts = [x for x in pth.split("/") if x]
    if len(parts) <= 4:
        return "/".join(parts)
    return "/".join(parts[-4:])

def _vsp__sev_weight(sev: str) -> int:
    m = {{
        "CRITICAL": 600, "HIGH": 500, "MEDIUM": 400, "LOW": 300, "INFO": 200, "TRACE": 100
    }}
    return m.get((sev or "").upper(), 0)

def _vsp__candidate_run_roots():
    return [
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
    ]

def _vsp__pick_latest_rid() -> str:
    best = ("", -1.0)
    for root in _vsp__candidate_run_roots():
        try:
            if not os.path.isdir(root):
                continue
            for d in glob.glob(os.path.join(root, "VSP_*")):
                if not os.path.isdir(d):
                    continue
                mt = os.path.getmtime(d)
                name = os.path.basename(d)
                if mt > best[1]:
                    best = (name, mt)
        except Exception:
            continue
    return best[0] or ""

def _vsp__find_run_dir_for_rid(rid: str) -> str:
    if not rid:
        return ""
    for root in _vsp__candidate_run_roots():
        d = os.path.join(root, rid)
        if os.path.isdir(d):
            return d
    best = ("", -1.0)
    for root in _vsp__candidate_run_roots():
        try:
            for d in glob.glob(os.path.join(root, rid + "*")):
                if not os.path.isdir(d):
                    continue
                mt = os.path.getmtime(d)
                if mt > best[1]:
                    best = (d, mt)
        except Exception:
            continue
    return best[0] or ""

def _vsp__load_unified_findings_anywhere(rid: str):
    run_dir = _vsp__find_run_dir_for_rid(rid)
    if not run_dir:
        return None, "RID_NOT_FOUND"
    candidates = [
        os.path.join(run_dir, "reports", "findings_unified.json"),
        os.path.join(run_dir, "findings_unified.json"),
        os.path.join(run_dir, "report", "findings_unified.json"),
    ]
    for fp in candidates:
        try:
            if not os.path.isfile(fp):
                continue
            with open(fp, "r", encoding="utf-8") as f:
                obj = json.load(f)
            if isinstance(obj, dict) and isinstance(obj.get("findings"), list):
                findings = obj.get("findings") or []
            elif isinstance(obj, list):
                findings = obj
            else:
                findings = []
            return findings, ""
        except Exception:
            continue
    return None, "UNIFIED_NOT_FOUND"
# END {helper_marker}
"""
if helper_marker not in s:
    m = re.search(r'^(?:import .*|from .* import .*)(?:\n(?:import .*|from .* import .*))*\n', s, flags=re.M)
    if m:
        s = s[:m.end()] + helper_block + "\n" + s[m.end():]
    else:
        s = helper_block + "\n" + s

# 3) Add our collision-safe route (unique function name + endpoint name)
route_marker = "VSP_P0_TOPFIND_ROUTE_V2"
new_route = f'''
# {route_marker}
@app.route("/api/vsp/top_findings_v1", methods=["GET"], endpoint="api_vsp_top_findings_v1_p0")
def api_vsp_top_findings_v1_p0():
    try:
        rid = (request.args.get("rid") or "").strip()
        limit = int(request.args.get("limit") or "5")
        if limit < 1: limit = 1
        if limit > 50: limit = 50

        if not rid:
            rid = _vsp__pick_latest_rid()

        if not rid:
            return jsonify({{"ok": False, "rid": "", "total": 0, "items": [], "reason": "NO_RUNS"}}), 200

        findings, errc = _vsp__load_unified_findings_anywhere(rid)
        if findings is None:
            return jsonify({{"ok": False, "rid": rid, "total": 0, "items": [], "reason": errc}}), 200

        items = []
        for f in (findings or []):
            if not isinstance(f, dict):
                continue
            it = {{
                "tool": f.get("tool"),
                "severity": (f.get("severity") or "").upper(),
                "title": f.get("title"),
                "cwe": f.get("cwe"),
                "rule_id": f.get("rule_id") or f.get("check_id") or f.get("id"),
                "file": _vsp__sanitize_path(f.get("file") or f.get("path") or ""),
                "line": f.get("line") or f.get("start_line") or f.get("line_start"),
            }}
            items.append(it)

        items.sort(key=lambda x: (_vsp__sev_weight(x.get("severity")), str(x.get("title") or "")), reverse=True)
        return jsonify({{
            "ok": True,
            "rid": rid,
            "total": len(items),
            "items": items[:limit],
            "ts": datetime.utcnow().isoformat() + "Z",
        }}), 200
    except Exception:
        return jsonify({{"ok": False, "rid": (request.args.get("rid") or ""), "total": 0, "items": [], "reason": "EXCEPTION"}}), 200
'''
if route_marker not in s:
    mmain = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s, flags=re.M)
    if mmain:
        s = s[:mmain.start()] + "\n" + new_route + "\n" + s[mmain.start():]
    else:
        s = s + "\n" + new_route + "\n"

p.write_text(s, encoding="utf-8")
print(f"[OK] disabled_old_routes={n}, added_route={route_marker}")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sudo systemctl status vsp-ui-8910.service --no-pager -l | sed -n '1,20p'

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-VSP_CI_20251218_114312}"
echo "== [TEST] top_findings_v1 =="
curl -fsS "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=5" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print("ok=",j.get("ok"),"rid=",j.get("rid"),"total=",j.get("total"),"reason=",j.get("reason"))
items=j.get("items") or []
print("items=",len(items))
if items:
  print("first_sev=",items[0].get("severity"),"title=", (items[0].get("title") or "")[:120])
PY

echo "[DONE]"
