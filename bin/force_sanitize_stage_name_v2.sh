#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_force_stage_sanitize_${TS}"
echo "[BACKUP] $F.bak_force_stage_sanitize_${TS}"

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

# ensure sanitizer exists (if not, add minimal one right after "import json, re")
if "_vsp__sanitize_stage_name_v2" not in blk:
    blk = re.sub(r"(?m)^import\s+json,\s*re\s*$",
                 "import json, re\n\ndef _vsp__sanitize_stage_name_v2(s: str) -> str:\n"
                 "    if not s:\n        return \"\"\n"
                 "    s = str(s).replace(\"\\r\\n\",\"\\n\").replace(\"\\r\",\"\\n\")\n"
                 "    s = s.split(\"\\n\", 1)[0].strip()\n"
                 "    if \"=====\" in s:\n        s = s.split(\"=====\", 1)[0].strip()\n"
                 "    s = re.sub(r\"^=+\\s*\\[\\s*\\d+\\s*/\\s*\\d+\\s*\\]\\s*\", \"\", s).strip()\n"
                 "    s = re.sub(r\"\\s*=+\\s*$\", \"\", s).strip()\n"
                 "    return s\n",
                 blk, count=1)

# Force sanitize right before final return (overwrite any previous hook)
blk = re.sub(r'(?m)^\s*payload\["stage_name"\]\s*=\s*_vsp__sanitize_stage_name_v2\(.*?\)\s*$\n?', '', blk)

blk2, n = re.subn(
    r'(?m)^(    )return\s+jsonify\(payload\)\s*,\s*200\s*$',
    r'    payload["stage_name"] = _vsp__sanitize_stage_name_v2(payload.get("stage_name",""))\n\1return jsonify(payload), 200',
    blk,
    count=1
)
if n != 1:
    raise SystemExit(f"[ERR] cannot hook sanitize before return (matches={n})")

t2 = t[:m.start()] + blk2 + t[m.end():]
p.write_text(t2, encoding="utf-8")
print("[OK] forced sanitize hook at final return")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh >/dev/null 2>&1 || true
echo "[OK] restarted 8910"
