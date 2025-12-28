#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need curl

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_topfind_forceRidEarly_${TS}"
echo "[BACKUP] ${APP}.bak_topfind_forceRidEarly_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_API_TOP_FINDINGS_FORCE_RID_EARLYRETURN_V2"
if marker in s:
    print("[OK] already patched:", marker)
    raise SystemExit(0)

# find decorator line containing top_findings_v1
m = re.search(r'(?m)^\s*@[^\n]*top_findings_v1[^\n]*\n', s)
if not m:
    print("[ERR] cannot find decorator for top_findings_v1")
    raise SystemExit(2)

# find def line after that decorator block
start = m.start()
# include contiguous decorators above this (rare) - go upward
lines = s.splitlines(True)
# compute line index for m.start()
pos = 0
idx = 0
for i, ln in enumerate(lines):
    if pos <= start < pos + len(ln):
        idx = i
        break
    pos += len(ln)

# move up to include any @ decorators directly above
dec_start = idx
while dec_start-1 >= 0 and lines[dec_start-1].lstrip().startswith("@"):
    dec_start -= 1

# locate def line
j = idx
while j < len(lines) and not lines[j].lstrip().startswith("def "):
    j += 1
if j >= len(lines):
    print("[ERR] cannot find def after decorator")
    raise SystemExit(2)

def_line = lines[j]
def_indent = re.match(r'^(\s*)', def_line).group(1)
body_indent = def_indent + "    "

# determine insertion point: after def line + optional docstring
k = j + 1
def is_blank(ln): return ln.strip() == ""
# skip blank lines
while k < len(lines) and is_blank(lines[k]):
    k += 1
# skip docstring if present
if k < len(lines) and lines[k].lstrip().startswith(('"""',"'''")):
    q = lines[k].lstrip()[:3]
    k += 1
    while k < len(lines):
        if q in lines[k]:
            k += 1
            break
        k += 1

inject = f"""{body_indent}# ===== {marker} =====
{body_indent}# If caller provides explicit rid, honor it STRICTLY (no AUTO/GLOBAL_BEST override).
{body_indent}try:
{body_indent}    _rid_req = (request.args.get("rid","") or "").strip()
{body_indent}except Exception:
{body_indent}    _rid_req = ""
{body_indent}if _rid_req and _rid_req not in ("YOUR_RID","__RID__","RID","NONE","None","null","NULL"):
{body_indent}    import os, json, glob
{body_indent}    try:
{body_indent}        _limit = request.args.get("limit","")
{body_indent}        _limit = int(_limit) if str(_limit).strip().isdigit() else 20
{body_indent}    except Exception:
{body_indent}        _limit = 20
{body_indent}    if _limit < 1: _limit = 1
{body_indent}    if _limit > 200: _limit = 200
{body_indent}    # Locate findings_unified.json for this RID (no internal HTTP call to avoid deadlock)
{body_indent}    _roots = [
{body_indent}        "/home/test/Data/SECURITY_BUNDLE/out_ci",
{body_indent}        "/home/test/Data/SECURITY_BUNDLE/out",
{body_indent}        "/home/test/Data/SECURITY-10-10-v4/out_ci",
{body_indent}        "/home/test/Data/SECURITY-10-10-v4/out",
{body_indent}    ]
{body_indent}    _rel = [
{body_indent}        "reports/findings_unified.json",
{body_indent}        "report/findings_unified.json",
{body_indent}        "findings_unified.json",
{body_indent}    ]
{body_indent}    _found = None
{body_indent}    for r in _roots:
{body_indent}        d = os.path.join(r, _rid_req)
{body_indent}        if os.path.isdir(d):
{body_indent}            for rel in _rel:
{body_indent}                fp = os.path.join(d, rel)
{body_indent}                if os.path.isfile(fp):
{body_indent}                    _found = fp
{body_indent}                    break
{body_indent}        if _found:
{body_indent}            break
{body_indent}    # fallback: glob search (bounded)
{body_indent}    if not _found:
{body_indent}        for r in _roots:
{body_indent}            pat = os.path.join(r, _rid_req, "**", "findings_unified.json")
{body_indent}            hits = glob.glob(pat, recursive=True)
{body_indent}            if hits:
{body_indent}                _found = hits[0]
{body_indent}                break
{body_indent}    if not _found:
{body_indent}        return jsonify({{"ok": True, "rid": _rid_req, "run_id": None, "items": [], "total": 0, "degraded": True, "reason": "missing findings_unified.json for rid"}})
{body_indent}    try:
{body_indent}        with open(_found, "r", encoding="utf-8", errors="replace") as f:
{body_indent}            j = json.load(f)
{body_indent}    except Exception as e:
{body_indent}        return jsonify({{"ok": True, "rid": _rid_req, "run_id": None, "items": [], "total": 0, "degraded": True, "reason": "cannot parse findings_unified.json", "error": str(e)[:160]}})
{body_indent}    arr = j.get("findings") if isinstance(j, dict) else None
{body_indent}    if arr is None and isinstance(j, list):
{body_indent}        arr = j
{body_indent}    if not isinstance(arr, list):
{body_indent}        arr = []
{body_indent}    _rank = {{"CRITICAL":0,"HIGH":1,"MEDIUM":2,"LOW":3,"INFO":4,"TRACE":5}}
{body_indent}    def _key(x):
{body_indent}        try:
{body_indent}            sev = (x.get("severity") or "").upper()
{body_indent}        except Exception:
{body_indent}            sev = ""
{body_indent}        return (_rank.get(sev, 9))
{body_indent}    arr.sort(key=_key)
{body_indent}    items = []
{body_indent}    for x in arr[:_limit]:
{body_indent}        try:
{body_indent}            items.append({{
{body_indent}                "severity": (x.get("severity") or "").upper(),
{body_indent}                "title": x.get("title") or x.get("name") or "",
{body_indent}                "tool": x.get("tool") or "",
{body_indent}            }})
{body_indent}        except Exception:
{body_indent}            pass
{body_indent}    return jsonify({{"ok": True, "rid": _rid_req, "run_id": None, "items": items, "total": len(items), "from": "force_rid_local"}})

"""

lines.insert(k, inject)

out = "".join(lines)
p.write_text(out, encoding="utf-8")
print("[OK] inserted marker:", marker)
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile PASS"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted: $SVC"
else
  echo "[WARN] systemctl not found; restart service manually"
fi

echo
echo "== [TEST] rid must be honored =="
RID="${1:-VSP_CI_20251218_114312}"
curl -fsS "$BASE/api/vsp/top_findings_v1?limit=5&rid=$RID" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"rid=",j.get("rid"),"items_len=",len(j.get("items") or []),"from=",j.get("from"))'
