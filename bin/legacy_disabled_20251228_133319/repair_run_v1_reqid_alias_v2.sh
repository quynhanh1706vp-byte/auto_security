#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.broken_reqid_alias_${TS}"
echo "[BROKEN_BACKUP] $F.broken_reqid_alias_${TS}"

# 1) Restore from latest pre-patch backup (bak_reqid_alias_*)
BK="$(ls -1t ${F}.bak_reqid_alias_* 2>/dev/null | head -n1 || true)"
if [ -z "$BK" ]; then
  echo "[ERR] no backup found: ${F}.bak_reqid_alias_*"
  exit 2
fi

cp -f "$BK" "$F"
echo "[RESTORE] from $BK"

# 2) Re-patch safely: insert alias block ONLY inside def run_v1()
python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_RUNV1_ADD_REQUEST_ID_ALIAS_V2_SAFE"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

m = re.search(r"^def\s+run_v1\s*\(\s*\)\s*:\s*$", txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find: def run_v1():")

start = m.start()

# find end of function: next top-level def after run_v1
m2 = re.search(r"^def\s+\w+\s*\(", txt[m.end():], flags=re.M)
end = (m.end() + m2.start()) if m2 else len(txt)

fn = txt[start:end]

# find the run_v1 return that returns __resp, 200
ret = re.search(r"(?m)^(?P<indent>[ \t]*)return\s+__resp\s*,\s*200\s*$", fn)
if not ret:
    raise SystemExit("[ERR] cannot find 'return __resp, 200' inside run_v1()")

indent = ret.group("indent")
# Use 2-space nesting (file style in your snippet is 2 spaces)
i1 = indent
i2 = indent + "  "
i3 = indent + "    "

inject = (
    f"{i1}# {MARK}\n"
    f"{i1}try:\n"
    f"{i2}if isinstance(__resp, dict):\n"
    f"{i3}__resp.setdefault('request_id', __resp.get('req_id') or req_id)\n"
    f"{i3}__resp.setdefault('req_id', __resp.get('request_id') or req_id)\n"
    f"{i1}except Exception:\n"
    f"{i2}pass\n"
)

# insert immediately before the return line
ins_at = start + ret.start()
txt2 = txt[:ins_at] + inject + txt[ins_at:]

p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
