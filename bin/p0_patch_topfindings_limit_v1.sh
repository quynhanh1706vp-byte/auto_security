#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_toplimit_${TS}"
echo "[BACKUP] ${APP}.bak_toplimit_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

route_pat = r'(?m)^\s*@.*\(\s*[\'"]\/api\/vsp\/top_findings_v1[\'"]\s*\)\s*$'
m = re.search(route_pat, s)
if not m:
    print("[ERR] cannot find route /api/vsp/top_findings_v1")
    sys.exit(2)

# find def after decorator
after = s[m.end():]
md = re.search(r'(?m)^\s*def\s+([a-zA-Z0-9_]+)\s*\(.*\):\s*$', after)
if not md:
    print("[ERR] cannot find def after decorator")
    sys.exit(2)

fn_name = md.group(1)
def_pos = m.end() + md.end()

# Determine function block end (next def at col 0.. same-ish)
rest = s[def_pos:]
mnext = re.search(r'(?m)^\s*def\s+\w+\s*\(', rest)
end = def_pos + (mnext.start() if mnext else len(rest))
chunk = s[m.start():end]

MARK="VSP_TOPFINDINGS_LIMIT_V1"
if MARK in chunk:
    print("[OK] already patched:", MARK, "fn=", fn_name)
    sys.exit(0)

# detect indent inside function
mindent = re.search(r'(?m)^(\s+)def\s+'+re.escape(fn_name)+r'\b', chunk)
base_ind = mindent.group(1) if mindent else ""
ind = base_ind + "    "

insert = (
f"\n{ind}# {MARK} (respect ?limit=, cap 500)\n"
f"{ind}try:\n"
f"{ind}    _lim = int((request.args.get('limit') or '50').strip())\n"
f"{ind}except Exception:\n"
f"{ind}    _lim = 50\n"
f"{ind}limit = max(1, min(_lim, 500))\n"
)

# Insert right after def line
# Find def line end inside chunk
mdefline = re.search(r'(?m)^\s*def\s+'+re.escape(fn_name)+r'\s*\(.*\):\s*$', chunk)
if not mdefline:
    print("[ERR] cannot locate def line inside chunk")
    sys.exit(2)

pos = mdefline.end()
chunk2 = chunk[:pos] + insert + chunk[pos:]

# Also relax any hard min(limit, 50) within this function chunk
chunk2 = re.sub(r'min\s*\(\s*limit\s*,\s*50\s*\)', 'min(limit, 500)', chunk2)
# If there is "limit = 50" later, keep ours by converting to "limit = limit"
chunk2 = re.sub(r'(?m)^\s*limit\s*=\s*50\s*$', '    # limit already set by VSP_TOPFINDINGS_LIMIT_V1\n    limit = limit', chunk2)

s2 = s[:m.start()] + chunk2 + s[end:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched", MARK, "fn=", fn_name)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting $SVC ..."
  sudo systemctl restart "$SVC" || true
fi

echo "[DONE] now test API: curl ...top_findings_v1?limit=200"
