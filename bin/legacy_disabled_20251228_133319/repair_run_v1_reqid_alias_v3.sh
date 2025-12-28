#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.broken_reqid_alias_${TS}"
echo "[BROKEN_BACKUP] $F.broken_reqid_alias_${TS}"

# restore latest pre-patch backup
BK="$(ls -1t ${F}.bak_reqid_alias_* 2>/dev/null | head -n1 || true)"
if [ -z "$BK" ]; then
  echo "[ERR] no backup found: ${F}.bak_reqid_alias_*"
  exit 2
fi
cp -f "$BK" "$F"
echo "[RESTORE] from $BK"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_RUNV1_ADD_REQUEST_ID_ALIAS_V3_SAFE"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# find def run_v1( ... ) with any args + any indent
m = re.search(r"^(?P<dindent>[ \t]*)def\s+run_v1\s*\(", txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find: def run_v1(")

dindent = m.group("dindent")
start = m.start()

# find end of function: next def at SAME indent
m2 = re.search(r"^" + re.escape(dindent) + r"def\s+\w+\s*\(", txt[m.end():], flags=re.M)
end = (m.end() + m2.start()) if m2 else len(txt)

fn = txt[start:end]

# find LAST return-line referencing __resp (covers: return __resp, 200 / return jsonify(__resp),200 / return __resp)
rets = list(re.finditer(r"(?m)^(?P<indent>[ \t]*)return\b[^\n]*\b__resp\b[^\n]*$", fn))
if not rets:
    # fallback: look for "return jsonify(" then "__resp" on same line
    rets = list(re.finditer(r"(?m)^(?P<indent>[ \t]*)return\b[^\n]*jsonify\([^\n]*\b__resp\b[^\n]*\)[^\n]*$", fn))
if not rets:
    raise SystemExit("[ERR] cannot find a return line containing __resp inside run_v1()")

ret = rets[-1]
rindent = ret.group("indent")
i1 = rindent
i2 = rindent + "  "
i3 = rindent + "    "

inject = (
    f"{i1}# {MARK}\n"
    f"{i1}try:\n"
    f"{i2}if isinstance(__resp, dict):\n"
    f"{i3}__resp.setdefault('request_id', __resp.get('req_id') or locals().get('req_id'))\n"
    f"{i3}__resp.setdefault('req_id', __resp.get('request_id') or locals().get('req_id'))\n"
    f"{i1}except Exception:\n"
    f"{i2}pass\n"
)

ins_at = start + ret.start()
txt2 = txt[:ins_at] + inject + txt[ins_at:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
