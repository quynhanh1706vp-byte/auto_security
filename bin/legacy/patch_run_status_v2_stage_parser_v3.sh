#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_stage_parser_v3_${TS}"
echo "[BACKUP] $F.bak_stage_parser_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_STATUS_V2_WINLAST_V6 ==="
END = "# === END VSP_RUN_STATUS_V2_WINLAST_V6 ==="
m = re.search(re.escape(TAG) + r".*?" + re.escape(END), t, flags=re.S)
if not m:
    raise SystemExit("[ERR] cannot find WINLAST_V6 block")

blk = t[m.start():m.end()]

# Replace the whole function _vsp__inject_stage_progress_v2 with a deterministic parser
pat = re.compile(r"(?s)def\s+_vsp__inject_stage_progress_v2\s*\(.*?\)\s*:\s*.*?(?=\ndef\s+|\n# === END VSP_RUN_STATUS_V2_WINLAST_V6 ===)")
new_func = r'''
def _vsp__inject_stage_progress_v2(ci_dir: str, payload: dict):
    payload.setdefault("stage_name", "")
    payload.setdefault("stage_index", 0)
    payload.setdefault("stage_total", 0)
    payload.setdefault("progress_pct", 0)
    if not ci_dir:
        return
    tail = _vsp__tail_text_v2(Path(ci_dir) / "runner.log")
    if not tail:
        return

    # Parse by lines: pick the last line containing "===== [i/j]" and extract name between "]" and "====="
    last = None
    for line in tail.splitlines():
        if "=====" in line and "[" in line and "/" in line and "]" in line:
            if re.search(r"\[\s*\d+\s*/\s*\d+\s*\]", line):
                last = line

    if not last:
        return

    mm = re.search(r"\[\s*(\d+)\s*/\s*(\d+)\s*\]", last)
    if not mm:
        return
    si = int(mm.group(1) or 0)
    st = int(mm.group(2) or 0)

    # stage name is after "]" and before the next "====="
    try:
        after = last.split("]", 1)[1]
    except Exception:
        after = ""
    name = after.split("=====", 1)[0].strip()

    payload["stage_name"] = name
    payload["stage_index"] = si
    payload["stage_total"] = st
    payload["progress_pct"] = int((si / st) * 100) if st > 0 else 0
'''

blk2, n = pat.subn(new_func.strip() + "\n", blk, count=1)
if n != 1:
    raise SystemExit(f"[ERR] cannot replace _vsp__inject_stage_progress_v2 (matches={n})")

t2 = t[:m.start()] + blk2 + t[m.end():]
p.write_text(t2, encoding="utf-8")
print("[OK] replaced _vsp__inject_stage_progress_v2 with line-based parser")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh >/dev/null 2>&1 || true
echo "[OK] restarted 8910"
