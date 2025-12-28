#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
cp -f "$APP" "${APP}.bak_force_toplimit_v4_${TS}"
echo "[BACKUP] ${APP}.bak_force_toplimit_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

fn = "api_vsp_top_findings_v1"

mdef = re.search(rf'(?m)^(?P<ind>\s*)def\s+{re.escape(fn)}\s*\(.*\):\s*$', s)
if not mdef:
    print("[ERR] cannot find def", fn)
    sys.exit(2)

base_ind = mdef.group("ind")
start = mdef.start()

# end = next def with indent <= base_ind (best effort: next def at same indent)
rest = s[mdef.end():]
mnext = re.search(rf'(?m)^{re.escape(base_ind)}def\s+\w+\s*\(', rest)
end = mdef.end() + (mnext.start() if mnext else len(rest))

chunk = s[start:end]
MARK = "VSP_FORCE_TOPLIMIT_V4"
if MARK in chunk:
    print("[OK] already patched:", MARK)
    sys.exit(0)

body_ind = base_ind + "    "

# 1) Ensure 'limit' parsing block exists right after def line
defline_end = re.search(rf'(?m)^{re.escape(base_ind)}def\s+{re.escape(fn)}\s*\(.*\):\s*$', chunk).end()
early = chunk[defline_end:defline_end+1500]
if "request.args.get('limit')" not in early and 'request.args.get("limit")' not in early:
    limit_block = (
        f"\n{body_ind}# {MARK}: respect ?limit= (cap 500)\n"
        f"{body_ind}try:\n"
        f"{body_ind}    _lim = int((request.args.get('limit') or '50').strip())\n"
        f"{body_ind}except Exception:\n"
        f"{body_ind}    _lim = 50\n"
        f"{body_ind}limit = max(1, min(_lim, 500))\n"
    )
    chunk = chunk[:defline_end] + limit_block + chunk[defline_end:]

# 2) Replace obvious hardcaps inside function
repls = [
    # hardcoded 50 slices / loops
    (r'\[\s*:\s*50\s*\]', '[:limit]'),
    (r'\[\s*0\s*:\s*50\s*\]', '[0:limit]'),
    (r'range\s*\(\s*50\s*\)', 'range(limit)'),
    # kwargs 50
    (r'(\b(top_n|max_items|n|limit)\s*=\s*)50\b', r'\1limit'),
    # min(limit,50)
    (r'min\s*\(\s*limit\s*,\s*50\s*\)', 'min(limit, 500)'),
]
for pat, rep in repls:
    chunk = re.sub(pat, rep, chunk)

# 3) Fix hardcoded JSON fields: "limit_applied": 50  (both ' and ")
chunk = re.sub(r'(["\']limit_applied["\']\s*:\s*)50\b', r'\1limit_applied', chunk)
chunk = re.sub(r'(?m)^\s*limit_applied\s*=\s*50\s*$', f"{body_ind}limit_applied = limit", chunk)

# 4) Insert FINALIZE block before LAST return jsonify(...)
lines = chunk.splitlines(True)
ret_i = None
for i in range(len(lines)-1, -1, -1):
    if re.search(r'^\s*return\s+jsonify\s*\(', lines[i]):
        ret_i = i
        break

finalize = (
    f"{body_ind}# {MARK} finalize: enforce limit_applied/items/items_truncated\n"
    f"{body_ind}try:\n"
    f"{body_ind}    limit_applied = int(locals().get('limit', 50))\n"
    f"{body_ind}    if limit_applied < 1:\n"
    f"{body_ind}        limit_applied = 1\n"
    f"{body_ind}    if limit_applied > 500:\n"
    f"{body_ind}        limit_applied = 500\n"
    f"{body_ind}    if 'items' in locals() and isinstance(items, (list, tuple)):\n"
    f"{body_ind}        items = list(items)\n"
    f"{body_ind}    else:\n"
    f"{body_ind}        items = []\n"
    f"{body_ind}    if len(items) > limit_applied:\n"
    f"{body_ind}        items = items[:limit_applied]\n"
    f"{body_ind}    _total = locals().get('total', None)\n"
    f"{body_ind}    if isinstance(_total, int):\n"
    f"{body_ind}        items_truncated = bool(_total > len(items))\n"
    f"{body_ind}except Exception:\n"
    f"{body_ind}    pass\n"
)

if ret_i is not None:
    # avoid double insert
    window = "".join(lines[max(0, ret_i-60):ret_i])
    if MARK not in window:
        lines.insert(ret_i, finalize)
chunk = "".join(lines)

# 5) Stamp marker safely (as standalone comment, not touching def syntax)
stamp = f"{body_ind}# {MARK} patched\n"
if stamp not in chunk[:2000]:
    chunk = chunk[:defline_end] + "\n" + stamp + chunk[defline_end:]

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

echo "[PROBE] expect items_len=200 and limit_applied=200 ..."
curl -sS "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=200" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"total=",j.get("total"),"limit_applied=",j.get("limit_applied"),"items_len=",len(j.get("items") or []),"items_truncated=",j.get("items_truncated"))'
