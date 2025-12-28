#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, time, py_compile

TS = time.strftime("%Y%m%d_%H%M%S")

FILES = [Path("wsgi_vsp_ui_gateway.py"), Path("vsp_demo_app.py")]
FILES = [p for p in FILES if p.exists()]
if not FILES:
    raise SystemExit("[ERR] missing wsgi_vsp_ui_gateway.py/vsp_demo_app.py")

MARKERS = [
  "VSP_P1_AFTERREQ_OKWRAP_RUNFILEALLOW_V1",
  "VSP_P1_AFTER_REQUEST_OKWRAP_RUNGATE_SUMMARY_V2",
]

def patch_one(p: Path) -> int:
    s = p.read_text(encoding="utf-8", errors="replace")
    bak = p.with_name(p.name + f".bak_passthroughfix_{TS}")
    bak.write_text(s, encoding="utf-8")
    print("[BACKUP]", bak)

    total = 0
    for mk in MARKERS:
        if mk not in s:
            continue

        # find the function body inside the marker block and patch the first `txt = resp.get_data(` occurrence AFTER the marker
        # Insert:
        #   try: resp.direct_passthrough = False
        #   except: pass
        idx = s.find(mk)
        if idx < 0:
            continue
        tail = s[idx: idx + 20000]  # enough window
        m = re.search(r"(?m)^(?P<ind>\s*)txt\s*=\s*resp\.get_data\(", tail)
        if not m:
            continue
        ind = m.group("ind")
        inject = (
            f"{ind}try:\n"
            f"{ind}    resp.direct_passthrough = False\n"
            f"{ind}except Exception:\n"
            f"{ind}    pass\n"
        )
        # ensure not already injected right above
        pre_start = idx + m.start()
        pre = s[max(0, pre_start-300):pre_start]
        if "direct_passthrough" in pre:
            continue

        s = s[:pre_start] + inject + s[pre_start:]
        total += 1

    p.write_text(s, encoding="utf-8")
    py_compile.compile(str(p), doraise=True)
    return total

n_sum = 0
for p in FILES:
    n = patch_one(p)
    print("[OK] patched", p, "count=", n)
    n_sum += n

if n_sum == 0:
    raise SystemExit("[ERR] no marker/get_data() spot patched. (Maybe marker blocks changed?)")

print("[DONE] passthrough disable injected total=", n_sum)
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] restart done. Now verify with curl."
