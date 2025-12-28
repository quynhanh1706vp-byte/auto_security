#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

cp -f "$W" "${W}.bak_p3k26_v26_${TS}"
echo "[BACKUP] ${W}.bak_p3k26_v26_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

TAG="P3K26_CACHEHOT_SILENT_DEFAULT_OFF_V26"
if TAG in s:
    print("[OK] already V26")
    raise SystemExit(0)

# (1) Make V25 lazy-starter require explicit enable flag
# Replace the V25 start_once gate if present
pat = r"(def __vsp_cachehot_v25_start_once\(\):\s*\n)([ \t]+global __vsp_cachehot_v25_started\s*\n)(.*?)(\n\s*#|\n\s*def |\Z)"
m = re.search(pat, s, flags=re.S)
if m:
    body = m.group(3)
    # ensure we short-circuit unless enabled
    if "VSP_CACHEHOT_ENABLE" not in body:
        inject = (
            "    # V26: cachehot is OFF by default (commercial clean logs)\n"
            "    if _vsp_os.environ.get(\"VSP_CACHEHOT_ENABLE\",\"0\") != \"1\":\n"
            "        return\n"
        )
        # place right after global or near top of function body
        s = s[:m.start(3)] + inject + s[m.start(3):]
else:
    print("[WARN] could not locate __vsp_cachehot_v25_start_once; will still mute NOT FOUND logs")

# (2) Mute any prints/logs that contain "cachehot: endpoint NOT FOUND"
lines=s.splitlines(True)
out=[]
muted=0
for ln in lines:
    if "cachehot: endpoint NOT FOUND" in ln:
        out.append("# P3K26_V26_MUTED_CACHEHOT_NOT_FOUND: " + ln)
        muted += 1
    else:
        out.append(ln)
s="".join(out)

# (3) Tag
s = s + f"\n# {TAG}\n"

p.write_text(s, encoding="utf-8")
print(f"[OK] V26 patched: muted_not_found_lines={muted}")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC" || true
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -fsS --connect-timeout 1 --max-time 5 "$BASE/api/vsp/rid_latest" | head -c 220; echo || true
echo "[DONE] v26"
