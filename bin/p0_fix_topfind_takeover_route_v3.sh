#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_topfind_v3_${TS}"
echo "[BACKUP] ${APP}.bak_topfind_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

def ensure_import(line: str):
    global s
    if re.search(r'^\s*' + re.escape(line) + r'\s*$', s, flags=re.M):
        return
    m = re.search(r'^(?:import .*|from .* import .*)(?:\n(?:import .*|from .* import .*))*\n', s, flags=re.M)
    if m:
        s = s[:m.end()] + line + "\n" + s[m.end():]
    else:
        s = line + "\n" + s

for line in ["import os","import json","import glob","import time","import re","from datetime import datetime"]:
    ensure_import(line)

# --- [A] Disable ALL existing registrations of the same path (robust) ---
# Match both ' and " and any spacing; do not require a trailing comma.
# Only rewrite inside decorator lines to avoid touching strings elsewhere.
lines = s.splitlines(True)
disabled = 0
out = []
for ln in lines:
    if ln.lstrip().startswith("@app.route") and ("/api/vsp/top_findings_v1" in ln):
        # rewrite just the path token
        ln2 = ln.replace("/api/vsp/top_findings_v1", "/api/vsp/_disabled_top_findings_v1_legacy")
        if ln2 != ln:
            disabled += 1
        out.append(ln2)
    else:
        out.append(ln)
s = "".join(out)

# --- [B] Helpers (idempotent) ---
helper_marker = "VSP_P0_TOPFIND_HELPERS_V3"
if helper_marker not in s:
    helper_block = f"""
# {helper_marker}
def _vsp__sanitize_path(pth: str) -> str:
    if not pth:
        return ""
    pth = pth.replace("\\\\", "/")
    pth = re.sub(r'^/+', '', pth)
    parts = [x for x in pth.split("/") if x]
    return "/".join(parts[-4:]) if len(parts) > 4 else "/".join(parts)

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
    # prefix match
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
                return (obj.get("findings") or []), ""
            if isinstance(obj, list):
                return obj, ""
        except Exception:
            continue
    return None, "UNIFIED_NOT_FOUND"
# END {helper_marker}
"""
    m = re.search(r'^(?:import .*|from .* import .*)(?:\n(?:import .*|from .* import .*))*\n', s, flags=re.M)
    if m:
        s = s[:m.end()] + helper_block + "\n" + s[m.end():]
    else:
        s = helper_block + "\n" + s

# --- [C] Add the single authoritative route (unique endpoint + unique function name) ---
route_marker = "VSP_P0_TOPFIND_ROUTE_V3"
if route_marker not in s:
    new_route = f'''
# {route_marker}
@app.route("/api/vsp/top_findings_v1", methods=["GET"], endpoint="vsp_top_findings_v1_p0")
def vsp_top_findings_v1_p0():
    try:
        rid = (request.args.get("rid") or "").strip()
        limit = int(request.args.get("limit") or "5")
        limit = 1 if limit < 1 else (50 if limit > 50 else limit)

        if not rid:
            rid = _vsp__pick_latest_rid()

        if not rid:
            return jsonify({{"ok": False, "rid": "", "total": 0, "items": [], "reason": "NO_RUNS"}}), 200

        findings, reason = _vsp__load_unified_findings_anywhere(rid)
        if findings is None:
            return jsonify({{"ok": False, "rid": rid, "total": 0, "items": [], "reason": reason}}), 200

        items = []
        for f in (findings or []):
            if not isinstance(f, dict):
                continue
            items.append({{
                "tool": f.get("tool"),
                "severity": (f.get("severity") or "").upper(),
                "title": f.get("title"),
                "cwe": f.get("cwe"),
                "rule_id": f.get("rule_id") or f.get("check_id") or f.get("id"),
                "file": _vsp__sanitize_path(f.get("file") or f.get("path") or ""),
                "line": f.get("line") or f.get("start_line") or f.get("line_start"),
            }})
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

@app.route("/api/vsp/_diag_topfind_routes_v1", methods=["GET"])
def vsp__diag_topfind_routes_v1():
    # returns how many live rules still point to /api/vsp/top_findings_v1 (should be 1)
    try:
        rules = []
        for r in app.url_map.iter_rules():
            if "/api/vsp/top_findings_v1" in str(r.rule):
                rules.append({{"rule": str(r.rule), "endpoint": r.endpoint, "methods": sorted(list(r.methods or []))}})
        return jsonify({{"ok": True, "count": len(rules), "rules": rules}}), 200
    except Exception:
        return jsonify({{"ok": False, "count": 0, "rules": []}}), 200
'''
    mmain = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s, flags=re.M)
    if mmain:
        s = s[:mmain.start()] + "\n" + new_route + "\n" + s[mmain.start():]
    else:
        s = s + "\n" + new_route + "\n"

p.write_text(s, encoding="utf-8")
print(f"[OK] disabled_legacy_decorators={disabled}, added={route_marker}")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sudo systemctl is-active --quiet vsp-ui-8910.service && echo "[OK] service active"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== [DIAG] route count for /api/vsp/top_findings_v1 =="
curl -fsS "$BASE/api/vsp/_diag_topfind_routes_v1" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print("ok=", j.get("ok"), "count=", j.get("count"))
if j.get("rules"):
  print("rules=")
  for r in j["rules"]:
    print(" -", r.get("rule"), "endpoint=", r.get("endpoint"))
PY

RID="${1:-VSP_CI_20251218_114312}"
echo "== [TEST] top_findings_v1 raw =="
curl -sS -D /tmp/top.h -o /tmp/top.b "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=5" || true
sed -n '1,20p' /tmp/top.h
head -c 200 /tmp/top.b; echo

echo "== [TEST] top_findings_v1 parse =="
python3 - <<'PY'
import json, sys
b=open("/tmp/top.b","rb").read().strip()
if not b:
    print("EMPTY_BODY"); sys.exit(2)
try:
    j=json.loads(b.decode("utf-8","replace"))
except Exception as e:
    print("NOT_JSON:", str(e))
    print(b[:200])
    sys.exit(2)
print("ok=",j.get("ok"),"rid=",j.get("rid"),"total=",j.get("total"),"reason=",j.get("reason"))
items=j.get("items") or []
print("items=",len(items))
if items:
    print("first_sev=",items[0].get("severity"),"title=",(items[0].get("title") or "")[:120])
PY

echo "[DONE]"
