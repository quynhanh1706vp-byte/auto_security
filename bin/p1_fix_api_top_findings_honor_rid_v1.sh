#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_topfind_honorRid_${TS}"
echo "[BACKUP] ${APP}.bak_topfind_honorRid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_API_TOP_FINDINGS_HONOR_RID_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# 1) locate route decorator for top_findings_v1
m = re.search(r'@app\.route\(\s*[\'"]/api/vsp/top_findings_v1[\'"]', s)
if not m:
    m = re.search(r'@app\.get\(\s*[\'"]/api/vsp/top_findings_v1[\'"]', s)
if not m:
    print("[ERR] cannot find route /api/vsp/top_findings_v1 in vsp_demo_app.py")
    raise SystemExit(2)

# find the def line after decorator
defm = re.search(r'\n(def\s+[A-Za-z0-9_]+\s*\(.*?\)\s*:)', s[m.start():], flags=re.S)
if not defm:
    print("[ERR] cannot find function def after route decorator")
    raise SystemExit(2)

def_start = m.start() + defm.start(1) + 1  # points at 'def ...'
# find function body start (first newline after def line)
def_line_end = s.find("\n", def_start)
if def_line_end < 0:
    print("[ERR] malformed def line")
    raise SystemExit(2)

# determine indent of function body
# body begins at next non-empty line; we will inject right after def line with 4 spaces
inject_head = (
    f"\n    # ===== {MARK} =====\n"
    f"    _rid_q = (request.args.get('rid') or '').strip()\n"
    f"    if _rid_q and _rid_q.upper() in ('YOUR_RID','NONE','NULL'):\n"
    f"        _rid_q = ''\n"
    f"    if _rid_q:\n"
    f"        import re as _re\n"
    f"        if not _re.match(r'^[A-Za-z0-9_.:-]{{6,120}}$', _rid_q):\n"
    f"            return jsonify({{'ok': False, 'error': 'invalid rid'}}), 400\n"
)

# inject header after def line
s2 = s[:def_line_end] + inject_head + s[def_line_end:]

# 2) identify the function block end (next decorator at col 0 or next def at col 0)
# work from after injected head
start_scan = def_line_end + len(inject_head)
endm = re.search(r'\n(@app\.(?:route|get|post|put|delete)\(|def\s+)[^\n]*', s2[start_scan:])
if endm:
    func_end = start_scan + endm.start()
else:
    func_end = len(s2)

func_block = s2[def_start:func_end]

# 3) after every assignment that sets rid, re-apply rid from query
# match lines like: "rid = ..." OR "rid, src = ..."
lines = func_block.splitlines(True)
out = []
rid_assign_re = re.compile(r'^(\s*)(rid\s*(?:,|\s)*=)', re.M)

for i, line in enumerate(lines):
    out.append(line)
    mm = rid_assign_re.match(line)
    if mm:
        indent = mm.group(1)
        # avoid duplicating if already followed by our guard
        next_line = lines[i+1] if i+1 < len(lines) else ""
        if MARK not in next_line and "_rid_q" not in next_line:
            out.append(
                f"{indent}# {MARK}: force rid from query when provided\n"
                f"{indent}if _rid_q:\n"
                f"{indent}    rid = _rid_q\n"
            )

func_block2 = "".join(out)
s3 = s2[:def_start] + func_block2 + s2[func_end:]

p.write_text(s3, encoding="utf-8")
print("[OK] patched:", MARK)
PY

# quick syntax check
python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile PASS"

# restart service
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted: $SVC"
else
  echo "[WARN] systemctl not found; restart app manually"
fi

echo "[DONE] Re-test: curl /api/vsp/top_findings_v1?rid=... must echo same rid"
