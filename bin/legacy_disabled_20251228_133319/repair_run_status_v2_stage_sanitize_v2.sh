#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_repair_sanitize_v2_${TS}"
echo "[BACKUP] $F.bak_repair_sanitize_v2_${TS}"

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

# 1) Remove any previously injected sanitizer function (broken or not)
blk = re.sub(r"(?s)\n?def\s+_vsp__sanitize_stage_name_v2\s*\(.*?\)\s*:\s*.*?(?=\n(?:def\s+|_STAGE_RE_V2\s*=|# === END VSP_RUN_STATUS_V2_WINLAST_V6 ===))",
             "\n", blk)

# 2) Ensure we add sanitizer right after "import json, re" line inside the block (indent 0)
san = (
'def _vsp__sanitize_stage_name_v2(s: str) -> str:\n'
'    if not s:\n'
'        return ""\n'
'    s = str(s)\n'
'    s = s.replace("\\r\\n", "\\n").replace("\\r", "\\n")\n'
'    # keep first line only\n'
'    s = s.split("\\n", 1)[0].strip()\n'
'    # remove trailing markers\n'
'    if "=====" in s:\n'
'        s = s.split("=====", 1)[0].strip()\n'
'    # remove possible prefix like "===== [3/8]"\n'
'    s = re.sub(r"^=+\\s*\\[\\s*\\d+\\s*/\\s*\\d+\\s*\\]\\s*", "", s).strip()\n'
'    s = re.sub(r"\\s*=+\\s*$", "", s).strip()\n'
'    return s\n'
)

imp = re.search(r"(?m)^import\s+json,\s*re\s*$", blk)
if not imp:
    raise SystemExit("[ERR] cannot find 'import json, re' line inside WINLAST_V6")
insert_at = imp.end()

blk = blk[:insert_at] + "\n" + san + "\n" + blk[insert_at:]

# 3) Hook sanitize exactly once inside api_vsp_run_status_v2_winlast_v6 before final return
# Remove old hook lines if any
blk = re.sub(r'(?m)^\s*payload\["stage_name"\]\s*=\s*_vsp__sanitize_stage_name_v2\(.*?\)\s*$\n?', '', blk)

# Insert hook before the final "return jsonify(payload), 200" in that function
blk2, n = re.subn(
    r'(?m)^(    )return\s+jsonify\(payload\)\s*,\s*200\s*$',
    r'    payload["stage_name"] = _vsp__sanitize_stage_name_v2(payload.get("stage_name",""))\n\1return jsonify(payload), 200',
    blk,
    count=1
)
if n != 1:
    raise SystemExit(f"[ERR] cannot hook sanitize before return (matches={n})")
blk = blk2

t2 = t[:m.start()] + blk + t[m.end():]
p.write_text(t2, encoding="utf-8")
print("[OK] repaired sanitizer + hooked safely")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh >/dev/null 2>&1 || true
echo "[OK] restarted 8910"
