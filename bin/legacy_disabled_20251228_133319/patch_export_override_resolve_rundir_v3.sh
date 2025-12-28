#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_export_resolve_rundir_v3_${TS}"
echo "[BACKUP] $F.bak_export_resolve_rundir_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

m = re.search(r'(?m)^(?P<ind>\s*)def\s+_vsp_export_v3_override\s*\([^)]*\)\s*:\s*$', s)
if not m:
    raise SystemExit("[ERR] cannot find def _vsp_export_v3_override")

ind = m.group("ind")
start = m.start()
lines = s.splitlines(True)

# locate def line idx
def_line_idx=None
pos=0
for i,ln in enumerate(lines):
    if pos==start:
        def_line_idx=i; break
    pos += len(ln)
if def_line_idx is None:
    raise SystemExit("[ERR] internal idx error")

# end idx
end_idx=len(lines)
for j in range(def_line_idx+1, len(lines)):
    ln=lines[j]
    if ln.strip()=="":
        continue
    if re.match(rf'^{re.escape(ind)}(def\s+|class\s+|@)', ln):
        end_idx=j; break

block="".join(lines[def_line_idx:end_idx])
if "### [COMMERCIAL] EXPORT_FORCEFS_V2 ###" not in block:
    raise SystemExit("[ERR] expected EXPORT_FORCEFS_V2 marker not found in _vsp_export_v3_override (did you patch V2?)")

# Replace ONLY the find_run_dir() function inside the override block
# We search inside block for "def find_run_dir(" and replace its body until next "def " at same indent+4.
pat = r'(?ms)^\s*def\s+find_run_dir\s*\(rid_norm:\s*str\)\s*:\s*.*?(?=^\s*def\s+ensure_report\s*\()'
mm = re.search(pat, block)
if not mm:
    raise SystemExit("[ERR] cannot find find_run_dir(...) inside override block")

new_find = """
    def find_run_dir(rid_norm: str):
        # 1) Strong source of truth: run_status_v2
        try:
            fn_status = current_app.view_functions.get('api_vsp_run_status_v2_winlast_v6')
            if fn_status:
                r = fn_status(rid)  # may return (resp,code) or resp
                # normalize to dict
                payload = None
                if isinstance(r, tuple) and len(r) >= 1:
                    payload = r[0].get_json(silent=True) if hasattr(r[0], "get_json") else None
                else:
                    payload = r.get_json(silent=True) if hasattr(r, "get_json") else None
                if isinstance(payload, dict):
                    rd = payload.get('ci_run_dir') or payload.get('ci') or payload.get('run_dir')
                    if isinstance(rd, str) and rd and os.path.isdir(rd):
                        return rd
        except Exception:
            pass

        # 2) Fallback glob by rid_norm
        cands = []
        cands += glob.glob('/home/test/Data/SECURITY-*/out_ci/' + rid_norm)
        cands += glob.glob('/home/test/Data/*/out_ci/' + rid_norm)
        for x in cands:
            try:
                if os.path.isdir(x):
                    return x
            except Exception:
                pass
        return None
"""

block2 = block[:mm.start()] + new_find + block[mm.end():]
lines2 = lines[:def_line_idx] + [block2] + lines[end_idx:]
p.write_text("".join(lines2), encoding="utf-8")
print("[OK] patched find_run_dir() to use run_status_v2 first")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
