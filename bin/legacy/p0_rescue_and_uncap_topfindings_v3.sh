#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"

pick_backup(){
  # prefer the rescue-point you just created; else fall back
  ls -1t ${APP}.bak_top_uncap50_v2_* 2>/dev/null | head -n 1 || true
}
B="$(pick_backup)"
if [ -z "${B:-}" ]; then
  B="$(ls -1t ${APP}.bak_toplimit_* 2>/dev/null | head -n 1 || true)"
fi
if [ -z "${B:-}" ]; then
  echo "[ERR] no backup found (bak_top_uncap50_v2_* or bak_toplimit_*)"
  exit 2
fi

cp -f "$B" "$APP"
echo "[RESTORE] $APP <= $B"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

fn = "api_vsp_top_findings_v1"
m = re.search(rf'(?m)^(?P<ind>\s*)def\s+{re.escape(fn)}\s*\(', s)
if not m:
    print("[ERR] cannot find function:", fn)
    sys.exit(2)

base_ind = m.group("ind")
start = m.start()

# find end of function: next def with indent <= base_ind (typically same level)
rest = s[m.end():]
mnext = re.search(r'(?m)^(?P<ind>\s*)def\s+\w+\s*\(', rest)
end = m.end() + (mnext.start() if mnext else len(rest))

chunk = s[start:end]

MARK = "VSP_TOPFINDINGS_UNCAP50_V3"
if MARK in chunk:
    print("[OK] already patched:", MARK)
    sys.exit(0)

body_ind = base_ind + "    "

# 1) ensure limit exists near top of function (insert right after def line)
mdefline = re.search(rf'(?m)^{re.escape(base_ind)}def\s+{re.escape(fn)}\s*\(.*\):\s*$', chunk)
if not mdefline:
    print("[ERR] cannot locate def line inside chunk")
    sys.exit(2)

insert_limit = (
    f"\n{body_ind}# {MARK}: respect ?limit= (cap 500)\n"
    f"{body_ind}try:\n"
    f"{body_ind}    _lim = int((request.args.get('limit') or '50').strip())\n"
    f"{body_ind}except Exception:\n"
    f"{body_ind}    _lim = 50\n"
    f"{body_ind}limit = max(1, min(_lim, 500))\n"
)
# avoid double insert if a prior 'limit =' already exists very early
early = chunk[mdefline.end():mdefline.end()+1200]
if re.search(r'(?m)^\s*limit\s*=\s*max\(', early) is None:
    chunk = chunk[:mdefline.end()] + insert_limit + chunk[mdefline.end():]

# 2) replace common hard caps 50 inside this function chunk
repls = [
    (r'\[\s*:\s*50\s*\]', '[:limit]'),
    (r'\[\s*0\s*:\s*50\s*\]', '[0:limit]'),
    (r'range\s*\(\s*50\s*\)', 'range(limit)'),
    (r'(\b(top_n|max_items|limit|n)\s*=\s*)50\b', r'\1limit'),
    (r'min\s*\(\s*limit\s*,\s*50\s*\)', 'min(limit, 500)'),
]
for pat, rep in repls:
    chunk = re.sub(pat, rep, chunk)

# 3) final guard before last return jsonify
lines = chunk.splitlines(True)
ret_idx = None
for i in range(len(lines)-1, -1, -1):
    if re.search(r'^\s*return\s+jsonify\s*\(', lines[i]):
        ret_idx = i
        break
if ret_idx is not None:
    guard = (
        f"{body_ind}# {MARK} final guard: enforce items[:limit]\n"
        f"{body_ind}try:\n"
        f"{body_ind}    if 'items' in locals() and isinstance(items, (list, tuple)):\n"
        f"{body_ind}        items = list(items)[:limit]\n"
        f"{body_ind}except Exception:\n"
        f"{body_ind}    pass\n"
    )
    # insert guard only once
    if MARK not in "".join(lines[max(0,ret_idx-40):ret_idx]):
        lines.insert(ret_idx, guard)
chunk = "".join(lines)

# 4) stamp marker as a safe comment line (NOT on def line)
chunk = chunk.replace(mdefline.group(0), mdefline.group(0) + f"\n{body_ind}# {MARK} patched", 1)

s2 = s[:start] + chunk + s[end:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched", MARK, "in", fn)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile vsp_demo_app.py"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting $SVC ..."
  sudo systemctl restart "$SVC" || true
fi

echo "[PROBE] top_findings_v1 limit=200 ..."
curl -sS "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=200" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"total=",j.get("total"),"items_len=",len(j.get("items") or []))'

echo "[DONE] If items_len >= 200 => PASS. (Ctrl+F5 UI)"
