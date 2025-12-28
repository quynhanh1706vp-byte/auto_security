#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_top_uncap50_v2_${TS}"
echo "[BACKUP] ${APP}.bak_top_uncap50_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

fn="api_vsp_top_findings_v1"

# locate function block
mdef = re.search(rf'(?m)^\s*def\s+{re.escape(fn)}\s*\(.*\):\s*$', s)
if not mdef:
    print("[ERR] cannot find def", fn)
    sys.exit(2)

start = mdef.start()
rest = s[mdef.end():]
mnext = re.search(r'(?m)^\s*def\s+\w+\s*\(', rest)
end = mdef.end() + (mnext.start() if mnext else len(rest))
chunk = s[start:end]

MARK="VSP_TOPFINDINGS_UNCAP50_V2"
if MARK in chunk:
    print("[OK] already patched:", MARK)
    sys.exit(0)

# Ensure 'limit' exists near top of function (keep/insert)
if re.search(r'(?m)^\s*limit\s*=\s*max\(', chunk) is None and re.search(r'(?m)^\s*limit\s*=\s*', chunk) is None:
    # infer indent of body
    ind = "    "
    m_ind = re.search(rf'(?m)^(?P<ind>\s*)def\s+{re.escape(fn)}\b', chunk)
    base = m_ind.group("ind") if m_ind else ""
    ind = base + "    "
    insert = (
        f"\n{ind}# {MARK}: respect ?limit= (cap 500)\n"
        f"{ind}try:\n"
        f"{ind}    _lim = int((request.args.get('limit') or '50').strip())\n"
        f"{ind}except Exception:\n"
        f"{ind}    _lim = 50\n"
        f"{ind}limit = max(1, min(_lim, 500))\n"
    )
    chunk = chunk[:mdef.end()-start] + insert + chunk[mdef.end()-start:]

# Replace common hard caps inside function
repls = [
    # slicing
    (r'\[\s*:\s*50\s*\]', '[:limit]'),
    (r'\[\s*0\s*:\s*50\s*\]', '[0:limit]'),
    # range
    (r'range\s*\(\s*50\s*\)', 'range(limit)'),
    # function call kwargs
    (r'(\b(top_n|max_items|limit|n)\s*=\s*)50\b', r'\1limit'),
    # min(limit,50) -> min(limit,500)
    (r'min\s*\(\s*limit\s*,\s*50\s*\)', 'min(limit, 500)'),
]
for pat, rep in repls:
    chunk = re.sub(pat, rep, chunk)

# As a final guard: force items slicing before return jsonify (best effort)
# Find last "return jsonify(" in chunk
mret = None
for m in re.finditer(r'(?m)^\s*return\s+jsonify\s*\(', chunk):
    mret = m
if mret and MARK not in chunk:
    # detect indentation
    mline = re.search(r'(?m)^(?P<ind>\s*)return\s+jsonify\s*\(', chunk[mret.start():])
    ind = mline.group("ind") if mline else "    "
    guard = (
        f"{ind}# {MARK} final guard: enforce items[:limit]\n"
        f"{ind}try:\n"
        f"{ind}    if 'items' in locals() and isinstance(items, (list, tuple)):\n"
        f"{ind}        items = list(items)[:limit]\n"
        f"{ind}except Exception:\n"
        f"{ind}    pass\n"
    )
    chunk = chunk[:mret.start()] + guard + chunk[mret.start():]

# Stamp marker near top
chunk = chunk.replace(f"def {fn}", f"def {fn}  # {MARK}", 1)

s2 = s[:start] + chunk + s[end:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched", MARK, "in", fn)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting $SVC ..."
  sudo systemctl restart "$SVC" || true
fi

echo "[DONE] test now: /api/vsp/top_findings_v1?limit=200"
