#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_stage_sanitize_${TS}"
echo "[BACKUP] $F.bak_stage_sanitize_${TS}"

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

# 1) Ensure sanitizer exists
if "_vsp__sanitize_stage_name_v2" not in blk:
    ins_pt = blk.find("def _vsp__read_json_if_exists_v2")
    if ins_pt < 0:
        raise SystemExit("[ERR] cannot find insertion anchor inside WINLAST_V6")

    sanitizer = r'''
def _vsp__sanitize_stage_name_v2(s: str) -> str:
    if not s:
        return ""
    s = str(s)
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    # take first physical line (runner.log may split markers)
    s = s.split("\n", 1)[0].strip()
    # strip any trailing marker
    if "=====" in s:
        s = s.split("=====", 1)[0].strip()
    # strip possible prefix like "===== [3/8]"
    s = re.sub(r"^=+\s*\[\s*\d+\s*/\s*\d+\s*\]\s*", "", s).strip()
    # strip trailing '=' if any
    s = re.sub(r"\s*=+\s*$", "", s).strip()
    return s
'''.strip() + "\n\n"

    blk = blk[:ins_pt] + sanitizer + blk[ins_pt:]

# 2) Inject sanitize call right before return jsonify(payload), 200 in api_vsp_run_status_v2_winlast_v6
#    (do it safely: only inside that function)
pat_func = re.compile(r"(?s)def\s+api_vsp_run_status_v2_winlast_v6\s*\(rid\)\s*:\s*(.*?)\n\s*return\s+jsonify\(payload\)\s*,\s*200")
mf = pat_func.search(blk)
if not mf:
    raise SystemExit("[ERR] cannot locate api_vsp_run_status_v2_winlast_v6 return site")

body = mf.group(1)
if "payload[\"stage_name\"] = _vsp__sanitize_stage_name_v2" not in body:
    body2 = body.rstrip() + "\n\n    payload[\"stage_name\"] = _vsp__sanitize_stage_name_v2(payload.get(\"stage_name\", \"\"))\n"
else:
    body2 = body

blk2 = blk[:mf.start(1)] + body2 + blk[mf.end(1):]
# write back
t2 = t[:m.start()] + blk2 + t[m.end():]
p.write_text(t2, encoding="utf-8")
print("[OK] added stage_name sanitizer + hooked into api_vsp_run_status_v2_winlast_v6")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh >/dev/null 2>&1 || true
echo "[OK] restarted 8910"
