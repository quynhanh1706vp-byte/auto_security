#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_topfind_${TS}"
echo "[BACKUP] ${APP}.bak_topfind_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

def ensure_import(modline: str):
    global s
    if re.search(r'^\s*' + re.escape(modline) + r'\s*$', s, flags=re.M):
        return
    # insert after first import block
    m = re.search(r'^(import .*|from .* import .*)\n', s, flags=re.M)
    if not m:
        s = modline + "\n" + s
        return
    # insert after consecutive import lines at top
    m2 = re.search(r'^(?:import .*|from .* import .*)(?:\n(?:import .*|from .* import .*))*\n', s, flags=re.M)
    if m2:
        s = s[:m2.end()] + modline + "\n" + s[m2.end():]
    else:
        s = s[:m.end()] + modline + "\n" + s[m.end():]

# minimal imports we rely on
for line in [
    "import os",
    "import json",
    "import glob",
    "import time",
    "from datetime import datetime",
]:
    ensure_import(line)

# Helper block (idempotent)
helper_marker = "VSP_P0_TOP_FINDINGS_HELPERS_V1"
helper_block = f"""
# {helper_marker}
def _vsp__sanitize_path(pth: str) -> str:
    if not pth:
        return ""
    # strip absolute prefixes + keep last chunks only (commercial-safe)
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
    # keep it broad (works across CI/local layouts) but no leak in API response
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
    # exact match first
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

def _vsp__load_unified_findings_anywhere(rid: str, limit: int):
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
    # place after imports (roughly)
    ins = re.search(r'^(?:import .*|from .* import .*)(?:\n(?:import .*|from .* import .*))*\n', s, flags=re.M)
    if ins:
        s = s[:ins.end()] + helper_block + "\n" + s[ins.end():]
    else:
        s = helper_block + "\n" + s

# Ensure we have `re` module for helpers (sanitize uses re)
if not re.search(r'^\s*import re\s*$', s, flags=re.M):
    ensure_import("import re")

route_pat = r'@app\.route\(\s*[\'"]\/api\/vsp\/top_findings_v1[\'"][\s\S]*?\)\s*\n(?:@app\.route|\Z)'
m = re.search(route_pat, s, flags=re.M)
new_route = r'''
@app.route("/api/vsp/top_findings_v1", methods=["GET"])
def api_vsp_top_findings_v1():
    try:
        rid = (request.args.get("rid") or "").strip()
        limit = int(request.args.get("limit") or "5")
        if limit < 1: limit = 1
        if limit > 50: limit = 50

        if not rid:
            # try existing rid_latest endpoint helper if present; else scan filesystem
            rid = ""
            try:
                # if app has a function returning latest rid, use it (best effort)
                if "api_vsp_rid_latest" in globals():
                    j = api_vsp_rid_latest()
                    # j can be Response; fallback to filesystem scan if not usable
                    rid = ""
            except Exception:
                rid = ""
            if not rid:
                rid = _vsp__pick_latest_rid()

        if not rid:
            return jsonify({"ok": False, "rid": "", "total": 0, "items": [], "reason": "NO_RUNS"}), 200

        findings, errc = _vsp__load_unified_findings_anywhere(rid, limit)
        if findings is None:
            # commercial-safe: no absolute path exposure
            return jsonify({"ok": False, "rid": rid, "total": 0, "items": [], "reason": errc}), 200

        # normalize + sort by severity weight desc
        items = []
        for f in (findings or []):
            if not isinstance(f, dict):
                continue
            it = {
                "tool": f.get("tool"),
                "severity": (f.get("severity") or "").upper(),
                "title": f.get("title"),
                "cwe": f.get("cwe"),
                "rule_id": f.get("rule_id") or f.get("check_id") or f.get("id"),
                "file": _vsp__sanitize_path(f.get("file") or f.get("path") or ""),
                "line": f.get("line") or f.get("start_line") or f.get("line_start"),
            }
            items.append(it)

        items.sort(key=lambda x: (_vsp__sev_weight(x.get("severity")), str(x.get("title") or "")), reverse=True)
        out = {
            "ok": True,
            "rid": rid,
            "total": len(items),
            "items": items[:limit],
            "ts": datetime.utcnow().isoformat() + "Z",
        }
        return jsonify(out), 200
    except Exception:
        # commercial-safe error; keep detail out of API
        return jsonify({"ok": False, "rid": (request.args.get("rid") or ""), "total": 0, "items": [], "reason": "EXCEPTION"}), 200
'''

def insert_route(text: str) -> str:
    # insert before the last route group or before main guard
    mmain = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', text, flags=re.M)
    if mmain:
        return text[:mmain.start()] + "\n" + new_route + "\n" + text[mmain.start():]
    return text + "\n" + new_route + "\n"

if m:
    # Replace existing top_findings route block
    s2 = re.sub(r'@app\.route\(\s*[\'"]\/api\/vsp\/top_findings_v1[\'"][\s\S]*?(?=\n@app\.route|\Z)', new_route.strip()+"\n", s, flags=re.M)
    s = s2
else:
    s = insert_route(s)

p.write_text(s, encoding="utf-8")
print("[OK] patched top_findings_v1 route + helpers")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

# FE singleflight/cache for top findings (best-effort; patch both common dashboard js)
patch_js(){
  local JS="$1"
  [ -f "$JS" ] || return 0
  cp -f "$JS" "${JS}.bak_topfind_sf_${TS}"
  echo "[BACKUP] ${JS}.bak_topfind_sf_${TS}"

  python3 - "$JS" <<'PY'
import sys, re
from pathlib import Path

js = Path(sys.argv[1])
s = js.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_TOPFIND_SF_CACHE_V1"
block = r'''
/* VSP_P0_TOPFIND_SF_CACHE_V1 */
window.__vspSF = window.__vspSF || {};
window.__vspCache = window.__vspCache || {};
window.__vspSFRun = function(key, fn){
  if(window.__vspSF[key]) return window.__vspSF[key];
  const p = Promise.resolve().then(fn).finally(()=>{ try{ delete window.__vspSF[key]; }catch(e){} });
  window.__vspSF[key]=p; return p;
};
window.__vspCacheGet = function(key, ttlMs){
  const o = window.__vspCache[key]; if(!o) return null;
  if(Date.now() - o.ts > ttlMs) return null;
  return o.val;
};
window.__vspCacheSet = function(key, val){
  window.__vspCache[key] = {ts: Date.now(), val: val};
  return val;
};
'''

if marker not in s:
    # prepend near top
    s = block + "\n" + s

# patch common fetch function names if present; otherwise leave
# Replace direct calls like /api/vsp/top_findings_v1?limit=5 to include rid and cache/sf wrapper
# We do a conservative replace to avoid breaking other code.
s = re.sub(
    r'(["\'])\/api\/vsp\/top_findings_v1\?limit=([0-9]+)\1',
    r'\1/api/vsp/top_findings_v1?rid=\'+encodeURIComponent((window.__vspRid||window.__VSP_RID||""))+\'&limit=\2\1',
    s
)

# If there is a function that loads top findings, wrap fetch in cache/sf when we can detect it
# Heuristic: replace fetch("/api/vsp/top_findings_v1?...") with singleflight+cache
s = re.sub(
    r'fetch\(([^)]*\/api\/vsp\/top_findings_v1[^)]*)\)',
    r'window.__vspSFRun("topfind:"+String(window.__vspRid||window.__VSP_RID||""), function(){'
    r'  var ck="topfind:"+String(window.__vspRid||window.__VSP_RID||"");'
    r'  var c=window.__vspCacheGet(ck, 30000);'
    r'  if(c) return Promise.resolve({json:()=>Promise.resolve(c)});'
    r'  return fetch(\1).then(function(r){return r.json().then(function(j){window.__vspCacheSet(ck,j); return {json:()=>Promise.resolve(j)};});});'
    r'})',
    s
)

js.write_text(s, encoding="utf-8")
print("[OK] patched JS:", js)
PY
}

patch_js "static/js/vsp_dashboard_luxe_v1.js"
patch_js "static/js/vsp_dash_only_v1.js"

# restart service if present
if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet vsp-ui-8910.service; then
    sudo systemctl restart vsp-ui-8910.service
    echo "[OK] restarted vsp-ui-8910.service"
  else
    echo "[WARN] service vsp-ui-8910.service not active; skip restart"
  fi
else
  echo "[WARN] no systemctl; restart manually if needed"
fi

# quick self-test (no failure if rid missing)
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-VSP_CI_20251218_114312}"
echo "== [TEST] top_findings_v1 =="
curl -fsS "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=5" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print("ok=",j.get("ok"),"rid=",j.get("rid"),"total=",j.get("total"))
items=j.get("items") or []
print("items=",len(items))
if items:
  print("first_sev=",items[0].get("severity"),"title=", (items[0].get("title") or "")[:90])
PY

echo "[DONE] If ok=False with reason=UNIFIED_NOT_FOUND, verify that this RID has findings_unified.json under run dir."
