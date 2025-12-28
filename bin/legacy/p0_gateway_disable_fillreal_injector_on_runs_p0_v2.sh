#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need curl

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_disable_fillreal_runs_${TS}"
echo "[BACKUP] ${F}.bak_disable_fillreal_runs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_DISABLE_FILLREAL_INJECTOR_ON_RUNS_V2"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# 1) ensure helper exists (global)
if "_vsp_is_runs_path" not in s:
    # put near top after imports (simple & safe)
    lines = s.splitlines(True)
    ins_at = 0
    for i, ln in enumerate(lines[:400]):
        if re.match(r'^\s*(from\s+\S+\s+import\s+|import\s+\S+)', ln) or re.match(r'^\s*#', ln) or ln.strip()=="":
            ins_at = i+1
            continue
        break
    helper = f"""
def _vsp_is_runs_path(environ):
    try:
        path = (environ.get("PATH_INFO") or "")
    except Exception:
        path = ""
    return path == "/runs" or path.startswith("/runs/")

# {MARK}
"""
    lines.insert(ins_at, helper)
    s = "".join(lines)
else:
    # still stamp marker once
    s += f"\n# {MARK}\n"

# 2) patch all injector IF lines tagged with VSP_P0_SKIP_FILLREAL_ON_RUNS_MARKER_V1
out_lines = []
n = 0
for ln in s.splitlines(True):
    if "VSP_P0_SKIP_FILLREAL_ON_RUNS_MARKER_V1" in ln and ln.lstrip().startswith("if "):
        if "_vsp_is_runs_path" not in ln:
            # insert guard before the first colon that ends the condition
            # keep comment as-is
            parts = ln.split(":", 1)
            if len(parts) == 2:
                head, tail = parts[0], parts[1]
                head2 = head.rstrip() + " and (not _vsp_is_runs_path(environ))"
                ln = head2 + ":" + tail
                n += 1
    out_lines.append(ln)

s2 = "".join(out_lines)
p.write_text(s2, encoding="utf-8")
print(f"[OK] patched injector IF-lines: {n}")
PY

rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

echo "== verify /runs no fillreal injector & no marker =="
curl -sS http://127.0.0.1:8910/runs -o /tmp/runs.html
grep -n "VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY" /tmp/runs.html && echo "[ERR] marker still present" || echo "[OK] no marker"
grep -n "vsp_fill_real_data_5tabs_p1_v1\\.js" /tmp/runs.html && echo "[ERR] still injected" || echo "[OK] no fillreal on /runs"

echo "== show any remaining injector lines in gateway =="
grep -n "VSP_P0_SKIP_FILLREAL_ON_RUNS_MARKER_V1" -n wsgi_vsp_ui_gateway.py | head -n 20 || true
